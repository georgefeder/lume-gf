import SwiftData
import SwiftUI

/// What Lume GF's search shows (GFSmartSearch): sections of categories, channels, programmes, films and series, laid
/// out by GFSearchLayout ("All" leads with Top Results, then the kind that matched best).
@MainActor
@Observable
final class GFSmartSearchModel {
    enum Row: Identifiable {
        case category(Category, channels: Int)
        case channel(LiveStream)
        case programme(GFProgrammeRow)
        case film(Movie)
        case series(Series)

        var id: String {
            switch self {
            case let .category(category, _): "category|" + category.id
            case let .channel(stream): "channel|" + stream.id
            case let .programme(row): "programme|" + row.id
            case let .film(movie): "film|" + movie.id
            case let .series(series): "series|" + series.id
            }
        }
    }

    struct ResultGroup: Identifiable {
        /// Nil for Top Results.
        let kind: GFSearchIndex.Kind?
        let rows: [Row]

        var id: String {
            kind.map { "\($0.rawValue)" } ?? "top"
        }

        var title: LocalizedStringKey {
            switch kind {
            case nil: "Top Results"
            case .category: "Categories"
            case .channel: "Channels"
            case .programme: "On TV"
            case .film: "Movies"
            case .series: "Series"
            }
        }
    }

    private(set) var groups: [ResultGroup] = []
    /// The search the groups answer ("No Results" waits for it).
    private(set) var answered = ""
    private(set) var now = Date()
    var selection: GFProgrammeSelection?
    @ObservationIgnored private let catalog: GFSearchCatalog

    init(catalog: GFSearchCatalog = .shared) {
        self.catalog = catalog
    }

    static func kinds(_ filter: ContentFilter) -> Set<GFSearchIndex.Kind> {
        switch filter {
        case .all: Set(GFSearchIndex.Kind.allCases)
        case .movies: [.film]
        case .series: [.series]
        case .liveTV: [.category, .channel, .programme]
        }
    }

    /// What the indexes are built from: each playlist's last sync (and films' and series'), and the guide's last
    /// import (every three hours at least, so ended programmes leave).
    struct Keys: Equatable {
        let playlists: [String]
        let live: String
        let guide: String
        let library: String

        init(playlists: [Playlist], now: Date = Date()) {
            let sorted = playlists.sorted { $0.id.uuidString < $1.id.uuidString }
            self.playlists = sorted.map(\.id.uuidString)
            live = sorted.map { "\($0.id.uuidString)@\($0.lastSyncDate?.timeIntervalSince1970 ?? 0)" }
                .joined(separator: ",")
            library = live + "|" + sorted.map {
                "\(GFCatalogStamps.vodSyncedAt($0.id)?.timeIntervalSince1970 ?? 0)"
            }.joined(separator: ",")
            let imported = GuideScheduler.shared.enabledStates().compactMap(\.lastUpdate).max()
            guide = "\(imported?.timeIntervalSince1970 ?? 0)|\(Int(now.timeIntervalSince1970 / 10800))"
        }
    }

    /// Builds the indexes before the first search needs them (the search screen opened).
    func prepare(keys: Keys, container: ModelContainer) {
        let shelves: [(GFSearchCatalog.Shelf, String)] = [(.live, keys.live), (.guide, keys.guide),
                                                          (.library, keys.library)]
        let playlists = keys.playlists
        let catalog = catalog
        for (shelf, key) in shelves {
            Task.detached(priority: .utility) {
                _ = await catalog.index(shelf, key: key, container: container, playlists: playlists)
            }
        }
    }

