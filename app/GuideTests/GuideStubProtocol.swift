import Foundation

/// Canned HTTP answers with headers for guide-download tests, keyed by URL path; remembers each path's last request.
final nonisolated class GuideStubProtocol: URLProtocol {
    struct Answer {
        var status: Int
        var headers: [String: String] = [:]
        var body = Data()
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var answers: [String: Answer] = [:]
    private nonisolated(unsafe) static var requests: [String: URLRequest] = [:]

    static func answer(_ path: String, _ answer: Answer) {
        lock.withLock { answers[path] = answer }
    }

    static func lastRequest(_ path: String) -> URLRequest? {
        lock.withLock { requests[path] }
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GuideStubProtocol.self]
        return URLSession(configuration: config)
    }

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let answer = Self.lock.withLock { () -> Answer? in
            Self.requests[path] = request
            return Self.answers[path]
        }
        guard let answer, let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1",
                                             headerFields: answer.headers)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

func guideTestURL() -> (url: String, path: String) {
    let path = "/\(UUID().uuidString)/xmltv.php"
    return ("https://guide.example.com\(path)", path)
}
