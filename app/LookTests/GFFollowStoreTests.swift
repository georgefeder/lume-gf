import Foundation
@testable import Lume
import Testing

/// The shows followed, kept in the settings (synced to every device) and read back.
@MainActor
struct GFFollowStoreTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "gf.follow.test.\(UUID().uuidString)")! }

    @Test func `a follow is kept in the settings and a store reading them finds it`() {
        let defaults = defaults()
        let store = GFFollowStore(defaults: defaults)
        store.toggle(title: "Shark Tank", streamName: "ABC 4K")
        #expect(store.isFollowed(title: "Shark Tank", streamName: "ABC HD"))
        #expect(GFFollowStore(defaults: defaults).shows.map(\.channel) == ["ABC"])
        store.toggle(title: "Shark Tank", streamName: "ABC HD")
        #expect(GFFollowStore(defaults: defaults).shows.isEmpty)
    }

    @Test func `a list arriving from another device is picked up`() async throws {
        let defaults = defaults()
        let store = GFFollowStore(defaults: defaults)
        let elsewhere = [GFFollowedShow(title: "Panorama", channel: "BBC One", followedAt: Date())]
        defaults.set(GFFollowedShows.encode(elsewhere), forKey: GFFollowedShows.storageKey)
        try await Task.sleep(for: .milliseconds(200))
        #expect(store.shows == elsewhere)
    }
}
