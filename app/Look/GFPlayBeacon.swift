import Foundation

/// Sends the player's moments of a live play (GFPlayEvent) to the server as they happen: one small GET of `/gf-play`
/// on the channel's own Dispatcharr host each, while the stream is playing anyway, read from Traefik's access log like
/// `/gf-zap` (the Oracle Admin joins them with its record of every live play by time and channel number). Live
/// channels on our own server only; films, episodes and other hosts send nothing. Fire and forget: no cookies, no
/// redirects followed, nothing kept when a send fails.
nonisolated final class GFPlayBeacon: @unchecked Sendable {
    static let shared = GFPlayBeacon()

    private let lock = NSLock()
    private var endpoint: URL?
    private var stream: String?
    private var session = ""
    private var lowLatency: Bool?
    private var liveBuffer: Int?
    private var device = "iphone"
    /// The stream before this one and its session, for its close arriving after the next stream was set up.
    private var previous: (stream: String, session: String)?
    /// When the stream was last closed and last given a reason to open again: an open after a close with no reason
    /// shortly around it is a new play (a reopen's close comes as the old player view goes, just after the reason).
    private var closedAt: Date?
    private var reopenedAt: Date?
    private let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        config.waitsForConnectivity = false
        return URLSession(configuration: config, delegate: GFNoRedirects(), delegateQueue: nil)
    }()

    private init() {}

    /// The player is set up for `url` (from GFZapReporter.expect, which sees every stream the player is given). A
    /// new stream starts a new session; anything but a live channel on a `dispatcharr.` host stops the beacon.
    func expect(url: URL, isLive: Bool, lowLatency: Bool?, liveBuffer: Int?, device: String) {
        lock.withLock {
            let name = url.lastPathComponent
            guard isLive, let scheme = url.scheme, let host = url.host(), host.hasPrefix("dispatcharr.") else {
                endpoint = nil
                stream = nil
                return
            }
            // the same channel at its other container (the TS retry of an HLS address) is the same play
            guard name.split(separator: ".").first != stream?.split(separator: ".").first else {
                stream = name
                return
            }
            endpoint = URL(string: "\(scheme)://\(host)/gf-play")
            if let stream { previous = (stream, session) }
            stream = name
            session = Self.newSession()
            closedAt = nil
            reopenedAt = nil
            self.lowLatency = lowLatency
            self.liveBuffer = liveBuffer
            self.device = device
        }
    }

    func send(_ kind: GFPlayEvent.Kind) {
        let at = Int64(Date().timeIntervalSince1970 * 1000)
        lock.withLock {
            guard let endpoint, let stream,
                  let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
            else { return }
            let now = Date()
            switch kind {
            case .reopen: reopenedAt = now
            case .open:
                if let closedAt, reopenedAt.map({ abs($0.timeIntervalSince(closedAt)) > 5 }) ?? true {
                    session = Self.newSession()
                    reopenedAt = nil
                }
                closedAt = nil
            default: break
            }
            var event = GFPlayEvent(kind: kind, stream: stream, at: at, session: session)
            if kind == .open {
                event.lowLatency = lowLatency
                event.liveBuffer = liveBuffer
            }
            post(event, to: components)
        }
    }

    /// The player view for `stream` went away. A close for the stream before (the next channel's set-up came first)
    /// goes with that stream and its session.
    func close(stream name: String) {
        let at = Int64(Date().timeIntervalSince1970 * 1000)
        lock.withLock {
            guard let endpoint, let current = stream,
                  let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
            else { return }
            let base = { (name: String) in name.split(separator: ".").first.map(String.init) ?? name }
            if base(name) == base(current) {
                closedAt = Date()
                post(GFPlayEvent(kind: .close, stream: current, at: at, session: session), to: components)
            } else if let previous, base(name) == base(previous.stream) {
                post(GFPlayEvent(kind: .close, stream: previous.stream, at: at, session: previous.session), to: components)
            }
        }
    }

    /// Called with the lock held; the request runs on the session's own queue.
    private func post(_ event: GFPlayEvent, to endpoint: URLComponents) {
        var components = endpoint
        components.percentEncodedQuery = event.query(device: device, build: build)
        guard let url = components.url else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpShouldHandleCookies = false
        urlSession.dataTask(with: request).resume()
    }

    private static func newSession() -> String {
        String(UUID().uuidString.prefix(6)).lowercased()
    }

    static func send(_ kind: GFPlayEvent.Kind) {
        shared.send(kind)
    }
}
