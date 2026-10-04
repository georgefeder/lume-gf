import Foundation
@testable import Lume
import Testing

struct GFCatalogStampsTests {
    @Test func `a playlist's films and series stamp is kept per playlist on this device`() throws {
        let defaults = try #require(UserDefaults(suiteName: "gf.catalog.test.\(UUID().uuidString)"))
        let a = UUID(), b = UUID(), when = Date(timeIntervalSince1970: 1_790_640_000)
        #expect(GFCatalogStamps.vodSyncedAt(a, defaults: defaults) == nil)
        GFCatalogStamps.markVODSynced(a, at: when, defaults: defaults)
        #expect(GFCatalogStamps.vodSyncedAt(a, defaults: defaults) == when)
        #expect(GFCatalogStamps.vodSyncedAt(b, defaults: defaults) == nil)
    }

    @Test func `the sync cover lists live channels first, and only them for a first sync's cover`() {
        #expect(SyncStep.steps(for: .xtream, gfScope: .live) == [.authenticating, .liveCategories, .liveStreams])
        #expect(Array(SyncStep.steps(for: .xtream).prefix(3)) == [.authenticating, .liveCategories, .liveStreams])
        #expect(SyncStep.steps(for: .xtream, gfScope: .vod) == [.movieCategories, .seriesCategories, .movies, .series])
    }
}
