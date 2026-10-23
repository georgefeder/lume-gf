import Foundation
import OSLog
import SwiftData

/// The stored listings' comparable content: loaded once per refresh and kept in step as sources apply changes.
nonisolated final class GuideStoredIndex {
    var rows: [String: GuideDiffPlanner.Stored]

    init(rows: [String: GuideDiffPlanner.Stored]) {
        self.rows = rows
    }
}

/// Applies a guide file to Lume's stored listings, writing only what changed (`GuideDiffPlanner`).
nonisolated struct GuideListingApplier {
    struct Result: Equatable {
        var inserted = 0
        var updated = 0
        var deleted = 0
        var completed = false
        var claimedChannels: Set<String> = []
    }

    /// Like Lume's own import: every save re-runs each active `@Query`, so saves are coalesced.
    static let saveThreshold = 10000
    static let deleteChunk = 500

    let container: ModelContainer
    /// Rows per page when reading the stored guide.
    var pageSize = 5000

    /// How long a guide may go without a complete import before the programmes long over are cleared ahead of the
    /// next one (`GuideRefresher`), and how far back that clearing starts at the latest.
    static let pruneAfter: TimeInterval = 24 * 60 * 60

    /// Deletes the programmes that ended before `cutoff`, oldest first a day (or a thirtieth of the span) at a time,
    /// each step saved so a stop keeps what is done, and returns how many went. An import only deletes once it has
    /// read its whole file, so a guide whose imports kept being cut off gained a day of programmes every day and lost
    /// none, each try slower than the last (Georgs' iPhone, 14-23 Oct: no complete import for nine days).
    func deleteEnded(before cutoff: Date) -> Int {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var oldest = FetchDescriptor<EPGListing>(sortBy: [SortDescriptor(\.end)])
        oldest.fetchLimit = 1
        oldest.propertiesToFetch = [\.end]
        guard var dayEnd = (try? context.fetch(oldest))?.first?.end, dayEnd < cutoff else { return 0 }
        var removed = 0
        let step = max(24 * 60 * 60, cutoff.timeIntervalSince(dayEnd) / 30) // about 30 saves however old it is
        while dayEnd < cutoff, !Task.isCancelled {
            dayEnd = min(dayEnd.addingTimeInterval(step), cutoff)
            let limit = dayEnd
            let gone = #Predicate<EPGListing> { $0.end < limit }
            do {
                let count = try context.fetchCount(FetchDescriptor(predicate: gone))
                try context.delete(model: EPGListing.self, where: gone)
                try context.save()
                removed += count
            } catch {
                let text = "Guide: clearing programmes long over stopped (\(GuideRefresher.reason(error)))"
                Logger.database.info("\(text, privacy: .public)")
                break
            }
        }
        return removed
    }

    /// The earliest programme start in a guide file, from a quick scan of its ` start="…"` attributes (no XML parse;
    /// the times read like the import reads them). Nil when it finds none.
    static func earliestStart(inFileAt url: URL) -> Date? {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        let key = Array(" start=\"".utf8), quote = UInt8(ascii: "\"")
        var earliest: Date?
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count, let hit = memmem(base + offset, raw.count - offset, key, key.count) {
                let valueStart = base.distance(to: UnsafeRawPointer(hit)) + key.count
                var end = valueStart
                while end < raw.count, raw[end] != quote, end - valueStart < 40 { end += 1 }
                if end < raw.count, raw[end] == quote,
                   let date = XMLTVDate.parse(String(decoding: raw[valueStart ..< end], as: UTF8.self)),
                   earliest.map({ date < $0 }) ?? true {
                    earliest = date
                }
                offset = end
            }
        }
        return earliest
    }

    /// Every stored listing's comparable content, read in pages with only the compared fields. (Paging by "id after
    /// the last one" skipped rows: the store sorts ids its own way, not as `>` compares them.)
    func loadStored() -> [String: GuideDiffPlanner.Stored] {
        var stored: [String: GuideDiffPlanner.Stored] = [:]
        var offset = 0
        var fetched = pageSize
        while fetched == pageSize {
            if Task.isCancelled { break }
            fetched = autoreleasepool {
                let context = ModelContext(container)
                var descriptor = FetchDescriptor<EPGListing>(sortBy: [SortDescriptor(\.id)])
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = pageSize
                descriptor.propertiesToFetch = [\.id, \.channelId, \.start, \.end, \.title, \.subtitle, \.category,
                                                \.listingDescription]
                let rows = (try? context.fetch(descriptor)) ?? []
                for row in rows {
                    stored[row.id] = GuideDiffPlanner.Stored(
                        channelId: row.channelId, start: row.start, end: row.end,
                        fingerprint: GuideFingerprint.of(end: row.end, title: row.title, subtitle: row.subtitle,
                                                         category: row.category, description: row.listingDescription)
                    )
                }
                return rows.count
            }
            offset += pageSize
        }
        return stored
    }

    /// Reads `fileURL` and applies it: inserts and updates batch by batch; deletions (and dropping old programmes)
    /// only when the file was read completely. `shouldStop` is asked after each batch (a background task's time).
    /// `allChannels`: every channel of every playlist; old programmes of channels outside it are dropped too.
    /// `nowFirst` (a stale stored guide, `GuideDiffPlanner.wantsNowFirst`): the programmes it overlaps are read and
    /// saved first, then `onNowReady` runs (the guide screens show them), then the whole file.
    func apply(fileURL: URL, claimableChannels: Set<String>, index: GuideStoredIndex, now: Date,
               allChannels: Set<String>? = nil, nowFirst: DateInterval? = nil, onNowReady: () -> Void = {},
               shouldStop: @escaping () -> Bool = { Task.isCancelled }) -> Result {
        // the planner takes the rows over while the file is read (a shared dictionary is copied whole on its first
        // change); they come back, with this file's changes, at the end
        let rows = index.rows
        index.rows = [:]
        let run = Run(
            planner: GuideDiffPlanner(stored: rows, claimableChannels: claimableChannels, now: now,
                                      allChannels: allChannels),
            context: ModelContext(container)
        )
        var parse = (count: 0, completed: true)
        if let nowFirst {
            parse = XMLTVParser.parseChecked(fileURL: fileURL, batchSize: 2000, shouldStop: shouldStop) { batch in
                autoreleasepool { run.apply(batch.filter { $0.end > nowFirst.start && $0.start < nowFirst.end }) }
            }
            try? run.context.save()
            run.pending = 0
            if parse.completed { onNowReady() }
        }
        if parse.completed {
            // the programmes taken first are seen already: the planner skips them
            parse = XMLTVParser.parseChecked(fileURL: fileURL, batchSize: 2000, shouldStop: shouldStop) { batch in
                autoreleasepool { run.apply(batch) }
            }
        }
        var result = run.result
        result.completed = parse.completed
        result.claimedChannels = run.planner.claimedChannels
        let deletions = run.planner.deletions(fileCompleted: parse.completed)
        var start = 0
        while start < deletions.count {
            let chunk = Array(deletions[start ..< min(start + Self.deleteChunk, deletions.count)])
            try? run.context.delete(model: EPGListing.self, where: #Predicate { chunk.contains($0.id) })
            start += Self.deleteChunk
        }
        var stored = run.planner.releaseStored()
        for (id, row) in run.changed {
            stored[id] = row
        }
        for id in deletions {
            stored[id] = nil
        }
        index.rows = stored
        result.deleted = deletions.count
        try? run.context.save()
        return result
    }

    static func stored(_ p: ParsedProgramme) -> GuideDiffPlanner.Stored {
        GuideDiffPlanner.Stored(channelId: p.channelId, start: p.start, end: p.end, fingerprint: fingerprint(p))
    }

    static func fingerprint(_ p: ParsedProgramme) -> UInt64 {
        GuideFingerprint.of(end: p.end, title: p.title, subtitle: p.subtitle,
                            category: GuideFingerprint.category(p.categories), description: p.description)
    }

    /// Mutable state shared with the parser's batch callback.
    private nonisolated final class Run {
        var planner: GuideDiffPlanner
        let context: ModelContext
        /// What this file inserted or changed, merged into the stored rows at the end.
        var changed: [String: GuideDiffPlanner.Stored] = [:]
        var result = Result()
        var pending = 0

        init(planner: GuideDiffPlanner, context: ModelContext) {
            self.planner = planner
            self.context = context
            context.autosaveEnabled = false
        }

        func apply(_ batch: [ParsedProgramme]) {
            var byID: [String: ParsedProgramme] = [:]
            let incoming = batch.map { p -> GuideDiffPlanner.Incoming in
                let id = GuideDiffPlanner.id(channelId: p.channelId, start: p.start)
                if byID[id] == nil { byID[id] = p }
                return .init(id: id, channelId: p.channelId, start: p.start, end: p.end,
                             fingerprint: GuideListingApplier.fingerprint(p))
            }
            let plan = planner.plan(incoming)
            for id in plan.inserts {
                guard let p = byID[id] else { continue }
                context.insert(EPGListing(
                    id: id, channelId: p.channelId, title: p.title, listingDescription: p.description,
                    start: p.start, end: p.end, subtitle: p.subtitle, category: GuideFingerprint.category(p.categories)
                ))
                changed[id] = GuideListingApplier.stored(p)
            }
            // the batch's changed programmes in one fetch, not one each
            let updateIDs = plan.updates
            let rows = updateIDs.isEmpty ? [] : (try? context.fetch(FetchDescriptor<EPGListing>(
                predicate: #Predicate { updateIDs.contains($0.id) }
            ))) ?? []
            var rowByID: [String: EPGListing] = [:]
            for row in rows {
                rowByID[row.id] = row
            }
            for id in plan.updates {
                guard let p = byID[id], let row = rowByID[id] else { continue }
                row.title = p.title
                row.listingDescription = p.description
                row.end = p.end
                row.subtitle = p.subtitle
                row.category = GuideFingerprint.category(p.categories)
                changed[id] = GuideListingApplier.stored(p)
            }
            result.inserted += plan.inserts.count
            result.updated += plan.updates.count
            pending += plan.inserts.count + plan.updates.count
            if pending >= GuideListingApplier.saveThreshold {
                try? context.save()
                pending = 0
            }
        }
    }
}
