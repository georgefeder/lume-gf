import Foundation
import OSLog
import SwiftData

/// When this device last fetched a playlist's films and series (device-local: each device keeps its own catalogue).
nonisolated enum GFCatalogStamps {
    private static func key(_ playlistID: UUID) -> String {
        "gf.catalog.vodSyncedAt." + playlistID.uuidString
    }

    static func vodSyncedAt(_ playlistID: UUID, defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: key(playlistID)) as? Date
    }

    static func markVODSynced(_ playlistID: UUID, at date: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: key(playlistID))
    }
}

/// Lume GF: playlist syncs nobody waits for (GFCatalogPlan): one at a time, out of sight. They never hold the guide
/// refresh back, unlike Lume's covered syncs: the playlist's channels are already in, and a daily sync of films and
/// series (which waits while video plays here, ContentSyncManager.gfWaitWhilePlaying) kept the iPhone's guide empty
/// for as long as it ran (Georgs, 9 Oct: "when i launch it, it doesnt automatically sync"). Once live channels are
/// re-synced, the guide checks for programmes of new ones.
@MainActor
final class GFBackgroundCatalogSync {
    static let shared = GFBackgroundCatalogSync()

    private struct Job: Equatable {
        var playlistID: UUID
        var scope: GFSyncScope
    }

    private var queue: [Job] = []
    private var running: (job: Job, task: Task<Void, Never>)?
    private var container: ModelContainer?

    /// Queues a background sync (a job already queued or running for the playlist is not added twice).
    func enqueue(playlistID: UUID, scope: GFSyncScope, container: ModelContainer) {
        self.container = container
        guard running?.job.playlistID != playlistID, !queue.contains(where: { $0.playlistID == playlistID }) else {
            return
        }
        queue.append(Job(playlistID: playlistID, scope: scope))
        runNext()
    }

    /// A covered sync of this playlist is starting (Sync Now): a background one for it stops and leaves the queue.
    func cancel(playlistID: UUID) {
        queue.removeAll { $0.playlistID == playlistID }
        if let running, running.job.playlistID == playlistID {
            running.task.cancel()
        }
    }

    func isSyncing(playlistID: UUID) -> Bool {
        running?.job.playlistID == playlistID
    }

    private func runNext() {
        guard running == nil, let container, !queue.isEmpty else { return }
        let job = queue.removeFirst()
        let task = Task { [weak self] in
            await Self.run(job, container: container)
            self?.running = nil
            self?.runNext()
        }
        running = (job, task)
    }

    private static func run(_ job: Job, container: ModelContainer) async {
        let playlistID = job.playlistID
        guard let playlist = try? ModelContext(container).fetch(
            FetchDescriptor<Playlist>(predicate: #Predicate { $0.id == playlistID })
        ).first, playlist.syncEnabled, playlist.syncStatus != .syncing else { return }
        var succeeded = false
        do {
            let manager = ContentSyncManager(modelContainer: container, gfScope: job.scope, gfBackground: true)
            try await BackgroundActivity.perform("Playlist sync (background)") {
                try await manager.syncPlaylist(playlist)
            }
            succeeded = true
            ContentIndexingService.shared.kick(after: .seconds(3))
            Logger.database.info("Lume GF: background \(job.scope.rawValue) sync of \(playlistID) done")
        } catch {
            Logger.database.info("Lume GF: background \(job.scope.rawValue) sync of \(playlistID) ended: \(error)")
        }
        if succeeded, job.scope.includesLive { EPGSyncService.shared.channelsDidSync() }
    }
}
