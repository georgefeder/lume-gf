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

    /// Like Lume's own import: every save re-runs each active `@Query`, so saves are coalesced. In a short background
    /// wake every batch is saved (`wakeSaveThreshold`): nothing is on screen, and iOS may end the wake at any batch.
    static let saveThreshold = 10000
    static let wakeSaveThreshold = 2000
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
        while dayEnd < cutoff, !GFGuidePause.stopOrWait() { // no saves while video plays
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
            if GFGuidePause.stopOrWait() { break } // video playing: waits (reading 100,000 rows is no light work)
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
    /// only when the file was read completely. `shouldStop` is asked after each batch (a background task's time;
    /// by default it also waits there while video plays, GFGuidePause).
    /// `allChannels`: every channel of every playlist; old programmes of channels outside it are dropped too.
    /// `nowFirst` (a stale stored guide, `GuideDiffPlanner.wantsNowFirst`): the programmes it overlaps are read and
    /// saved first, then `onNowReady` runs (the guide screens show them), then the whole file.
    func apply(fileURL: URL, claimableChannels: Set<String>, index: GuideStoredIndex, now: Date,
               allChannels: Set<String>? = nil, nowFirst: DateInterval? = nil, onNowReady: () -> Void = {},
               saveEvery: Int = saveThreshold,
               shouldStop: @escaping () -> Bool = GFGuidePause.stopOrWait) -> Result {
        // the planner takes the rows over while the file is read (a shared dictionary is copied whole on its first
        // change); they come back, with this file's changes, at the end
        let rows = index.rows
        index.rows = [:]
        let run = Run(
            planner: GuideDiffPlanner(stored: rows, claimableChannels: claimableChannels, now: now,
                                      allChannels: allChannels),
            context: ModelContext(container),
            saveEvery: saveEvery
        )
        var parse = (count: 0, completed: true)
        if let nowFirst {
            parse = XMLTVParser.parseChecked(fileURL: fileURL, batchSize: 2000, shouldStop: shouldStop) { batch in
                autoreleasepool { run.apply(batch.filter { $0.end > nowFirst.start && $0.start < nowFirst.end }) }
            }
            GFGuidePause.shared.waitWhileHeld() // no write while video plays
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
            GFGuidePause.shared.waitWhileHeld() // no write while video plays
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
        GFGuidePause.shared.waitWhileHeld() // no write while video plays
        try? run.context.save()
        return result
    }

    /// Applies the server's change file (`GuideDelta`): its programmes are new or changed and go in by id, each
    /// batch's stored rows fetched in one go; `removed` (ids of programmes gone before they ended) are deleted once the
    /// file was read to the end. Nothing else of the stored guide is read: that is what made a whole import too slow for a
    /// background wake. Saved in batches and at the end, so a stop keeps what is done (the same file applied again
    /// writes nothing twice: a stored programme that is the same is left alone). `window`: only the programmes it
    /// overlaps (what is on now, ahead of the rest of a whole guide taken in this way, GuideRefresher).
    func applyChanges(fileURL: URL, claimableChannels: Set<String>, removed: [String], window: DateInterval? = nil,
                      saveEvery: Int = saveThreshold,
                      shouldStop: @escaping () -> Bool = GFGuidePause.stopOrWait, sweep: Sweep? = nil) -> Result {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let run = ChangeRun()
        let parse = XMLTVParser.parseChecked(fileURL: fileURL, batchSize: 2000, shouldStop: shouldStop) { batch in
            autoreleasepool {
                var byID: [String: ParsedProgramme] = [:]
                for p in batch where claimableChannels.contains(p.channelId) {
                    if let window, p.end <= window.start || p.start >= window.end { continue }
                    let id = GuideDiffPlanner.id(channelId: p.channelId, start: p.start)
                    if byID[id] == nil { byID[id] = p }
                }
                guard !byID.isEmpty else { return }
                if let sweep {
                    for (id, p) in byID {
                        sweep.see(id: id, channelId: p.channelId, start: p.start)
                    }
                }
                let ids = Array(byID.keys)
                let rows = (try? context.fetch(FetchDescriptor<EPGListing>(
                    predicate: #Predicate { ids.contains($0.id) }
                ))) ?? []
                var written = byID.count
                for row in rows {
                    guard let p = byID.removeValue(forKey: row.id) else { continue }
                    run.result.claimedChannels.insert(p.channelId)
                    let same = GuideFingerprint.of(end: row.end, title: row.title, subtitle: row.subtitle,
                                                   category: row.category, description: row.listingDescription)
                        == Self.fingerprint(p)
                    if same {
                        written -= 1
                        continue
                    }
                    row.title = p.title
                    row.listingDescription = p.description
                    row.end = p.end
                    row.subtitle = p.subtitle
                    row.category = GuideFingerprint.category(p.categories)
                    run.result.updated += 1
                }
                for (id, p) in byID {
                    context.insert(EPGListing(
                        id: id, channelId: p.channelId, title: p.title, listingDescription: p.description,
                        start: p.start, end: p.end, subtitle: p.subtitle,
                        category: GuideFingerprint.category(p.categories)
                    ))
                    run.result.inserted += 1
                    run.result.claimedChannels.insert(p.channelId)
                }
                run.pending += written
                if run.pending >= saveEvery {
                    GFGuidePause.shared.waitWhileHeld() // no write while video plays
                    try? context.save()
                    run.pending = 0
                }
            }
        }
        var result = run.result
        result.completed = parse.completed
        if parse.completed {
            var start = 0
            while start < removed.count {
                let chunk = Array(removed[start ..< min(start + Self.deleteChunk, removed.count)])
                GFGuidePause.shared.waitWhileHeld() // no write while video plays
                try? context.delete(model: EPGListing.self, where: #Predicate { chunk.contains($0.id) })
                start += Self.deleteChunk
            }
            result.deleted = removed.count
        }
        GFGuidePause.shared.waitWhileHeld() // no write while video plays
        try? context.save()
        return result
    }

    /// A whole guide file applied without reading the stored guide first (GuideRefresher): its programmes go in by id
    /// as in `applyChanges` (what is on now first when `nowFirst` is given), saved every batch, so a stop keeps what is
    /// done and the next try writes nothing twice. Once the file is read to the end, `sweepGone` drops what it no
    /// longer has. Reading the ~300,000 stored programmes first took about 5 minutes on the iPhone and never fitted the
    /// overnight import (21 Nov 2026: cut off at the same point every night; "Sync Now" spun for minutes).
    func applyWhole(fileURL: URL, claimableChannels: Set<String>, now: Date, allChannels: Set<String>? = nil,
                    nowFirst: DateInterval? = nil, onNowReady: () -> Void = {}, saveEvery: Int = saveThreshold,
                    shouldStop: @escaping () -> Bool = GFGuidePause.stopOrWait) -> Result {
        var first = Result()
        if let nowFirst {
            first = applyChanges(fileURL: fileURL, claimableChannels: claimableChannels, removed: [], window: nowFirst,
                                 saveEvery: saveEvery, shouldStop: shouldStop)
            guard first.completed else { return first }
            onNowReady()
        }
        // the second pass finds the first one's programmes the same; only it sees the whole span of each channel
        let sweep = Sweep()
        var result = applyChanges(fileURL: fileURL, claimableChannels: claimableChannels, removed: [],
                                  saveEvery: saveEvery, shouldStop: shouldStop, sweep: sweep)
        result.inserted += first.inserted
        result.updated += first.updated
        result.claimedChannels = Set(sweep.firstStart.keys)
        guard result.completed else { return result }
        let swept = sweepGone(sweep, now: now, allChannels: allChannels, shouldStop: shouldStop)
        result.deleted = swept.deleted
        result.completed = swept.completed
        return result
    }

    /// GuideDiffPlanner's deletion rules without the stored guide in memory, one channel at a time: a stored programme
    /// of a channel the file guides goes when the file no longer has it and it starts within the span the file covers
    /// on that channel, or ended more than 12 hours ago; the long-over programmes of channels no playlist has any more
    /// (`allChannels`) go too. Not completed when stopped (the next whole import sweeps again).
    func sweepGone(_ sweep: Sweep, now: Date, allChannels: Set<String>?,
                   shouldStop: () -> Bool = GFGuidePause.stopOrWait) -> (deleted: Int, completed: Bool) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let cutoff = now.addingTimeInterval(-GuideDiffPlanner.keepPast)
        var deleted = 0
        var pending = 0
        func save() {
            GFGuidePause.shared.waitWhileHeld() // no write while video plays
            try? context.save()
            pending = 0
        }
        for channel in sweep.firstStart.keys.sorted() {
            if shouldStop() {
                save()
                return (deleted, false)
            }
            guard let first = sweep.firstStart[channel] else { continue }
            let kept = Array(sweep.seen[channel] ?? [])
            let gone = #Predicate<EPGListing> {
                $0.channelId == channel && ($0.start >= first || $0.end < cutoff) && !kept.contains($0.id)
            }
            let count = (try? context.fetchCount(FetchDescriptor(predicate: gone))) ?? 0
            guard count > 0 else { continue }
            try? context.delete(model: EPGListing.self, where: gone)
            deleted += count
            pending += count
            if pending >= Self.deleteChunk { save() }
        }
        if let allChannels {
            let all = Array(allChannels)
            let orphaned = #Predicate<EPGListing> { $0.end < cutoff && !all.contains($0.channelId) }
            let count = (try? context.fetchCount(FetchDescriptor(predicate: orphaned))) ?? 0
            if count > 0 {
                try? context.delete(model: EPGListing.self, where: orphaned)
                deleted += count
            }
        }
        save()
        return (deleted, true)
    }

    /// Whether the stored guide has gone stale for `channels` (GuideDiffPlanner.wantsNowFirst), from one count of the
    /// programmes on now instead of the whole stored guide.
    func wantsNowFirst(channels: Set<String>, now: Date) -> Bool {
        guard !channels.isEmpty else { return false }
        let ids = Array(channels)
        let onNow = #Predicate<EPGListing> { $0.start <= now && $0.end > now && ids.contains($0.channelId) }
        let count = (try? ModelContext(container).fetchCount(FetchDescriptor(predicate: onNow))) ?? 0
        return count * 2 < channels.count
    }

    /// What a whole file's pass saw of each channel, for `sweepGone`.
    nonisolated final class Sweep {
        var seen: [String: Set<String>] = [:]
        var firstStart: [String: Date] = [:]

        func see(id: String, channelId: String, start: Date) {
            seen[channelId, default: []].insert(id)
            if firstStart[channelId].map({ start < $0 }) ?? true { firstStart[channelId] = start }
        }
    }

    static func stored(_ p: ParsedProgramme) -> GuideDiffPlanner.Stored {
        GuideDiffPlanner.Stored(channelId: p.channelId, start: p.start, end: p.end, fingerprint: fingerprint(p))
    }

    static func fingerprint(_ p: ParsedProgramme) -> UInt64 {
        GuideFingerprint.of(end: p.end, title: p.title, subtitle: p.subtitle,
                            category: GuideFingerprint.category(p.categories), description: p.description)
    }

    /// `applyChanges`' counts, shared with the parser's batch callback.
    private nonisolated final class ChangeRun {
        var result = Result()
        var pending = 0
    }

    /// Mutable state shared with the parser's batch callback.
    private nonisolated final class Run {
        var planner: GuideDiffPlanner
        let context: ModelContext
        /// What this file inserted or changed, merged into the stored rows at the end.
        var changed: [String: GuideDiffPlanner.Stored] = [:]
        var result = Result()
        var pending = 0
        let saveEvery: Int

        init(planner: GuideDiffPlanner, context: ModelContext, saveEvery: Int) {
            self.planner = planner
            self.context = context
            self.saveEvery = saveEvery
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
            if pending >= saveEvery {
                GFGuidePause.shared.waitWhileHeld() // no write while video plays
                try? context.save()
                pending = 0
            }
        }
    }
}
