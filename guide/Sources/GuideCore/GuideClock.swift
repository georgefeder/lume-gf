import Foundation

/// When the next guide check is due (spec: docs/superpowers/specs/2026-09-29-lume-gf-2-guide-design.md).
///
/// Following the server: the guide server builds a new guide every hour and sends the build time as the guide's
/// `Last-Modified`; the next check is due one interval plus a margin after that build. A late server or a failed try
/// is asked again after `floor`. A wrong device clock must not stall the guide: a check is never planned more than
/// one interval plus the margin after the last try.
/// Switch off: Lume's own interval (6 h, daily, ...) after the last good check, with the same floor after a failure.
nonisolated enum GuideClock {
    static let buildInterval: TimeInterval = 60 * 60
    static let margin: TimeInterval = 3 * 60
    static let floor: TimeInterval = 15 * 60

    static func nextCheck(lastCheck: Date?, lastAttempt: Date?, serverBuild: Date?, followServer: Bool,
                          interval: TimeInterval) -> Date {
        guard let attempt = lastAttempt ?? lastCheck else { return .distantPast }
        let earliest = attempt.addingTimeInterval(floor)
        guard followServer else {
            return max(lastCheck.map { $0.addingTimeInterval(interval) } ?? earliest, earliest)
        }
        let latest = attempt.addingTimeInterval(buildInterval + margin)
        let wanted = serverBuild.map { $0.addingTimeInterval(buildInterval + margin) }
            ?? (lastCheck ?? attempt).addingTimeInterval(buildInterval)
        return min(max(wanted, earliest), latest)
    }

    /// The earliest next check over the given (enabled) sources; none means nothing to check.
    static func nextCheck(states: [GuideSourceState], followServer: Bool, interval: TimeInterval) -> Date {
        states.map {
            nextCheck(lastCheck: $0.lastCheck, lastAttempt: $0.lastAttempt, serverBuild: $0.serverBuild,
                      followServer: followServer, interval: interval)
        }.min() ?? .distantFuture
    }
}

/// The one-line guide status for the settings, e.g. "Guide updated 00:13 · server built 00:11".
nonisolated enum GuideStatusSummary {
    static func line(for states: [GuideSourceState], time: (Date) -> String) -> String {
        guard let s = states.max(by: { ($0.lastAttempt ?? .distantPast) < ($1.lastAttempt ?? .distantPast) }),
              let update = s.lastUpdate
        else { return "Guide not updated yet" }
        var line = "Guide updated \(time(update))"
        if let build = s.serverBuild { line += " · server built \(time(build))" }
        if let error = s.lastError, let attempt = s.lastAttempt {
            return "Guide updated \(time(update)) · last check failed \(time(attempt)) (\(error))"
        }
        if let check = s.lastCheck, check > update.addingTimeInterval(60) { line += " · checked \(time(check))" }
        return line
    }
}
