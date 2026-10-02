import Foundation
@testable import Lume
import SwiftData
import Testing

/// Recently watched channels travel with Lume's sync (Part 4): Lume keeps them on each device, Georgs wants them on all.
@MainActor
struct GFRecentChannelsTests {
    private func freshShadow() -> CloudSyncShadow {
        CloudSyncShadow(defaults: UserDefaults(suiteName: "gf.recents.\(UUID().uuidString)")!)
    }

    private func channel(_ playlist: Playlist, _ n: Int) -> LiveStream {
        LiveStream(id: "\(playlist.id.uuidString)-live-\(n)", streamId: n, name: "Channel \(n)", epgChannelId: nil,
                   tvArchive: 0, tvArchiveDuration: 0, num: n, categoryId: nil)
    }

    @Test func `a channel watched here goes to the cloud store`() async throws {
        let container = try makeProfileTestContainer()
        let ctx = container.mainContext
        let playlist = Playlist(name: "TV", serverURL: "http://x", username: "u", password: "p")
        ctx.insert(playlist)
        let watched = Date(timeIntervalSince1970: 1_790_000_000)
        let stream = channel(playlist, 1)
        stream.lastWatchedDate = watched
        ctx.insert(stream)
        try ctx.save()

        _ = await CloudSyncEngine(container: container, shadow: freshShadow()).reconcile()

        let states = try ctx.fetch(FetchDescriptor<UserContentState>())
        #expect(states.count == 1)
        #expect(states.first?.kind == .live)
        #expect(states.first?.lastWatchedDate == watched)
    }

    @Test func `a channel watched on another device shows here as recently watched`() async throws {
        let container = try makeProfileTestContainer()
        let ctx = container.mainContext
        let playlist = Playlist(name: "TV", serverURL: "http://x", username: "u", password: "p")
        ctx.insert(playlist)
        let stream = channel(playlist, 2)
        ctx.insert(stream)
        let watched = Date(timeIntervalSince1970: 1_790_000_500)
        ctx.insert(UserContentState(contentId: stream.id, kind: .live, profileID: UserProfile.defaultProfileID,
                                    watchProgress: 0, isWatched: false, lastWatchedDate: watched, isFavorite: false,
                                    addedToWatchlistDate: nil, favoriteOrder: nil))
        try ctx.save()

        _ = await CloudSyncEngine(container: container, shadow: freshShadow()).reconcile()

        // read back as Lume's own sync tests do (the engine saved through its own context)
        let id = stream.id
        let updated = try #require(try ctx.fetch(FetchDescriptor<LiveStream>(predicate: #Predicate { $0.id == id })).first)
        #expect(updated.lastWatchedDate == watched)
    }
}
