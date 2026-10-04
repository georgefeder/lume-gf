import Foundation
@testable import Lume
import Testing

struct GFLastPlayedTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func media(_ ref: PlayableMedia.ContentRef, live: Bool) -> PlayableMedia {
        PlayableMedia(id: "m", url: URL(string: "http://x/1")!, title: "BBC One", subtitle: nil,
                      posterURL: URL(string: "http://x/logo.png"), kind: live ? .live : .vod, startTime: 0,
                      contentRef: ref)
    }

    @Test func `a channel becomes a channel note with its logo`() {
        let note = GFLastPlayed.note(for: media(.live("p-live-1"), live: true), position: 0, duration: 0,
                                     playing: true, now: now)
        #expect(note.kind == .channel)
        #expect(note.contentId == "p-live-1")
        #expect(note.artworkURL == "http://x/logo.png")
        #expect(note.deviceID == GFLastPlayed.deviceID)
        #expect(note.updatedAt == now)
    }

    @Test func `films and episodes keep their position`() {
        let film = GFLastPlayed.note(for: media(.movie("p-movie-7"), live: false), position: 4323, duration: 7200,
                                     playing: false, now: now)
        #expect(film.kind == .film)
        #expect(film.position == 4323)
        #expect(!film.playing)
        #expect(GFLastPlayed.note(for: media(.episode("p-ep-3"), live: false), position: 1, duration: 2,
                                  playing: true, now: now).kind == .episode)
    }

    @Test func `the device id stays the same`() {
        #expect(GFLastPlayed.deviceID == GFLastPlayed.deviceID)
        #expect(!GFLastPlayed.deviceID.isEmpty)
    }

    @Test func `no banner without iCloud`() {
        // Review Focus 3: unit tests are unsigned, so there is no store and nothing is read or written
        #expect(GFLastPlayed.store == nil)
    }
}
