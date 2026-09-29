import Foundation

/// Plans an only-what-changed import: which programmes of a new guide file to insert or update and, once the file has
/// been read completely, which stored ones to delete.
///
/// A programme's id is "<channel>-<start epoch seconds>" (Lume's `EPGListing.id`). The new file is authoritative only
/// for the span it covers on each channel it guides: a stored programme is deleted when its channel is in the file,
/// it starts at or after that channel's first programme in the file, and the file no longer has it. Programmes that
/// ended more than 12 hours ago are dropped (Lume's guide shows 12 hours back). A file that was not read completely
/// deletes nothing.
nonisolated struct GuideDiffPlanner {
    struct Stored: Equatable {
        var channelId: String
        var start: Date
        var end: Date
        var fingerprint: UInt64
    }

    struct Incoming: Equatable {
        var id: String
        var channelId: String
        var start: Date
        var end: Date
        var fingerprint: UInt64
    }

    struct BatchPlan: Equatable {
        var inserts: [String] = []
        var updates: [String] = []
    }

    static let keepPast: TimeInterval = 12 * 60 * 60

    static func id(channelId: String, start: Date) -> String {
        "\(channelId)-\(Int(start.timeIntervalSince1970))"
    }

    private let stored: [String: Stored]
    private let claimable: Set<String>
    private let cutoff: Date
    private var seen: Set<String> = []
    private var firstStart: [String: Date] = [:]

    init(stored: [String: Stored], claimableChannels: Set<String>, now: Date) {
        self.stored = stored
        claimable = claimableChannels
        cutoff = now.addingTimeInterval(-Self.keepPast)
    }

    /// Channels this file guides (programmes on channels this source may claim).
    var claimedChannels: Set<String> {
        Set(firstStart.keys)
    }

    mutating func plan(_ batch: [Incoming]) -> BatchPlan {
        var plan = BatchPlan()
        for item in batch where claimable.contains(item.channelId) {
            if firstStart[item.channelId].map({ item.start < $0 }) ?? true {
                firstStart[item.channelId] = item.start
            }
            guard seen.insert(item.id).inserted, item.end >= cutoff else { continue }
            if let old = stored[item.id] {
                if old.fingerprint != item.fingerprint { plan.updates.append(item.id) }
            } else {
                plan.inserts.append(item.id)
            }
        }
        return plan
    }

    func deletions(fileCompleted: Bool) -> [String] {
        guard fileCompleted else { return [] }
        var out: [String] = []
        for (id, row) in stored {
            if row.end < cutoff {
                out.append(id)
            } else if let first = firstStart[row.channelId], row.start >= first, !seen.contains(id) {
                out.append(id)
            }
        }
        return out.sorted()
    }
}
