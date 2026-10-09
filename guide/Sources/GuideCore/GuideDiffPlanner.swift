import Foundation

/// Plans an only-what-changed import: which programmes of a new guide file to insert or update and, once the file has
/// been read completely, which stored ones to delete.
///
/// A programme's id is "<channel>-<start epoch seconds>" (Lume's `EPGListing.id`). Everything the file carries is
/// stored, old programmes included (the server's catch-up days feed the Apple TV player's replay list), like Lume's own
/// import. The new file is authoritative only for the span it covers on each channel it guides: a stored programme is
/// deleted when its channel is in the file, it starts at or after that channel's first programme in the file, and the
/// file no longer has it. A stored programme that ended more than 12 hours ago and is no longer in the file is dropped
/// when the file guides its channel, or when no playlist has that channel any more (`allChannels`); another source's
/// programmes are that source's to drop. A file that was not read completely deletes nothing.
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
    /// The span a stale guide takes first (`wantsNowFirst`): wider than an iPhone's or a TV's opening guide screen.
    static let nowFirstSpan: TimeInterval = 4 * 60 * 60

    /// Whether the stored guide has gone stale for `channels` (fewer than half have a programme on now): then an import
    /// takes what is on from now for `nowFirstSpan` first and shows it, before the rest of the file (Georgs, 9 Oct: a
    /// phone that had not refreshed for a day showed "No Programme" everywhere for a minute while a whole new guide
    /// went in). A first import counts as stale.
    static func wantsNowFirst(stored: [String: Stored], channels: Set<String>, now: Date) -> Bool {
        guard !channels.isEmpty else { return false }
        var onNow: Set<String> = []
        for row in stored.values where row.start <= now && row.end > now && channels.contains(row.channelId) {
            onNow.insert(row.channelId)
        }
        return onNow.count * 2 < channels.count
    }

    static func id(channelId: String, start: Date) -> String {
        "\(channelId)-\(Int(start.timeIntervalSince1970))"
    }

    private var stored: [String: Stored]
    private let claimable: Set<String>
    /// Every channel of every playlist (nil: unknown, so no programme counts as orphaned).
    private let allChannels: Set<String>?
    private let cutoff: Date
    private var seen: Set<String> = []
    private var firstStart: [String: Date] = [:]

    init(stored: [String: Stored], claimableChannels: Set<String>, now: Date, allChannels: Set<String>? = nil) {
        self.stored = stored
        claimable = claimableChannels
        self.allChannels = allChannels
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
            guard seen.insert(item.id).inserted else { continue }
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
        for (id, row) in stored where !seen.contains(id) {
            if row.end < cutoff,
               firstStart[row.channelId] != nil || allChannels.map({ !$0.contains(row.channelId) }) == true {
                out.append(id) // ended long ago and no longer in the file (of a channel it guides, or of none)
            } else if let first = firstStart[row.channelId], row.start >= first {
                out.append(id) // inside the span the file covers, but gone from it
            }
        }
        return out.sorted()
    }

    /// Hands the stored rows back and lets go of them, so the caller can change them without copying them all.
    mutating func releaseStored() -> [String: Stored] {
        let rows = stored
        stored = [:]
        return rows
    }
}