    func update(text: String, filter: ContentFilter, keys: Keys, scope: [Playlist], context: ModelContext,
                restriction: ContentRestriction) async {
        guard !text.isEmpty else {
            groups = []
            answered = ""
            return
        }
        let now = Date()
        let request = GFSmartSearch.Request(
            text: text, kinds: Self.kinds(filter), playlists: keys.playlists, scope: Set(scope.map(\.id.uuidString)),
            liveKey: keys.live, guideKey: keys.guide, libraryKey: keys.library, now: now
        )
        let (container, catalog) = (context.container, catalog)
        let search = Task.detached(priority: .userInitiated) {
            await GFSmartSearch.run(request, container: container, catalog: catalog)
        }
        let found = await withTaskCancellationHandler { await search.value } onCancel: { search.cancel() }
        guard !Task.isCancelled else { return }
        self.now = now
        groups = Self.assemble(found, allKinds: filter == .all, context: context, restriction: restriction, now: now)
        answered = text
    }

    /// The matches as rows, in the viewer's view of the library: hidden or restricted ones left out, favourite and
    /// recently watched channels counted up.
    private static func assemble(_ found: GFSmartSearch.Found, allKinds: Bool, context: ModelContext,
                                 restriction: ContentRestriction, now: Date) -> [ResultGroup] {
        var rows: [GFSearchLayout.Row<String>] = []
        var lookup: [String: Row] = [:]
        func add(_ row: Row, _ kind: GFSearchIndex.Kind, _ score: Double) {
            guard lookup[row.id] == nil else { return }
            lookup[row.id] = row
            rows.append(GFSearchLayout.Row(kind: kind, id: row.id, score: score))
        }
        let scores = Dictionary(found.hits.map { ($0.key, $0.score) }, uniquingKeysWith: max)
        func ids(_ kind: GFSearchIndex.Kind) -> [String] {
            found.hits.filter { $0.kind == kind }.map(\.key)
        }
        let categoryIDs = ids(.category)
        if !categoryIDs.isEmpty {
            let fetched = (try? context.fetch(FetchDescriptor<Category>(
                predicate: #Predicate { categoryIDs.contains($0.id) }
            ))) ?? []
            for category in fetched where !category.isHidden && !restriction.hides(categoryID: category.id) {
                add(.category(category, channels: found.channelCounts[category.id] ?? 0), .category,
                    scores[category.id] ?? 0)
            }
        }
        let streamIDs = ids(.channel)
        if !streamIDs.isEmpty {
            let fetched = (try? context.fetch(FetchDescriptor<LiveStream>(
                predicate: #Predicate { streamIDs.contains($0.id) }
            ))) ?? []
            for stream in fetched where !stream.isHidden && !restriction.hides(categoryID: stream.categoryId) {
                add(.channel(stream), .channel, GFSearchLayout.channelScore(
                    scores[stream.id] ?? 0, isFavorite: stream.isFavorite, lastWatched: stream.lastWatchedDate, now: now
                ))
            }
        }
        for airing in found.airings {
            guard let stream = context.model(for: airing.stream) as? LiveStream,
                  !restriction.hides(categoryID: stream.categoryId) else { continue }
            add(.programme(GFProgrammeRow(hit: airing.hit, stream: stream)), .programme, airing.score)
        }
        let filmIDs = ids(.film)
        if !filmIDs.isEmpty {
            let fetched = (try? context.fetch(FetchDescriptor<Movie>(
                predicate: #Predicate { filmIDs.contains($0.id) }
            ))) ?? []
            for movie in fetched where !restriction.hides(categoryID: movie.categoryId) {
                add(.film(movie), .film, scores[movie.id] ?? 0)
            }
        }
        let seriesIDs = ids(.series)
        if !seriesIDs.isEmpty {
            let fetched = (try? context.fetch(FetchDescriptor<Series>(
                predicate: #Predicate { seriesIDs.contains($0.id) }
            ))) ?? []
            for series in fetched where !restriction.hides(categoryID: series.categoryId) {
                add(.series(series), .series, scores[series.id] ?? 0)
            }
        }
        return GFSearchLayout.sections(rows, allKinds: allKinds).map { section in
            ResultGroup(kind: section.kind, rows: section.ids.compactMap { lookup[$0] })
        }
    }
}

