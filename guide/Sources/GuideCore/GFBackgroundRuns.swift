import Foundation

/// The times the system woke the app to refresh the guide while it was closed, for the TV Guide settings: how often
/// iOS or tvOS really gives it that time (Georgs, 12 Nov 2026: "how do we know if it's correctly syncing it every hour
/// in background"). Kept two days on the device, a wake cut short by the system marked as such, and one the guide
/// server's push asked for (GFGuidePush) marked too.
nonisolated enum GFBackgroundRuns {
    static let key = "gf.guide.backgroundRuns"
    static let keptFor: TimeInterval = 48 * 60 * 60
    static let most = 48

    struct Run: Codable, Equatable {
        var at: Date
        var finished: Bool
        /// The server's push woke the app (nil in wakes kept before pushes)
        var push: Bool?
    }

    static func load(_ defaults: UserDefaults = .standard) -> [Run] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Run].self, from: $0) } ?? []
    }

    private static func save(_ runs: [Run], _ defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(runs) { defaults.set(data, forKey: key) }
    }

    /// A wake begins: kept as not finished until `finish` says otherwise (the system may end it first).
    static func begin(at now: Date = Date(), push: Bool = false, defaults: UserDefaults = .standard) {
        let kept = load(defaults).filter { now.timeIntervalSince($0.at) < keptFor }
        save(Array((kept + [Run(at: now, finished: false, push: push ? true : nil)]).suffix(most)), defaults)
    }

    /// The wake begun last ended, its refresh done or not.
    static func finish(_ finished: Bool, defaults: UserDefaults = .standard) {
        var runs = load(defaults)
        guard !runs.isEmpty else { return }
        runs[runs.count - 1].finished = finished
        save(runs, defaults)
    }

    /// Today's wakes, oldest first ("Refreshed while closed today: 03:10, 06:12 (cut short), 09:15 (push)"); the
    /// last one when there was none today; or none yet.
    static func line(_ runs: [Run], now: Date, calendar: Calendar = .current, time: (Date) -> String,
                     when: (Date) -> String) -> String {
        let today = runs.filter { calendar.isDate($0.at, inSameDayAs: now) && $0.at <= now }
        guard !today.isEmpty else {
            return runs.last.map { "Last refreshed while closed: \(when($0.at))" } ?? "Not refreshed while closed yet"
        }
        let times = today.map { run in
            let marks = [run.push == true ? "push" : nil, run.finished ? nil : "cut short"].compactMap { $0 }
            return marks.isEmpty ? time(run.at) : "\(time(run.at)) (\(marks.joined(separator: ", ")))"
        }
        return "Refreshed while closed today: " + times.joined(separator: ", ")
    }
}
