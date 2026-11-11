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

    /// Apple TV: whether it loads films and series at all, off unless switched on (Georgs, 10 Nov 2026: "I don't watch
    /// films and series in lume at all"): less for tvOS to clear when storage runs low, a quicker sync back after it.
    static let tvFilmsAndSeriesKey = "gf.tv.filmsAndSeries"

    static func vodIsDue(vodSyncedAt: Date?, now: Date) -> Bool {
        guard let vodSyncedAt else { return true }
        return now.timeIntervalSince(vodSyncedAt) >= vodInterval
    }

    /// An automatic sync of a playlist that is due (launch, return to the app, playlist switch). Without films and
    /// series (`wantsVOD` false: an Apple TV that leaves them out) an Xtream playlist fetches its live channels only;
    /// other sources keep their single pass, which cannot leave them out.
    static func automatic(isXtream: Bool, everSynced: Bool, vodSyncedAt: Date?, now: Date, wantsVOD: Bool = true) -> Plan {
        guard everSynced else {
            guard isXtream else { return Plan(cover: .all, background: nil) }
            return Plan(cover: .live, background: wantsVOD ? .vod : nil)
        }
        guard isXtream else { return Plan(cover: nil, background: .all) }
        guard wantsVOD else { return Plan(cover: nil, background: .live) }
        return Plan(cover: nil, background: vodIsDue(vodSyncedAt: vodSyncedAt, now: now) ? .all : .live)
    }

    /// Sync Now and the first sync's cover: an Xtream playlist's live channels only, behind the automatic cover or
    /// without films and series here; everything otherwise.
    static func covered(isXtream: Bool, automatic: Bool, wantsVOD: Bool = true) -> GFSyncScope {
        isXtream && (automatic || !wantsVOD) ? .live : .all
    }
}