/// The search screen's sections. Channels, films and series are drawn as Lume draws them (`lumeRow`); a category
/// opens Live TV on it, a programme on now plays its channel and a later one opens its card.
struct GFSmartSearchSections<LumeRow: View>: View {
    let model: GFSmartSearchModel
    let onPlay: (LiveStream) -> Void
    let onOpenCategory: (Category) -> Void
    @ViewBuilder let lumeRow: (SearchResult) -> LumeRow

    var body: some View {
        ForEach(model.groups) { group in
            Section {
                ForEach(group.rows) { row in
                    rowView(row)
                }
            } header: {
                Text(group.title)
            }
        }
    }

    @ViewBuilder private func rowView(_ row: GFSmartSearchModel.Row) -> some View {
        switch row {
        case let .category(category, channels):
            Button {
                onOpenCategory(category)
            } label: {
                GFSearchCategoryRow(category: category, channels: channels)
            }
            .buttonStyle(.plain)
        case let .channel(stream):
            lumeRow(.liveStream(stream))
        case let .programme(programme):
            Button {
                if programme.hit.isLive(at: Date()) {
                    onPlay(programme.stream)
                } else {
                    model.selection = GFProgrammeSelection(programme)
                }
            } label: {
                GFGuideSearchRow(hit: programme.hit, stream: programme.stream, now: model.now)
            }
            .buttonStyle(.plain)
        case let .film(movie):
            lumeRow(.movie(movie))
        case let .series(series):
            lumeRow(.series(series))
        }
    }
}

/// A live TV category found: its name and how many channels it holds.
struct GFSearchCategoryRow: View {
    let category: Category
    let channels: Int

    private var side: CGFloat {
        GFGuideGlass.isTV ? 66 : 44
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: side * 0.26, style: .continuous)
                .fill(Color.accentColor.opacity(0.16))
                .frame(width: side, height: side)
                .overlay {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: side * 0.4))
                        .foregroundStyle(Color.accentColor)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: category.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(verbatim: "Live TV category · " + (channels == 1 ? "1 channel" : "\(channels) channels"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            #if !os(tvOS)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            #endif
        }
        .contentShape(Rectangle())
    }
}

extension View {
    /// Lume GF: runs search (GFSmartSearch) for the settled `query`, and opens a later programme's card.
    func gfSmartSearch(_ model: GFSmartSearchModel, query: String, filter: ContentFilter, playlists: [Playlist],
                       scope: [Playlist], onPlay: @escaping (LiveStream) -> Void) -> some View {
        modifier(GFSmartSearchHost(model: model, query: query, filter: filter, playlists: playlists, scope: scope,
                                   onPlay: onPlay))
    }
}

private struct GFSmartSearchHost: ViewModifier {
    let model: GFSmartSearchModel
    let query: String
    let filter: ContentFilter
    let playlists: [Playlist]
    let scope: [Playlist]
    let onPlay: (LiveStream) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.contentRestriction) private var restriction

    private struct Key: Equatable {
        let query: String
        let filter: ContentFilter
        let keys: GFSmartSearchModel.Keys
        let scope: [String]
    }

    func body(content: Content) -> some View {
        @Bindable var model = model
        let keys = GFSmartSearchModel.Keys(playlists: playlists)
        content
            .task(id: keys) { model.prepare(keys: keys, container: modelContext.container) }
            .task(id: Key(query: query, filter: filter, keys: keys, scope: scope.map(\.id.uuidString))) {
                await model.update(text: query, filter: filter, keys: keys, scope: scope, context: modelContext,
                                   restriction: restriction)
            }
            .sheet(item: $model.selection) { selection in
                EPGProgramDetailView(stream: selection.stream, cell: selection.cell, now: Date(),
                                     onPlay: { onPlay(selection.stream) })
                    .recordActionFlow(toastPlacement: .sheet)
            }
    }
}
