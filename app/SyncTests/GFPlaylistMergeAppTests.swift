import Foundation
@testable import Lume
import SwiftData
import Testing

@MainActor
struct GFPlaylistMergeAppTests {
    private let keepID = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let dropID = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    private func freshShadow() -> CloudSyncShadow {
        CloudSyncShadow(defaults: UserDefaults(suiteName: "gf.merge.\(UUID().uuidString)")!)
    }

    private func playlist(_ id: UUID, server: String = "http://tv.example:8080") -> Playlist {
        let playlist = Playlist(name: "TV", serverURL: server, username: "georgs", password: "p")
        playlist.id = id
        return playlist
    }

    private func mirror(_ id: UUID, server: String = "http://tv.example:8080/") -> SyncedPlaylist {
        SyncedPlaylist(id: id, name: "TV", serverURL: server, username: "georgs", password: "p",
                       sourceTypeRaw: "xtream", epgURL: nil, syncEnabled: true)
    }

    private func state(_ id: String, favourite: Bool = false, progress: Double = 0) -> UserContentState {
        UserContentState(contentId: id, kind: .live, profileID: UserProfile.defaultProfileID, watchProgress: progress,
                         isWatched: false, lastWatchedDate: nil, isFavorite: favourite, addedToWatchlistDate: nil,
                         favoriteOrder: nil)
    }

    @Test func `the copy with the larger id goes, its favourites move to the kept playlist`() async throws {
        let container = try makeProfileTestContainer()
        let ctx = container.mainContext
        ctx.insert(playlist(dropID))            // this device's own copy
        ctx.insert(mirror(dropID))
        ctx.insert(mirror(keepID))              // another device's copy, arrived from iCloud
        ctx.insert(state("\(dropID.uuidString)-live-5", favourite: true))
        try ctx.save()

        let engine = CloudSyncEngine(container: container, shadow: freshShadow())
        let merged = try await engine.gfMergeDuplicatePlaylists()
        _ = await engine.reconcile()

        #expect(merged == 1)
        #expect(try ctx.fetch(FetchDescriptor<Playlist>()).map(\.id) == [keepID])
        #expect(try ctx.fetch(FetchDescriptor<SyncedPlaylist>()).map(\.id) == [keepID])
        let ids = try ctx.fetch(FetchDescriptor<UserContentState>()).map(\.contentId)
        #expect(ids == ["\(keepID.uuidString)-live-5"])
    }

    @Test func `unsynced favourites of a dropped copy move to the kept playlist`() async throws {
        // Review Focus 2: a favourite set on the dropped copy's channel that never reached the cloud store
        let container = try makeProfileTestContainer()
        let ctx = container.mainContext
        let own = playlist(dropID)
        ctx.insert(own)
        ctx.insert(mirror(keepID))
        let stream = LiveStream(id: "\(dropID.uuidString)-live-9", streamId: 9, name: "Nine", epgChannelId: nil,
                                tvArchive: 0, tvArchiveDuration: 0, num: 9, categoryId: nil)
        stream.isFavorite = true
        ctx.insert(stream)
        try ctx.save()

        let engine = CloudSyncEngine(container: container, shadow: freshShadow())
        _ = try await engine.gfMergeDuplicatePlaylists()

        let moved = try ctx.fetch(FetchDescriptor<UserContentState>())
        #expect(moved.map(\.contentId) == ["\(keepID.uuidString)-live-9"])
        #expect(moved.first?.isFavorite == true)
    }

    @Test func `both copies' state for the same channel combine`() async throws {
        let container = try makeProfileTestContainer()
        let ctx = container.mainContext
        ctx.insert(mirror(keepID))
        ctx.insert(mirror(dropID))
        ctx.insert(state("\(keepID.uuidString)-live-3", progress: 0))
        ctx.insert(state("\(dropID.uuidString)-live-3", favourite: true))
        try ctx.save()

        _ = try await CloudSyncEngine(container: container, shadow: freshShadow()).gfMergeDuplicatePlaylists()

        let states = try ctx.fetch(FetchDescriptor<UserContentState>())
        #expect(states.count == 1)
        #expect(states.first?.contentId == "\(keepID.uuidString)-live-3")
        #expect(states.first?.isFavorite == true)
    }

    @Test func `different playlists stay`() async throws {
        let container = try makeProfileTestContainer()
        let ctx = container.mainContext
        ctx.insert(mirror(keepID))
        ctx.insert(mirror(dropID, server: "http://other.example"))
        try ctx.save()

        let merged = try await CloudSyncEngine(container: container, shadow: freshShadow()).gfMergeDuplicatePlaylists()

        #expect(merged == 0)
        #expect(try ctx.fetch(FetchDescriptor<SyncedPlaylist>()).count == 2)
    }

    @Test func `a restriction on the dropped copy's category moves too`() async throws {
        let container = try makeProfileTestContainer()
        let ctx = container.mainContext
        ctx.insert(mirror(keepID))
        ctx.insert(mirror(dropID))
        ctx.insert(SyncedCategoryRestriction(categoryID: "\(dropID.uuidString)-live-12"))
        try ctx.save()

        _ = try await CloudSyncEngine(container: container, shadow: freshShadow()).gfMergeDuplicatePlaylists()

        #expect(try ctx.fetch(FetchDescriptor<SyncedCategoryRestriction>()).map(\.categoryID)
            == ["\(keepID.uuidString)-live-12"])
    }
}
