import Foundation
@testable import Lume
import SwiftData
import Testing

/// Search's "On TV" against a real store (Georgs, 8 Oct: when and where does "Shark Tank" air?).
@MainActor
struct GFGuideSearchFetchTests {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)

    private func listing(_ id: String, _ channel: String, _ title: String, startsIn seconds: TimeInterval,
                         minutes: Double = 60) -> EPGListing {
        EPGListing(id: id, channelId: channel, title: title, listingDescription: "About \(title)",
                   start: now.addingTimeInterval(seconds), end: now.addingTimeInterval(seconds + minutes * 60))
    }

    @Test func `a programme on this playlist's channel is found, with the channel that carries it`() throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let mine = Playlist(name: "Mine", serverURL: "http://example.invalid", username: "u", password: "p")
        let other = Playlist(name: "Other", serverURL: "http://example.invalid", username: "u", password: "p")
        context.insert(mine)
        context.insert(other)
        context.insert(LiveStream(id: "\(mine.id.uuidString)-live-1", streamId: 1, name: "CNBC HD",
                                  epgChannelId: "cnbc", num: 2))
        context.insert(LiveStream(id: "\(other.id.uuidString)-live-9", streamId: 9, name: "Other HD",
                                  epgChannelId: "other"))
        context.insert(listing("later", "cnbc", "Shark Tank", startsIn: 3600))
        context.insert(listing("ended", "cnbc", "Shark Tank", startsIn: -7200))
        context.insert(listing("theirs", "other", "Shark Tank", startsIn: 3600))
        context.insert(listing("unrelated", "cnbc", "Dragons' Den", startsIn: 1800))
        context.insert(listing("live", "cnbc", "Shark Tank Australia", startsIn: -600))
        try context.save()

        let found = GFGuideSearchFetcher.fetch(container: container, query: "shark tank",
                                               playlistIDs: [mine.id.uuidString], now: now)
        #expect(found.hits.map(\.listingID) == ["live", "later"])
        #expect(found.hits.first?.detail == "About Shark Tank Australia")
        #expect(found.streams.keys.sorted() == ["cnbc"])
    }

    @Test func `nothing matches, nothing is fetched`() throws {
        let container = try makeTestContainer()
        let found = GFGuideSearchFetcher.fetch(container: container, query: "shark tank", playlistIDs: ["x"], now: now)
        #expect(found.hits.isEmpty)
        #expect(found.streams.isEmpty)
    }
}
