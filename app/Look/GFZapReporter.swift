import Foundation
import QuartzCore
#if canImport(UIKit)
    import UIKit
#endif

/// Times the full-screen player's live channel changes and reports each one to our server once it is over: the
/// picture moving, the open failing, or the next change replacing it (Georgs, 4 Nov 2026, through the Glasgow Pi Admin
/// chat: "measure first"). The report is one GET of `/gf-zap` on the Dispatcharr host the channel itself plays from,
/// whose access log the server reads (a 302 to its login page is the expected answer); only for streams from a
/// `dispatcharr.` host, so another playlist's server is never asked. It carries the device kind, the build, the
/// channel's number and the timings: never an address, login, token or channel name. Fire and forget, off the main
/// and player threads, three seconds at most, no retry, no cookies, no redirects followed, errors ignored.
nonisolated final class GFZapReporter: @unchecked Sendable {
    static let shared = GFZapReporter()

    private let lock = NSLock()
    private var current: GFZapTiming?
    /// The stream last timed: the player builds its options on every redraw, so only a new stream starts a timing.
    private var lastStream: String?
    private var endpoint: URL?
    private var device = "iphone"
    private let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    /// A change still not over after this long is reported as it is.
    private let giveUp: Double = 30

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        config.waitsForConnectivity = false
        return URLSession(configuration: config, delegate: GFNoRedirects(), delegateQueue: nil)
    }()

    private init() {}

    /// The full-screen player is set up for `url` (KSPlayerOptionsFactory.make, on every redraw): a new live
    /// stream's change is timed from now; the one before, if not over, is reported as it is (replaced).
    @MainActor
    func expect(url: URL, isLive: Bool, lowLatency: Bool? = nil, liveBuffer: Int? = nil) {
        let now = CACurrentMediaTime()
        let kind = Self.deviceKind
        lock.withLock {
            let stream = url.lastPathComponent
            guard stream != lastStream else { return }
            lastStream = stream
            if let old = current { send(old) }
            current = nil
            guard isLive, let scheme = url.scheme, let host = url.host(), host.hasPrefix("dispatcharr.") else {
                endpoint = nil
                return
            }
            endpoint = URL(string: "\(scheme)://\(host)/gf-zap")
            device = kind
            current = GFZapTiming(stream: stream, started: now, lowLatency: lowLatency, liveBuffer: liveBuffer)
        }
    }

    /// One line of KSPlayer's channel-change log (KSOptions.gfZapReport), on KSPlayer's own threads.
    func note(_ line: String) {
        let now = CACurrentMediaTime()
        lock.withLock {
            // the player closed: the same channel opened again later is a new change
            if let lastStream, line.hasPrefix(lastStream + " shuts down") { self.lastStream = nil }
            guard var timing = current else { return }
            let over = timing.note(line, at: now) || now - timing.started > giveUp
            current = over ? nil : timing
            if over { send(timing) }
        }
    }

    /// Called with the lock held; the request itself runs on the session's own queue.
    private func send(_ timing: GFZapTiming) {
        guard let endpoint, var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return
        }
        components.percentEncodedQuery = timing.query(device: device, build: build)
        guard let url = components.url else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        request.httpShouldHandleCookies = false
        session.dataTask(with: request).resume()
    }

    @MainActor
    private static var deviceKind: String {
        #if os(tvOS)
            "atv"
        #elseif canImport(UIKit)
            UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #else
            "mac"
        #endif
    }
}

/// The report's answer is a redirect to the server's login page: never followed (the push token's report too,
/// GFGuidePushClient). The completion-handler form: Swift 6.3.3 crashed making the async form's Objective-C thunk
/// (CI run 41885691907).
nonisolated final class GFNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
                    newRequest _: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
