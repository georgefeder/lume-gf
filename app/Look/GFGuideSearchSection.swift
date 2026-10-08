import SwiftData
import SwiftUI

/// Search's "On TV" (Georgs, 8 Oct: searching "Shark Tank", when and where will it air?): guide programmes whose title
/// matches, on now or later, on this playlist's channels (every playlist's with "Search All Playlists"). One on now
/// plays its channel; a later one opens the programme's card (Lume 2.4: record it from there).
@MainActor
@Observable
final class GFGuideSearchModel {
    struct Row: Identifiable {
        let hit: GFGuideSearchHit
        let stream: LiveStream
        var id: String {
            hit.listingID + "|" + stream.id
        }
    }

    struct Selection: Identifiable {
        let id: String
        let stream: LiveStream
        let cell: EPGProgramCell
    }

    var rows: [Row] = []
    var now = Date()
    var selection: Selection?
}

/// The matching, off the main thread: programmes by title (not ended, by start, at most 300), then this playlist's
/// visible channels that carry them (lowest channel number first).
nonisolated enum GFGuideSearchFetcher {
    struct Found: Sendable {
        var hits: [GFGuideSearchHit] = []
        /// guide channel id → the channel row that carries it
        var streams: [String: PersistentIdentifier] = [:]
    }

    static func fetch(container: ModelContainer, query: String, playlistIDs: [String], now: Date) -> Found {
        let context = ModelContext(container)
        var listings = FetchDescriptor<EPGListing>(
            predicate: #Predicate { $0.end > now && $0.title.localizedStandardContains(query) },
            sortBy: [SortDescriptor(\.start)]
        )
        listings.fetchLimit = 300
        guard let matched = try? context.fetch(listings), !matched.isEmpty else { return Found() }
        let wanted = Set(matched.map(\.channelId))
        var streams: [String: PersistentIdentifier] = [:]
        for playlistID in playlistIDs {
            guard !Task.isCancelled else { return Found() }
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
        let hits = GFGuideSearch.hits(matched.map {
            GFGuideSearchHit(listingID: $0.id, channelId: $0.channelId, title: $0.title, subtitle: $0.subtitle,
                             detail: $0.listingDescription, start: $0.start, end: $0.end)
        }, channels: Set(streams.keys), now: now)
        let used = Set(hits.map(\.channelId))
        return Found(hits: hits, streams: streams.filter { used.contains($0.key) })
    }
}

/// The "On TV" section in search's list (nothing when no programme matches).
struct GFGuideSearchSection: View {
    let model: GFGuideSearchModel
    let onPlay: (LiveStream) -> Void

    var body: some View {
        if !model.rows.isEmpty {
            Section {
                ForEach(model.rows) { row in
                    Button {
                        open(row)
                    } label: {
                        GFGuideSearchRow(hit: row.hit, stream: row.stream, now: model.now)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("On TV")
            }
        }
    }

    private func open(_ row: GFGuideSearchModel.Row) {
        if row.hit.isLive(at: Date()) {
            onPlay(row.stream)
            return
        }
        let hit = row.hit
        model.selection = GFGuideSearchModel.Selection(
            id: row.id, stream: row.stream,
            cell: EPGProgramCell(id: hit.listingID, title: hit.title, detail: hit.detail, start: hit.start,
                                 end: hit.end, listingID: hit.listingID, isGap: false, width: 0)
        )
    }
}

/// A programme found: its title (and episode), on now or when it airs, and the channel.
struct GFGuideSearchRow: View {
    let hit: GFGuideSearchHit
    let stream: LiveStream
    let now: Date

    private var logoSide: CGFloat {
        GFGuideGlass.isTV ? 66 : 44
    }

    var body: some View {
        HStack(spacing: 12) {
            EPGLogoTile(url: URL(string: stream.streamIcon ?? ""), side: logoSide, cornerRadius: logoSide * 0.26,
                        padding: logoSide * 0.11, glyphSize: logoSide * 0.39)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: hit.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if let subtitle = hit.subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if hit.isLive(at: now) {
                        LiveBadge()
                        Text(verbatim: GFChannelNames.title(for: stream.name))
                    } else {
                        Text(verbatim: GFGuideSearch.whenLabel(start: hit.start, end: hit.end, now: now,
                                                               calendar: .current, locale: .current)
                            + " · " + GFChannelNames.title(for: stream.name))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

extension View {
    /// Lume GF: runs search's guide pass for `query` (only while the filter wants live TV) and opens a later
    /// programme's card.
    func gfGuideSearch(_ model: GFGuideSearchModel, query: String, playlistIDs: [String], isWanted: Bool,
                       onPlay: @escaping (LiveStream) -> Void) -> some View {
        modifier(GFGuideSearchHost(model: model, query: query, playlistIDs: playlistIDs, isWanted: isWanted,
                                   onPlay: onPlay))
    }
}

private struct GFGuideSearchHost: ViewModifier {
    let model: GFGuideSearchModel
    let query: String
    let playlistIDs: [String]
    let isWanted: Bool
    let onPlay: (LiveStream) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.contentRestriction) private var restriction

    private struct Key: Equatable {
        let query: String
        let playlistIDs: [String]
        let isWanted: Bool
    }

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .task(id: Key(query: query, playlistIDs: playlistIDs, isWanted: isWanted)) { await refresh() }
            .sheet(item: $model.selection) { selection in
                EPGProgramDetailView(stream: selection.stream, cell: selection.cell, now: Date(),
                                     onPlay: { onPlay(selection.stream) })
                    .recordActionFlow(toastPlacement: .sheet)
            }
    }

    private func refresh() async {
        guard isWanted, !query.isEmpty, !playlistIDs.isEmpty else {
            model.rows = []
            return
        }
        let container = modelContext.container
        let (query, playlistIDs, now) = (query, playlistIDs, Date())
        let fetch = Task.detached(priority: .userInitiated) {
            GFGuideSearchFetcher.fetch(container: container, query: query, playlistIDs: playlistIDs, now: now)
        }
        let found = await withTaskCancellationHandler { await fetch.value } onCancel: { fetch.cancel() }
        guard !Task.isCancelled else { return }
        model.now = now
        model.rows = found.hits.compactMap { hit in
            guard let id = found.streams[hit.channelId], let stream = modelContext.model(for: id) as? LiveStream,
                  !restriction.hides(categoryID: stream.categoryId) else { return nil }
            return GFGuideSearchModel.Row(hit: hit, stream: stream)
        }
    }
}
