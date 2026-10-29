import Foundation
import OSLog
import SwiftData
import SwiftUI
#if !os(macOS)
    import BackgroundTasks
#endif
#if canImport(UIKit)
    import UIKit
#endif

/// The "follow the guide server" switch (default on in Lume GF).
nonisolated enum GuideSettings {
    static let followServerKey = "gf.guide.followServer"

    static var followServer: Bool {
        UserDefaults.standard.object(forKey: followServerKey) as? Bool ?? true
    }
}

/// The guide settings' status line, kept current by the scheduler.
@Observable
final class GuideStatus {
    static let shared = GuideStatus()
    private(set) var line = "Guide not updated yet"

    private init() {}

    func reload() {
        line = GuideStatusSummary.line(for: GuideScheduler.shared.enabledStates(), time: Self.when)
    }

    /// A time today, "yesterday" and a time, or the date and a time: a bare "21:48" read as later today when it was
    /// yesterday's (Georgs, 23 Oct).
    nonisolated static func when(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return time }
        if Calendar.current.isDateInYesterday(date) { return "yesterday \(time)" }
        return "\(date.formatted(.dateTime.day().month(.abbreviated))) \(time)"
    }
}

/// Keeps Lume GF's guide in step with the guide server: decides when a check is due (`GuideClock`), wakes the app
/// for it while it is open (a timer) and asks Apple for background time around the next due check.
final class GuideScheduler {
    static let shared = GuideScheduler()
    nonisolated static let refreshTaskID = "\(Bundle.main.bundleIdentifier ?? "lume").guide.refresh"
    nonisolated static let importTaskID = "\(Bundle.main.bundleIdentifier ?? "lume").guide.import"

    private var container: ModelContainer?
    private var timer: Task<Void, Never>?
    private var isActive = false
    /// Set once Lume's launch task has run its own first guide check (Lume's launch order stays as it is).
    private var launched = false

    private init() {}

    func configure(container: ModelContainer) {
        self.container = container
    }

    /// Only enabled sources count, so a disabled or deleted source never keeps the guide "due".
    func enabledStates() -> [GuideSourceState] {
        guard let container else { return [] }
        let sources = (try? ModelContext(container).fetch(
            FetchDescriptor<EPGSource>(predicate: #Predicate { $0.isEnabled })
        )) ?? []
        return sources.map { GuideSourceStateStore.shared.state(for: $0.id) }
    }

    func nextCheck() -> Date {
        let raw = UserDefaults.standard.string(forKey: SyncFrequency.epgStorageKey) ?? ""
        return GuideClock.nextCheck(states: enabledStates(), followServer: GuideSettings.followServer,
                                    interval: SyncFrequency.resolveEPG(raw).interval)
    }

    func isDue(now: Date = Date()) -> Bool {
        nextCheck() <= now
    }

    /// The app finished launching (it is in the foreground).
    func appLaunched() {
        launched = true
        #if canImport(UIKit)
            isActive = UIApplication.shared.applicationState != .background
        #else
            isActive = true
        #endif
        GuideStatus.shared.reload()
        if isActive { armTimer() }
    }

    func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .active:
            isActive = true
            guard launched else { return } // the launch task runs the first check
            EPGSyncService.shared.syncIfDue()
            armTimer()
        case .background:
            isActive = false
            timer?.cancel()
            timer = nil
            submitBackgroundRefresh()
            submitImportTask(onPower: true)
        default:
            break
        }
    }

    /// A refresh ended, however it ended: plan the next one and update the status line.
    func refreshFinished() {
        GuideStatus.shared.reload()
        if isActive { armTimer() }
        submitBackgroundRefresh()
    }

    /// While the app is open, check again when the next check is due (at least a minute, at most an hour away).
    private func armTimer() {
        timer?.cancel()
        let delay = min(max(nextCheck().timeIntervalSinceNow, 60), 3600)
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            EPGSyncService.shared.syncIfDue()
            self?.armTimer()
        }
    }

    #if !os(macOS)
        /// Registers both background tasks. Must run before the app finishes launching (`LumeApp.init`).
        nonisolated static func registerBackgroundTasks() {
            for id in [refreshTaskID, importTaskID] {
                BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
                    // Set at once: Apple may end the time before the main actor gets to the refresh.
                    task.expirationHandler = {
                        Logger.database.info("Guide: iOS ended the background time")
                        Task { @MainActor in
                            EPGSyncService.shared.cancelBackgroundRefresh()
                            GuideScheduler.shared.submitImportTask()
                        }
                    }
                    Task { @MainActor in await GuideScheduler.shared.runBackground(task) }
                }
            }
        }

        /// Each wake is in the diagnostic report (Georgs, 29 Oct: is the guide refreshed while the app is closed?).
        private func runBackground(_ task: BGTask) async {
            let kind = task is BGProcessingTask ? "overnight import" : "background refresh"
            Logger.database.info("Guide: iOS woke the app for its \(kind, privacy: .public)")
            let finished = await EPGSyncService.shared.refreshIfDueAndWait()
            let outcome = finished ? "done" : "not finished"
            Logger.database.info("Guide: \(kind, privacy: .public) \(outcome, privacy: .public)")
            submitBackgroundRefresh()
            if finished, task is BGProcessingTask { submitImportTask(onPower: true) }
            task.setTaskCompleted(success: finished)
        }

        private func submitBackgroundRefresh() {
            let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
            request.earliestBeginDate = GuideClock.backgroundBeginDate(next: nextCheck(), now: Date())
            do {
                try BGTaskScheduler.shared.submit(request)
                let after = (request.earliestBeginDate ?? Date()).formatted(date: .omitted, time: .shortened)
                Logger.database.info("Guide: background refresh asked of iOS for after \(after, privacy: .public)")
            } catch {
                Logger.database.info("Guide background refresh not scheduled: \(error.localizedDescription, privacy: .public)")
            }
        }

        /// The longer background time Apple gives while the device is idle: to finish a refresh the short one cut off,
        /// or (`onPower`) to keep the guide current while the iPhone charges overnight, so it opens with today's
        /// programmes (Georgs, 9 Oct: a guide a day old took a minute to come in at launch).
        private func submitImportTask(onPower: Bool = false) {
            let request = BGProcessingTaskRequest(identifier: Self.importTaskID)
            request.requiresNetworkConnectivity = true
            if onPower {
                request.requiresExternalPower = true
                request.earliestBeginDate = GuideClock.backgroundBeginDate(next: nextCheck(), now: Date())
            }
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                Logger.database.info("Guide background import not scheduled: \(error.localizedDescription, privacy: .public)")
            }
        }
    #else
        nonisolated static func registerBackgroundTasks() {}
        private func submitBackgroundRefresh() {}
        private func submitImportTask(onPower _: Bool = false) {}
    #endif
}
