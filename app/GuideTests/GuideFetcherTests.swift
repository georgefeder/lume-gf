import Foundation
@testable import Lume
import Testing

struct GuideFetcherTests {
    let fetcher = GuideFetcher(session: GuideStubProtocol.session())
    let built = "Mon, 28 Sep 2026 23:11:31 GMT"

    @Test func `the stored fingerprint and date are sent`() async throws {
        let (url, path) = guideTestURL()
        GuideStubProtocol.answer(path, .init(status: 304))
        _ = try await fetcher.fetch(urlString: url, etag: "\"a\"", lastModified: built)
        let sent = GuideStubProtocol.lastRequest(path)
        #expect(sent?.value(forHTTPHeaderField: "If-None-Match") == "\"a\"")
        #expect(sent?.value(forHTTPHeaderField: "If-Modified-Since") == built)
    }

    @Test func `304 means unchanged`() async throws {
        let (url, path) = guideTestURL()
        GuideStubProtocol.answer(path, .init(status: 304))
        let result = try await fetcher.fetch(urlString: url, etag: "\"a\"", lastModified: nil)
        guard case .unchanged = result else {
            Issue.record("expected .unchanged"); return
        }
    }

    @Test func `200 brings the file and the server's answer`() async throws {
        let (url, path) = guideTestURL()
        GuideStubProtocol.answer(path, .init(status: 200, headers: ["ETag": "\"b\"", "Last-Modified": built],
                                             body: Data("<tv></tv>".utf8)))
        let result = try await fetcher.fetch(urlString: url, etag: nil, lastModified: nil)
        guard case let .file(file, etag, lastModified, serverBuild, isTemporary) = result else {
            Issue.record("expected .file"); return
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "<tv></tv>")
        #expect(etag == "\"b\"" && lastModified == built && isTemporary)
        #expect(serverBuild == Date(timeIntervalSince1970: 1_790_637_091))
    }

    @Test func `200 without validators still brings the file`() async throws {
        let (url, path) = guideTestURL()
        GuideStubProtocol.answer(path, .init(status: 200, body: Data("<tv></tv>".utf8)))
        let result = try await fetcher.fetch(urlString: url, etag: "\"old\"", lastModified: nil)
        guard case let .file(_, etag, lastModified, serverBuild, _) = result else {
            Issue.record("expected .file"); return
        }
        #expect(etag == nil && lastModified == nil && serverBuild == nil)
    }

    @Test func `a server error is thrown`() async throws {
        let (url, path) = guideTestURL()
        GuideStubProtocol.answer(path, .init(status: 500))
        await #expect(throws: M3UError.self) {
            _ = try await fetcher.fetch(urlString: url, etag: nil, lastModified: nil)
        }
    }
}
