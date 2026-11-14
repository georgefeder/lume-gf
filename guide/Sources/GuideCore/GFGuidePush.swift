import Foundation

/// The guide server's silent push after each hourly build (Georgs, 13 Nov 2026: iOS woke the app nine times overnight
/// on the charger and not once in the 7½ hours after; "bigger change yea"). The push asks iOS to wake the app right
/// after the build, so the guide is checked then, day or night. The device's push token reaches the server as one GET of
/// `/gf-push` on the guide's own Dispatcharr host, read from its access log like `/gf-zap`: no route, no login.
nonisolated enum GFGuidePush {
    static let reportedKey = "gf.guide.pushReported"
    /// Told again after a day even when nothing changed: the server keeps a week of access logs.
    static let reportEvery: TimeInterval = 24 * 60 * 60

    struct Reported: Codable, Equatable {
        var token: String
        var build: String
        var at: Date
    }

    /// Ours carry `"gf": "guide"`; other pushes (iCloud's change notices) are left alone.
    static func isGuidePush(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let mark = userInfo[AnyHashable("gf")] as? String else { return false }
        return mark == "guide"
    }

    static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    /// The report's address: only a guide served from a `dispatcharr.` host (our server) is told the token.
    static func reportURL(guideURLs: [String], device: String, build: String, token: String) -> URL? {
        guard let guide = guideURLs.lazy.compactMap({ URLComponents(string: $0) })
            .first(where: { ($0.host ?? "").hasPrefix("dispatcharr.") }),
            let host = guide.host
        else { return nil }
        var report = URLComponents()
        report.scheme = guide.scheme ?? "https"
        report.host = host
        report.port = guide.port
        report.path = "/gf-push"
        report.queryItems = [.init(name: "d", value: device), .init(name: "b", value: build),
                             .init(name: "t", value: token)]
        return report.url
    }

    /// A new token or build, or a day since the last report.
    static func shouldReport(token: String, build: String, last: Reported?, now: Date) -> Bool {
        guard let last else { return true }
        return last.token != token || last.build != build || now.timeIntervalSince(last.at) >= reportEvery
    }

    static func loadReported(_ defaults: UserDefaults = .standard) -> Reported? {
        defaults.data(forKey: reportedKey).flatMap { try? JSONDecoder().decode(Reported.self, from: $0) }
    }

    static func saveReported(_ reported: Reported, _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(reported) { defaults.set(data, forKey: reportedKey) }
    }
}
