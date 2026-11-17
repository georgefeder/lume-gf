import Foundation
#if canImport(UIKit)
    import UIKit
#endif

/// Sends a guide refresh's timings (GFGuideTiming) as one GET of `/gf-guide` on the guide's own `dispatcharr.` host,
/// like the channel-change report (GFZapReporter): fire and forget, ten seconds at most, no cookies, no redirects (a
/// 302 to the login page is the expected answer), errors ignored. Another server's guide is never told anything.
nonisolated enum GFGuideReporter {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config, delegate: GFNoRedirects(), delegateQueue: nil)
    }()

    private static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

    static func send(_ timing: GFGuideTiming, guideURL: String) {
        guard let guide = URLComponents(string: guideURL), let host = guide.host, host.hasPrefix("dispatcharr.")
        else { return }
        var report = URLComponents()
        report.scheme = guide.scheme ?? "https"
        report.host = host
        report.port = guide.port
        report.path = "/gf-guide"
        report.percentEncodedQuery = timing.query(device: device, build: build)
        guard let url = report.url else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpShouldHandleCookies = false
        session.dataTask(with: request).resume()
    }

    /// The kind of device, told once on the main actor at launch (GuideScheduler.appLaunched): UIDevice is the main
    /// actor's, and the report goes from the refresh's own thread.
    nonisolated(unsafe) static var device = "iphone"

    @MainActor static func noteDevice() {
        #if os(tvOS)
            device = "atv"
        #elseif canImport(UIKit)
            device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #else
            device = "mac"
        #endif
    }
}
