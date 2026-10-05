import Foundation
@testable import Lume
import SwiftData
import Testing

/// A store that hands back one note and records what was saved.
final class FakeLastPlayedStore: GFLastPlayedStoring, @unchecked Sendable {
    var note: GFLastPlayedNote?
    func save(_ note: GFLastPlayedNote) async { self.note = note }
    func load() async -> GFLastPlayedNote? { note }
}

@MainActor
struct GFContinueBannerTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func note(_ contentId: String, from deviceID: String = "the-apple-tv") -> GFLastPlayedNote {
        GFLastPlayedNote(deviceID: deviceID, deviceKind: "Apple TV", kind: .channel, contentId: contentId,
                         title: "BBC One", artworkURL: nil, position: 0, duration: 0, playing: true,
                         updatedAt: now.addingTimeInterval(-180))
    }

    private func catalog() throws -> (ModelContext, Playlist) {
        let context = ModelContext(try makeTestContainer())
        let playlist = Playlist(name: "Home", serverURL: "http://example.invalid", username: "u", password: "p")
        context.insert(playlist)
        context.insert(LiveStream(id: "\(playlist.id.uuidString)-live-1", streamId: 1, name: "BBC One"))
        try context.save()
        return (context, playlist)
    }

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "gf.banner.test.\(UUID().uuidString)")! }

    @Test func `a channel from another device that this device has is offered, then dismissed for good`() async throws {
        let (context, playlist) = try catalog()
        let store = FakeLastPlayedStore(), ud = defaults()
        store.note = note("\(playlist.id.uuidString)-live-1")
        let model = GFContinueBannerModel(store: store, context: context, dismissedDefaults: ud)
        await model.refresh(now: now, playingHere: false)
        #expect(model.offered == store.note)
        let media = model.media(playlists: [playlist], selectedID: "")
        #expect(media?.contentRef == .live("\(playlist.id.uuidString)-live-1"))

        model.dismiss()
        #expect(model.offered == nil)
        await model.refresh(now: now, playingHere: false)
        #expect(model.offered == nil) // the same note is not offered again
    }

    @Test func `content this device lacks, this device's own note and a playing device are not offered`() async throws {
        let (context, playlist) = try catalog()
        let store = FakeLastPlayedStore(), ud = defaults()
        let model = GFContinueBannerModel(store: store, context: context, dismissedDefaults: ud)
        store.note = note("\(playlist.id.uuidString)-live-404")
        await model.refresh(now: now, playingHere: false)
        #expect(model.offered == nil)

        store.note = note("\(playlist.id.uuidString)-live-1", from: GFLastPlayed.deviceID)
        await model.refresh(now: now, playingHere: false)
        #expect(model.offered == nil)

        store.note = note("\(playlist.id.uuidString)-live-1")
        await model.refresh(now: now, playingHere: true)
        #expect(model.offered == nil)
    }

    @Test func `no store, no banner`() async throws {
        let (context, _) = try catalog()
        let model = GFContinueBannerModel(store: nil, context: context, dismissedDefaults: defaults())
        await model.refresh(now: now, playingHere: false)
        #expect(model.offered == nil)
    }
}
