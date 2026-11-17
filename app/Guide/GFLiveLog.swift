import Foundation

/// Lume GF's live log (Georgs, 17 Nov 2026: "why can't there be a probe in the app so u can debug live here"; "all the
/// time but so it doesn't affect battery really"): short lines from our own code (the guide's steps, wakes, the
/// player's start, stalls and engine changes) go to the guide's own Dispatcharr host as GETs of `/gf-log`, read from
/// Traefik's access log like `/gf-zap` (selfhost-aio host-scripts/lume-live-log.py). Kept on the device and sent in
/// one go at most once a minute while the app is on screen, and once at the end of a background wake, when the radio
/// is on anyway: nothing is sent just for the log. Lines that could carry an address or login never leave
/// (GFLiveLogLines.clean). Fire and forget: no cookies, no redirects followed, a failed send keeps its lines.
nonisolated final class GFLiveLog: @unchecked Sendable {
    static let shared = GFLiveLog()

    private let lock = NSLock()
    private var lines: [String] = []
    private var lastSent = Date.distantPast
    private var sequence = 0
    private var endpoint: URL?
    private var appActive = false
    private var sending = false
    private let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        return URLSession(configuration: config, delegate: GFNoRedirects(), delegateQueue: nil)
    }()

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private init() {}

    /// One line, stamped with the time (UTC, as the server's logs are).
    static func note(_ text: String) {
        shared.add(text)
    }

    /// Where to send: the guide's own `dispatcharr.` host (the same server the channel-change report goes to).
    func useGuideHost(_ guideURLs: [String]) {
        guard let guide = guideURLs.lazy.compactMap({ URLComponents(string: $0) })
            .first(where: { ($0.host ?? "").hasPrefix("dispatcharr.") }), let host = guide.host
        else { return }
        var log = URLComponents()
        log.scheme = guide.scheme ?? "https"
        log.host = host
        log.port = guide.port
        log.path = "/gf-log"
        lock.withLock { endpoint = log.url }
    }

    /// The app came on screen or left it (leaving, GuideScheduler sends what is waiting in iOS's background time).
    func appActive(_ active: Bool) {
        lock.withLock { appActive = active }
    }

    /// Sends what is waiting and returns once the requests are done (ten seconds at most): the end of a background
    /// wake waits for it, or iOS suspends the app with the requests still out.
    func flushAndWait() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            flush { done.resume() }
        }
    }

    /// Sends what is waiting now (the app leaving the screen, enough lines). `finished` runs once it is done.
    func flush(finished: (@Sendable () -> Void)? = nil) {
        let (batches, url, first) = lock.withLock { () -> ([[String]], URL?, Int) in
            guard !sending, let endpoint, !lines.isEmpty else { return ([], nil, 0) }
            sending = true
            let taken = lines
            lines = []
            lastSent = Date()
            let first = sequence
            sequence += GFLiveLogLines.batches(taken).count
            return (GFLiveLogLines.batches(taken), endpoint, first)
        }
        guard let url, !batches.isEmpty else {
            finished?()
            return
        }
        let group = DispatchGroup()
        let unsent = Unsent()
        for (offset, batch) in batches.enumerated() {
            guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { continue }
            parts.percentEncodedQuery = [("d", GFGuideReporter.device), ("b", build), ("s", String(first + offset)),
                                         ("l", batch.joined(separator: "\n"))]
                .map { "\($0.0)=\(GFLiveLogLines.queryValue($0.1))" }.joined(separator: "&")
            guard let request = parts.url.map({ URLRequest(url: $0, cachePolicy: .reloadIgnoringLocalCacheData,
                                                           timeoutInterval: 10) }) else { continue }
            group.enter()
            session.dataTask(with: request) { _, response, _ in
                if response == nil { unsent.keep(batch) }
                group.leave()
            }.resume()
        }
        group.notify(queue: .global(qos: .utility)) { [self] in
            lock.withLock {
                sending = false
                // a failed send keeps its lines (ahead of the newer ones), within the limit
                lines = Array((unsent.lines + lines).suffix(GFLiveLogLines.maxKept))
            }
            finished?()
        }
    }

    private func add(_ text: String) {
        guard let line = GFLiveLogLines.clean("\(Self.clock.string(from: Date())) \(text)") else { return }
        let send = lock.withLock { () -> Bool in
            lines.append(line)
            if lines.count > GFLiveLogLines.maxKept { lines.removeFirst(lines.count - GFLiveLogLines.maxKept) }
            return GFLiveLogLines.shouldSend(waiting: lines.count, sinceLast: Date().timeIntervalSince(lastSent),
                                             appActive: appActive)
        }
        if send { flush() }
    }

    /// The lines of batches whose send failed, gathered from the requests' own threads.
    nonisolated private final class Unsent: @unchecked Sendable {
        private let lock = NSLock()
        private var kept: [String] = []

        var lines: [String] {
            lock.withLock { kept }
        }

        func keep(_ batch: [String]) {
            lock.withLock { kept += batch }
        }
    }
}
