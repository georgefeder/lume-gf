import Foundation

/// The conditional-request rules for a guide download: which headers to send, and what the answer means.
nonisolated enum GuideFetchPolicy {
    enum Answer: Equatable {
        case unchanged
        case newGuide(etag: String?, lastModified: String?, serverBuild: Date?)
        case failed(status: Int)
    }

    static func requestHeaders(etag: String?, lastModified: String?) -> [String: String] {
        var headers: [String: String] = [:]
        if let etag, !etag.isEmpty { headers["If-None-Match"] = etag }
        if let lastModified, !lastModified.isEmpty { headers["If-Modified-Since"] = lastModified }
        return headers
    }

    static func interpret(status: Int, etag: String?, lastModified: String?) -> Answer {
        switch status {
        case 304: .unchanged
        case 200 ... 299: .newGuide(etag: etag, lastModified: lastModified, serverBuild: lastModified.flatMap(httpDate))
        default: .failed(status: status)
        }
    }

    /// Parses an HTTP date such as "Mon, 28 Sep 2026 23:11:31 GMT".
    static func httpDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: text)
    }
}
