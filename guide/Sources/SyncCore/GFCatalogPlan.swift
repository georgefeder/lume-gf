import Foundation

/// Which parts of an Xtream catalogue a sync fetches: live channels (with their categories), films and series, or
/// both (live first).
nonisolated enum GFSyncScope: String, Sendable, Equatable {
    case all, live, vod

    var includesLive: Bool {
        self != .vod
    }

    var includesVOD: Bool {
        self != .live
    }
}

/// When a playlist's catalogue loads, and whether the viewer waits for it (Georgs, 4 Oct: live channels as fast as
/// possible). A playlist's first sync shows Lume's cover until its live channels are in, then fetches films and series
/// in the background; every later automatic sync runs in the background, films and series at most once a day. Other
/// sources than Xtream keep Lume's single pass. Settings › Sync Now always fetches everything behind its cover.
nonisolated enum GFCatalogPlan {
    struct Plan: Equatable {
        /// What runs behind Lume's sync cover (nil: no cover).
        var cover: GFSyncScope?
        /// What runs quietly afterwards (nil: nothing).
        var background: GFSyncScope?
    }

    static let vodInterval: TimeInterval = 24 * 60 * 60

    static func vodIsDue(vodSyncedAt: Date?, now: Date) -> Bool {
        guard let vodSyncedAt else { return true }
        return now.timeIntervalSince(vodSyncedAt) >= vodInterval
    }

    /// An automatic sync of a playlist that is due (launch, return to the app, playlist switch).
    static func automatic(isXtream: Bool, everSynced: Bool, vodSyncedAt: Date?, now: Date) -> Plan {
        guard everSynced else {
            return isXtream ? Plan(cover: .live, background: .vod) : Plan(cover: .all, background: nil)
        }
        guard isXtream else { return Plan(cover: nil, background: .all) }
        return Plan(cover: nil, background: vodIsDue(vodSyncedAt: vodSyncedAt, now: now) ? .all : .live)
    }
}
