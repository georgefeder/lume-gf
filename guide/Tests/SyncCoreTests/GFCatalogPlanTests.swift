import Foundation
@testable import SyncCore
import Testing

struct GFCatalogPlanTests {
    let now = Date(timeIntervalSince1970: 1_790_640_000)
    let hour: TimeInterval = 3600

    @Test func `a new Xtream playlist waits only for its live channels; films and series follow quietly`() {
        let plan = GFCatalogPlan.automatic(isXtream: true, everSynced: false, vodSyncedAt: nil, now: now)
        #expect(plan == .init(cover: .live, background: .vod))
    }

    @Test func `a synced Xtream playlist refreshes without a cover, films and series once a day`() {
        let fresh = GFCatalogPlan.automatic(isXtream: true, everSynced: true,
                                            vodSyncedAt: now.addingTimeInterval(-2 * hour), now: now)
        #expect(fresh == .init(cover: nil, background: .live))
        let stale = GFCatalogPlan.automatic(isXtream: true, everSynced: true,
                                            vodSyncedAt: now.addingTimeInterval(-25 * hour), now: now)
        #expect(stale == .init(cover: nil, background: .all))
        let never = GFCatalogPlan.automatic(isXtream: true, everSynced: true, vodSyncedAt: nil, now: now)
        #expect(never == .init(cover: nil, background: .all))
    }

    @Test func `other sources keep Lume's single pass, only out of sight once synced`() {
        #expect(GFCatalogPlan.automatic(isXtream: false, everSynced: false, vodSyncedAt: nil, now: now)
            == .init(cover: .all, background: nil))
        #expect(GFCatalogPlan.automatic(isXtream: false, everSynced: true, vodSyncedAt: nil, now: now)
            == .init(cover: nil, background: .all))
    }

    @Test func `films and series are due after a day, or when never fetched`() {
        #expect(GFCatalogPlan.vodIsDue(vodSyncedAt: nil, now: now))
        #expect(!GFCatalogPlan.vodIsDue(vodSyncedAt: now.addingTimeInterval(-23 * hour), now: now))
        #expect(GFCatalogPlan.vodIsDue(vodSyncedAt: now.addingTimeInterval(-24 * hour), now: now))
    }

    @Test func `a scope says what it fetches`() {
        #expect(GFSyncScope.all.includesLive && GFSyncScope.all.includesVOD)
        #expect(GFSyncScope.live.includesLive && !GFSyncScope.live.includesVOD)
        #expect(!GFSyncScope.vod.includesLive && GFSyncScope.vod.includesVOD)
    }
}
