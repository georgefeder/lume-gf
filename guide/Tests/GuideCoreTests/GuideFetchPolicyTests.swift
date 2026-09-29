import Foundation
@testable import GuideCore
import Testing

struct GuideFetchPolicyTests {
    @Test func `both validators are sent`() {
        #expect(GuideFetchPolicy.requestHeaders(etag: "\"6abaf423-206b11\"", lastModified: "Mon, 28 Sep 2026 23:11:31 GMT")
            == ["If-None-Match": "\"6abaf423-206b11\"", "If-Modified-Since": "Mon, 28 Sep 2026 23:11:31 GMT"])
    }

    @Test func `no validators, no conditional headers`() {
        #expect(GuideFetchPolicy.requestHeaders(etag: nil, lastModified: "").isEmpty)
    }

    @Test func `304 means unchanged`() {
        #expect(GuideFetchPolicy.interpret(status: 304, etag: "\"a\"", lastModified: nil) == .unchanged)
    }

    @Test func `200 is a new guide with the server's build time`() {
        #expect(GuideFetchPolicy.interpret(status: 200, etag: "\"a\"", lastModified: "Mon, 28 Sep 2026 23:11:31 GMT")
            == .newGuide(etag: "\"a\"", lastModified: "Mon, 28 Sep 2026 23:11:31 GMT",
                         serverBuild: Date(timeIntervalSince1970: 1_790_637_091)))
    }

    @Test func `200 without validators still is a new guide`() {
        #expect(GuideFetchPolicy.interpret(status: 200, etag: nil, lastModified: nil)
            == .newGuide(etag: nil, lastModified: nil, serverBuild: nil))
    }

    @Test func `other statuses are failures`() {
        #expect(GuideFetchPolicy.interpret(status: 500, etag: nil, lastModified: nil) == .failed(status: 500))
        #expect(GuideFetchPolicy.interpret(status: 404, etag: nil, lastModified: nil) == .failed(status: 404))
    }

    @Test func `HTTP dates parse, garbage does not`() {
        #expect(GuideFetchPolicy.httpDate("Mon, 28 Sep 2026 23:11:31 GMT") == Date(timeIntervalSince1970: 1_790_637_091))
        #expect(GuideFetchPolicy.httpDate("yesterday") == nil)
    }
}
