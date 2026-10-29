import OSLog
import SwiftData
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

/// Lume GF's search behind Lume's search screen (Georgs, 29 Oct: typos, his languages, categories, and an "All" that
/// understands what he is after). Three indexes (GFSearchIndex) are built off the main thread from the library and
/// kept while the app runs: live TV (categories and channels), the guide (programmes) and the library (films and
/// series). Each is rebuilt when what it was built from changes (a playlist sync, a new guide); until the new one is
/// in, the old one answers.
nonisolated final class GFSearchCatalog: @unchecked Sendable {
    static let shared = GFSearchCatalog()

    enum Shelf: String, Sendable {
        case live, guide, library
    }

    /// An index, what it was built from, and the playlists its groups stand for.
    struct Built: Sendable {
        let key: String
        let index: GFSearchIndex
        /// Playlist ids (`uuidString`) by group number.
        let playlists: [String]
        /// Live TV: channels per category id.
        let channelCounts: [String: Int]
    }

    private let lock = NSLock()
    private var built: [Shelf: Built] = [:]
    private var building: [Shelf: (key: String, task: Task<Built, Never>)] = [:]

    init() {
        #if canImport(UIKit)
            // the guide's and the library's indexes are the big ones: built again at the next search
            NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
            ) { [weak self] _ in
                self?.lock.withLock {
                    self?.built[.guide] = nil
                    self?.built[.library] = nil
                }
            }
        #endif
    }

    /// Whether the index for `key` is built.
    func isReady(_ shelf: Shelf, key: String) -> Bool {
        lock.withLock { built[shelf]?.key == key }
    }

    /// The index for `key`: at once when built, the older one while a new one builds, else once it is built. The
    /// guide's holds the programmes that have not ended at `now`.
    func index(_ shelf: Shelf, key: String, container: ModelContainer, playlists: [String], now: Date = Date(),
               priority: TaskPriority = .userInitiated) async -> Built {
        enum Answer {
            case ready(Built)
            case wait(Task<Built, Never>)
        }
        let answer: Answer = lock.withLock {
            if let current = built[shelf], current.key == key { return .ready(current) }
            let task: Task<Built, Never>
            if let running = building[shelf], running.key == key {
                task = running.task
            } else {
                task = Task.detached(priority: built[shelf] == nil ? priority : .utility) { [self] in
                    let result = Self.build(shelf, key: key, container: container, playlists: playlists, now: now)
                    // kept only while it is the newest asked for: an older build finishing late is not
                    lock.withLock {
                        if building[shelf]?.key == key {
                            built[shelf] = result
                            building[shelf] = nil
                        }
                    }
                    return result
                }
                building[shelf] = (key, task)
            }
            if let older = built[shelf] { return .ready(older) }
            return .wait(task)
        }
        switch answer {
        case let .ready(built): return built
        case let .wait(task): return await task.value
        }
    }

    // MARK: - Building

    private static func build(_ shelf: Shelf, key: String, container: ModelContainer, playlists: [String],
                              now: Date) -> Built {
        let started = Date()
        let context = ModelContext(container)
        var builder = GFSearchIndex.Builder()
        var counts: [String: Int] = [:]
        let groups = Dictionary(playlists.enumerated().map { ($1, UInt8(clamping: $0)) },
                                uniquingKeysWith: { first, _ in first })
        /// A catalog row's playlist and its id without the playlist ("live-12": kept short, held for every title).
        func split(_ id: String) -> (group: UInt8, key: String)? {
            let utf8 = id.utf8
            guard utf8.count > 37, let playlist = String(utf8.prefix(36)), let group = groups[playlist] else {
                return nil
            }
            return (group, String(id.dropFirst(37)))
        }
        switch shelf {
        case .live:
            // hidden ones too (Content Management can show them again without a sync): the search leaves them out
            let live = "live" // CategoryType.live
            var categories = FetchDescriptor<Category>(predicate: #Predicate { $0.typeRaw == live })
            categories.propertiesToFetch = [\.id, \.name]
            for category in (try? context.fetch(categories)) ?? [] {
                guard let row = split(category.id) else { continue }
                builder.add(.category, key: row.key, group: row.group, name: category.name)
            }
            var streams = FetchDescriptor<LiveStream>()
            streams.propertiesToFetch = [\.id, \.name, \.categoryId, \.isHidden]
            try? context.enumerate(streams, batchSize: 2000) { stream in
                guard let row = split(stream.id) else { return }
                builder.add(.channel, key: row.key, group: row.group, name: stream.name)
                if let category = stream.categoryId, !stream.isHidden { counts[category, default: 0] += 1 }
            }
        case .guide:
            var listings = FetchDescriptor<EPGListing>(predicate: #Predicate { $0.end > now })
            listings.propertiesToFetch = [\.title, \.subtitle, \.category]
            var seen = Set<String>()
            try? context.enumerate(listings, batchSize: 5000) { listing in
                let key = GFSmartSearch.programmeKey(title: listing.title, subtitle: listing.subtitle)
                guard seen.insert(key).inserted else { return }
                let extra = [listing.subtitle, listing.category].compactMap(\.self).joined(separator: " ")
                builder.add(.programme, key: key, name: listing.title, extra: extra)
            }
        case .library:
            var films = FetchDescriptor<Movie>()
            films.propertiesToFetch = [\.id, \.name]
            try? context.enumerate(films, batchSize: 5000) { film in
                guard let row = split(film.id) else { return }
                builder.add(.film, key: row.key, group: row.group, name: film.name)
            }
            var series = FetchDescriptor<Series>()
            series.propertiesToFetch = [\.id, \.name]
            try? context.enumerate(series, batchSize: 5000) { show in
                guard let row = split(show.id) else { return }
                builder.add(.series, key: row.key, group: row.group, name: show.name)
            }
        }
        let index = builder.build()
        let line = "Search: \(shelf.rawValue) index of \(index.count) in "
            + String(format: "%.2f", Date().timeIntervalSince(started)) + " s"
        Logger.database.info("\(line, privacy: .public)")
        return Built(key: key, index: index, playlists: playlists, channelCounts: counts)
    }
}

/// One search, off the main thread: the query read (GFSearchQuery), each index asked, their matches merged, and the
/// airings of the programmes found.
nonisolated enum GFSmartSearch {
    struct Request: Sendable {
        let text: String
        let kinds: Set<GFSearchIndex.Kind>
        /// Every playlist (`uuidString`), and the ones searched.
        let playlists: [String]
        let scope: Set<String>
        /// What each index is built from (`GFSearchCatalog`).
        let liveKey: String
        let guideKey: String
        let libraryKey: String
        let now: Date
    }

    /// A programme found, at one airing, on a channel that carries it.
    struct Airing: Sendable {
        let hit: GFGuideSearchHit
        let stream: PersistentIdentifier
        let score: Double
    }

    struct Found: Sendable {
        /// Categories, channels, films and series, best first; keys are the rows' ids.
        var hits: [GFSearchIndex.Hit] = []
        var airings: [Airing] = []
        var channelCounts: [String: Int] = [:]
    }

    /// A programme's key in the guide index: its title and episode line.
    static func programmeKey(title: String, subtitle: String?) -> String {
        title + "\u{1F}" + (subtitle ?? "")
    }

    static func title(ofProgrammeKey key: String) -> String {
        String(key.prefix { $0 != "\u{1F}" })
    }

    static func run(_ request: Request, container: ModelContainer, catalog: GFSearchCatalog = .shared) async -> Found {
        guard !Task.isCancelled else { return Found() }
        let query = GFSearchQuery(request.text)
        guard !query.required.isEmpty else { return Found() }
        let liveKinds = request.kinds.intersection([.category, .channel])
        let libraryKinds = request.kinds.intersection([.film, .series])
        async let live = load(.live, key: request.liveKey, wanted: !liveKinds.isEmpty, request: request,
                              container: container, catalog: catalog)
        async let guide = load(.guide, key: request.guideKey, wanted: request.kinds.contains(.programme),
                               request: request, container: container, catalog: catalog)
        async let library = load(.library, key: request.libraryKey, wanted: !libraryKinds.isEmpty, request: request,
                                 container: container, catalog: catalog)
        let (liveBuilt, guideBuilt, libraryBuilt) = await (live, guide, library)
        let shelves: [(GFSearchCatalog.Built?, Set<GFSearchIndex.Kind>)] = [
            (liveBuilt, liveKinds), (guideBuilt, [.programme]), (libraryBuilt, libraryKinds)
        ]
        guard !Task.isCancelled else { return Found() }
        var lists: [[GFSearchIndex.Hit]] = []
        for (built, kinds) in shelves {
            guard let built, !kinds.isEmpty else { continue }
            if kinds == [.programme] {
                lists.append(built.index.search(query, kinds: kinds))
                continue
            }
            // catalog rows: only the playlists searched, with their full ids back
            let groups = Set(built.playlists.indices.filter { request.scope.contains(built.playlists[$0]) }
                .map { UInt8(clamping: $0) })
            lists.append(built.index.search(query, kinds: kinds, groups: groups).map { hit in
                GFSearchIndex.Hit(kind: hit.kind, group: hit.group,
                                  key: built.playlists[Int(hit.group)] + "-" + hit.key, score: hit.score,
                                  typos: hit.typos, nameLength: hit.nameLength)
            })
        }
        let merged = GFSearchIndex.merged(lists)
        var found = Found(hits: merged.filter { $0.kind != .programme }, channelCounts: liveBuilt?.channelCounts ?? [:])
        let programmes = merged.filter { $0.kind == .programme }
        if !programmes.isEmpty, !Task.isCancelled {
            found.airings = airings(of: programmes, query: query, request: request, container: container)
        }
        return found
    }

    private static func load(_ shelf: GFSearchCatalog.Shelf, key: String, wanted: Bool, request: Request,
                             container: ModelContainer, catalog: GFSearchCatalog) async -> GFSearchCatalog.Built? {
        guard wanted else { return nil }
        return await catalog.index(shelf, key: key, container: container, playlists: request.playlists,
                                   now: request.now)
    }

    /// The found programmes' next airings on the searched playlists' channels (each programme's on now first, then
    /// by start, at most `GFSearchLayout.airingsPerProgramme`), best first, at most `GFGuideSearch.limit`.
    private static func airings(of programmes: [GFSearchIndex.Hit], query: GFSearchQuery, request: Request,
                                container: ModelContainer) -> [Airing] {
        let scores = Dictionary(programmes.prefix(40).map { ($0.key, $0.score) }, uniquingKeysWith: max)
        let titles = Array(Set(scores.keys.map(title(ofProgrammeKey:))))
        let now = request.now
        let context = ModelContext(container)
        // every airing of these titles (a title on many channels, "NBA Basketball", has many): sorted here, so
        // tonight's or a particular game's airing is never cut off by earlier ones
        var descriptor = FetchDescriptor<EPGListing>(
            predicate: #Predicate { titles.contains($0.title) && $0.end > now }
        )
        descriptor.fetchLimit = 5000
        let matched = ((try? context.fetch(descriptor)) ?? []).filter {
            scores[programmeKey(title: $0.title, subtitle: $0.subtitle)] != nil
        }
        guard !matched.isEmpty else { return [] }
        let wanted = Set(matched.map(\.channelId))
        var streams: [String: PersistentIdentifier] = [:]
        for playlistID in request.scope.sorted() {
            guard !Task.isCancelled else { return [] }
            let prefix = playlistID + "-"
            var channels = FetchDescriptor<LiveStream>(
                predicate: #Predicate { $0.id.starts(with: prefix) && $0.isHidden == false },
                sortBy: [SortDescriptor(\.num)]
            )
            channels.propertiesToFetch = [\.epgChannelId]
            for stream in (try? context.fetch(channels)) ?? [] {
                guard let channel = stream.epgChannelId, wanted.contains(channel), streams[channel] == nil
                else { continue }
                streams[channel] = stream.persistentModelID
            }
        }
        var byProgramme: [String: [GFGuideSearchHit]] = [:]
        for listing in matched {
            byProgramme[programmeKey(title: listing.title, subtitle: listing.subtitle), default: []].append(
                GFGuideSearchHit(listingID: listing.id, channelId: listing.channelId, title: listing.title,
                                 subtitle: listing.subtitle, detail: listing.listingDescription, start: listing.start,
                                 end: listing.end)
            )
        }
        let calendar = Calendar.current
        var result: [Airing] = []
        for (key, listings) in byProgramme {
            guard let score = scores[key] else { continue }
            // with a time asked for ("tonight"), that time's airings when there are any
            let inTime = query.time.map { time in
                listings.filter { time.contains(start: $0.start, end: $0.end, now: now, calendar: calendar) }
            } ?? []
            for hit in GFGuideSearch.hits(inTime.isEmpty ? listings : inTime, channels: Set(streams.keys), now: now,
                                          limit: GFSearchLayout.airingsPerProgramme) {
                guard let stream = streams[hit.channelId] else { continue }
                result.append(Airing(hit: hit, stream: stream, score: GFSearchLayout.programmeScore(
                    score, start: hit.start, end: hit.end, now: now, time: query.time, calendar: calendar
                )))
            }
        }
        result.sort { $0.score != $1.score ? $0.score > $1.score : $0.hit.start < $1.hit.start }
        return Array(result.prefix(GFGuideSearch.limit))
    }
}
