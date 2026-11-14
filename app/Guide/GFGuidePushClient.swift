#if os(iOS)
    import OSLog
    import UIKit

    /// The iPhone's side of the guide server's silent push (GFGuidePush): asks iOS for a push token at launch, tells
    /// the server the token once a day or when it changes, and checks the guide when a push arrives. The report is one
    /// GET like the channel-change report (GFZapReporter): device kind, build and token, never an address or login;
    /// a 302 to the server's login page is the expected answer. Hooks in LumeAppDelegate (patch 0039).
    enum GFGuidePushClient {
        private static var token: String?
        private static var reporting = false

        private static let session: URLSession = {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.urlCache = nil
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 10
            return URLSession(configuration: config, delegate: GFNoRedirects(), delegateQueue: nil)
        }()

        static func start() {
            UIApplication.shared.registerForRemoteNotifications()
        }

        static func registered(_ deviceToken: Data) {
            token = GFGuidePush.hex(deviceToken)
            reportIfNeeded()
        }

        static func failed(_ error: Error) {
            Logger.database.info("Guide push not available: \(error.localizedDescription, privacy: .public)")
        }

        /// Tells the server the token when it is new, the build is new, or a day has passed. Before the guide sources
        /// are loaded there is nowhere to tell it: the next finished guide refresh tries again.
        static func reportIfNeeded() {
            guard let token, !reporting else { return }
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
            let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
            guard GFGuidePush.shouldReport(token: token, build: build, last: GFGuidePush.loadReported(), now: Date()),
                  let url = GFGuidePush.reportURL(guideURLs: GuideScheduler.shared.enabledSourceURLs(), device: device,
                                                  build: build, token: token)
            else { return }
            reporting = true
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            request.httpShouldHandleCookies = false
            session.dataTask(with: request) { _, response, _ in
                // any answer means the server's log has it; no answer, try again next time
                let answered = response != nil
                Task { @MainActor in
                    reporting = false
                    if answered { GFGuidePush.saveReported(.init(token: token, build: build, at: Date())) }
                }
            }.resume()
        }

        /// A push arrived. Not ours: false, and the caller answers iOS itself.
        static func received(_ userInfo: [AnyHashable: Any],
                             completion: @escaping (UIBackgroundFetchResult) -> Void) -> Bool {
            guard GFGuidePush.isGuidePush(userInfo) else { return false }
            Task { @MainActor in
                let finished = await GuideScheduler.shared.runPush()
                completion(finished ? .newData : .noData)
            }
            return true
        }
    }
#endif
