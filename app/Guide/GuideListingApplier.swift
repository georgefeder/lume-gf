import Foundation
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
    static let pageSize = 5000
    static let deleteChunk = 500

    let container: ModelContainer

    /// Every stored listing's comparable content, read in pages with only the compared fields.
    func loadStored() -> [String: GuideDiffPlanner.Stored] {
        var stored: [String: GuideDiffPlanner.Stored] = [:]
        var offset = 0
        var fetched = Self.pageSize
        while fetched == Self.pageSize {
            fetched = autoreleasepool {
                let context = ModelContext(container)
                var descriptor = FetchDescriptor<EPGListing>(sortBy: [SortDescriptor(\.id)])
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = Self.pageSize
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
            offset += Self.pageSize
        }
        return stored
    }

    /// Reads `fileURL` and applies it: inserts and updates batch by batch; deletions (and dropping old programmes)
    /// only when the file was read completely. `shouldStop` is asked after each batch (a background task's time).
    func apply(fileURL: URL, claimableChannels: Set<String>, index: GuideStoredIndex, now: Date,
               shouldStop: @escaping () -> Bool = { Task.isCancelled }) -> Result {
        let run = Run(
            planner: GuideDiffPlanner(stored: index.rows, claimableChannels: claimableChannels, now: now),
            context: ModelContext(container), index: index
        )
        let parse = XMLTVParser.parseChecked(fileURL: fileURL, batchSize: 2000, shouldStop: shouldStop) { batch in
            autoreleasepool { run.apply(batch) }
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
        for id in deletions {
            index.rows[id] = nil
        }
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
        let index: GuideStoredIndex
        var result = Result()
        var pending = 0

        init(planner: GuideDiffPlanner, context: ModelContext, index: GuideStoredIndex) {
            self.planner = planner
            self.context = context
            self.index = index
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
                index.rows[id] = GuideListingApplier.stored(p)
            }
            for id in plan.updates {
                guard let p = byID[id] else { continue }
                var descriptor = FetchDescriptor<EPGListing>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                guard let row = try? context.fetch(descriptor).first else { continue }
                row.title = p.title
                row.listingDescription = p.description
                row.end = p.end
                row.subtitle = p.subtitle
                row.category = GuideFingerprint.category(p.categories)
                index.rows[id] = GuideListingApplier.stored(p)
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
