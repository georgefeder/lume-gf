import Foundation
@testable import Lume
import SwiftData
import Testing

/// Lume GF's search against a real store (Georgs, 29 Oct: categories, typos, his languages; 8 Oct: when and where
/// does "Shark Tank" air?).
@MainActor
struct GFSmartSearchTests {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)

    private struct Library {
        let container: ModelContainer
        let mine: Playlist
        let other: Playlist
        let finland: Lume.Category
    }

    private func library() throws -> Library {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let mine = Playlist(name: "Mine", serverURL: "http://example.invalid", username: "u", password: "p")
        let other = Playlist(name: "Other", serverURL: "http://example.invalid", username: "u", password: "p")
        context.insert(mine)
        context.insert(other)
        let finland = Lume.Category(apiId: "7", name: "FI | Finland", parentId: 0, type: .live, playlist: mine)
        let news = Lume.Category(apiId: "8", name: "UK | News", parentId: 0, type: .live, playlist: mine)
        let theirs = Lume.Category(apiId: "7", name: "FI | Finland", parentId: 0, type: .live, playlist: other)
        [finland, news, theirs].forEach { context.insert($0) }
        let mineID = mine.id.uuidString
        context.insert(LiveStream(id: "\(mineID)-live-1", streamId: 1, name: "FI | Yle TV1 HD", epgChannelId: "yle",
                                  num: 1, categoryId: finland.id))
        context.insert(LiveStream(id: "\(mineID)-live-2", streamId: 2, name: "CNBC HD", epgChannelId: "cnbc", num: 2,
                                  categoryId: news.id))
        let hidden = LiveStream(id: "\(mineID)-live-3", streamId: 3, name: "FI | MTV3 HD", num: 3,
                                categoryId: finland.id)
        hidden.isHidden = true
        context.insert(hidden)
        context.insert(LiveStream(id: "\(other.id.uuidString)-live-9", streamId: 9, name: "FI | Yle TV2 HD",
                                  epgChannelId: "cnbc", num: 1, categoryId: theirs.id))
        context.insert(Movie(id: "\(mineID)-movie-5", streamId: 5, name: "Dune"))
        context.insert(Movie(id: "\(mineID)-movie-6", streamId: 6, name: "Dune: Part Two"))
        context.insert(Series(id: "\(mineID)-series-7", seriesId: 7, name: "Shark Tank"))
        func listing(_ id: String, _ channel: String, _ title: String, startsIn seconds: TimeInterval,
                     subtitle: String? = nil) -> EPGListing {
            EPGListing(id: id, channelId: channel, title: title, listingDescription: "About \(title)",
                       start: now.addingTimeInterval(seconds), end: now.addingTimeInterval(seconds + 3600),
                       subtitle: subtitle, category: nil)
        }
        context.insert(listing("later", "cnbc", "Shark Tank", startsIn: 3600))
        context.insert(listing("ended", "cnbc", "Shark Tank", startsIn: -7200))
        context.insert(listing("live", "cnbc", "Shark Tank Australia", startsIn: -600))
        context.insert(listing("news", "yle", "Uutiset", startsIn: -600))
        context.insert(listing("nba", "cnbc", "NBA Basketball", startsIn: 7200,
                               subtitle: "Golden State Warriors at Los Angeles Lakers"))
        try context.save()
        return Library(container: container, mine: mine, other: other, finland: finland)
    }

    private func search(_ text: String, in library: Library,
                        kinds: Set<GFSearchIndex.Kind> = Set(GFSearchIndex.Kind.allCases),
                        everyPlaylist: Bool = false) async -> GFSmartSearch.Found {
        let playlists = [library.mine, library.other].map(\.id.uuidString).sorted()
        let scope = everyPlaylist ? Set(playlists) : [library.mine.id.uuidString]
        let request = GFSmartSearch.Request(text: text, kinds: kinds, playlists: playlists, scope: scope,
                                            liveKey: "live", guideKey: "guide", libraryKey: "library", now: now)
        return await GFSmartSearch.run(request, container: library.container, catalog: GFSearchCatalog())
    }

    @Test func `a country finds its category and its visible channels, in this playlist only`() async throws {
        let library = try library()
        for text in ["finland", "Somija", "finlnd"] {
            let found = await search(text, in: library)
            let keys = found.hits.map(\.key)
            #expect(keys.first == library.finland.id, "\(text): \(keys)")
            #expect(keys.contains("\(library.mine.id.uuidString)-live-1"), "\(text): \(keys)")
            #expect(!keys.contains("\(library.mine.id.uuidString)-live-3"), "\(text): hidden channel found")
            #expect(!keys.contains { $0.hasPrefix(library.other.id.uuidString) }, "\(text): other playlist found")
            #expect(found.channelCounts[library.finland.id] == 1)
        }
        let everywhere = await search("finland", in: library, everyPlaylist: true).hits.map(\.key)
        #expect(everywhere.contains("\(library.other.id.uuidString)-live-9"))
    }

    @Test func `a programme is found by title or by its episode line, with the channel that carries it`() async throws {
        let library = try library()
        let shark = await search("shark tank", in: library)
        #expect(Set(shark.airings.map(\.hit.listingID)) == ["later", "live"])
        #expect(shark.hits.map(\.key) == ["\(library.mine.id.uuidString)-series-7"])
        let warriors = await search("warriors", in: library)
        #expect(warriors.airings.map(\.hit.listingID) == ["nba"])
        #expect(warriors.airings.first?.hit.subtitle == "Golden State Warriors at Los Angeles Lakers")
    }

    @Test func `a mistyped film is found, and only the kinds asked for`() async throws {
        let library = try library()
        let films = await search("duen", in: library).hits.map(\.key)
        #expect(films == ["\(library.mine.id.uuidString)-movie-5", "\(library.mine.id.uuidString)-movie-6"])
        let live = await search("dune", in: library, kinds: [.category, .channel, .programme])
        #expect(live.hits.isEmpty && live.airings.isEmpty)
    }

    @Test func `the screen's sections: Top Results, then the best kind first`() async throws {
        let library = try library()
        let model = GFSmartSearchModel(catalog: GFSearchCatalog())
        let context = ModelContext(library.container)
        await model.update(text: "finland", filter: .all, keys: GFSmartSearchModel.Keys(playlists: [library.mine]),
                           scope: [library.mine], context: context, restriction: ContentRestriction())
        #expect(model.answered == "finland")
        #expect(model.groups.first?.kind == .category)
        #expect(model.groups.flatMap(\.rows).count == 2) // the category and Yle TV1
    }
}
