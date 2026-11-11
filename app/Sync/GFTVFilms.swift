import Foundation
import OSLog
import SwiftData
import SwiftUI

/// Lume GF: films and series on this device (GFCatalogPlan.tvFilmsAndSeriesKey). The Apple TV leaves them out unless
/// switched on in Settings › Library: no Movies and Series tabs, Xtream syncs fetch live channels only, and the ones
/// stored before are deleted once. iCloud keeps their watch state, favourites and progress: the reconcile reads a
/// catalogue row that is gone as a pending pull, never as a deletion (CloudSyncEngine.resolveClearChecks).
nonisolated enum GFTVFilms {
    /// Whether this device loads films and series: always off tvOS, on the Apple TV only once switched on.
    static var wanted: Bool {
        #if os(tvOS)
            UserDefaults.standard.bool(forKey: GFCatalogPlan.tvFilmsAndSeriesKey)
        #else
            true
        #endif
    }

    /// Deletes the stored films and series while they are left out here: episodes and cast first, then the titles, so
    /// no relationship rule is involved, each kind saved on its own to keep the work small. Their categories stay
    /// (a few hundred rows): a category gone here would read to the iCloud reconcile as its parental restriction
    /// lifted, on every device. Their sync stamps go, so switching them back on fetches them at once.
    static func dropIfLeftOut(container: ModelContainer) async {
        guard !wanted else { return }
        await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let movies = (try? context.fetchCount(FetchDescriptor<Movie>())) ?? 0
            let series = (try? context.fetchCount(FetchDescriptor<Series>())) ?? 0
            guard movies + series > 0 else { return }
            do {
                try context.delete(model: Episode.self)
                try context.save()
                try context.delete(model: CastMember.self)
                try context.save()
                try context.delete(model: Movie.self)
                try context.save()
                try context.delete(model: Series.self)
                try context.save()
                let playlists = (try? context.fetch(FetchDescriptor<Playlist>())) ?? []
                for playlist in playlists {
                    UserDefaults.standard.removeObject(forKey: GFCatalogStamps.key(playlist.id))
                }
                Logger.database.info("Films and series left out here: \(movies) films, \(series) series deleted")
            } catch {
                let reason = error.localizedDescription
                Logger.database.error("Films and series left out here, not deleted: \(reason, privacy: .public)")
            }
        }.value
    }
}

#if os(tvOS)

    /// Settings › Library on the Apple TV: films and series here or not. Off deletes the stored ones; on fetches them
    /// in the background (they need about a day's first sync on a big playlist).
    struct GFTVFilmsRow: View {
        @Environment(\.modelContext) private var modelContext
        @AppStorage(GFCatalogPlan.tvFilmsAndSeriesKey) private var filmsAndSeries = false
        @Query private var playlists: [Playlist]

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                TVOptionToggleRow(title: "Films & Series on This Apple TV", isOn: $filmsAndSeries)
                // swiftlint:disable:next line_length
                Text("Off keeps this Apple TV to live channels and the guide: less for tvOS to clear when its storage runs low, and a quicker start after it does. Your iPhone and iPad keep theirs.")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, TVSettingsMetrics.rowHPadding)
                    .padding(.top, 6)
            }
            .onChange(of: filmsAndSeries) { _, wanted in
                let container = modelContext.container
                if wanted {
                    for playlist in playlists where playlist.sourceType == .xtream && playlist.syncEnabled {
                        GFBackgroundCatalogSync.shared.enqueue(playlistID: playlist.id, scope: .vod, container: container)
                    }
                } else {
                    // a films-and-series sync still running would only bring them back
                    for playlist in playlists { GFBackgroundCatalogSync.shared.cancel(playlistID: playlist.id) }
                    Task { await GFTVFilms.dropIfLeftOut(container: container) }
                }
            }
        }
    }

#endif
