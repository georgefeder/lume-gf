import Foundation
@testable import Lume
import SwiftData
import Testing

struct GuideRefresherTests {
    let now = Date(timeIntervalSince1970: 1_790_640_000)
    let built = "Mon, 28 Sep 2026 23:11:31 GMT"

    func setUp() throws -> (ModelContainer, GuideSourceStateStore, GuideRefresher) {
        let container = try makeTestContainer()
        let states = GuideSourceStateStore(fileURL: FileManager.default.temporaryDirectory
            .appending(path: "grt-\(UUID().uuidString)/state.json"))
        let refresher = GuideRefresher(container: container, fetcher: GuideFetcher(session: GuideStubProtocol.session()),
                                       states: states, now: { self.now })
        return (container, states, refresher)
    }

    func guide(_ count: Int) throws -> Data {
        try Data(contentsOf: writeGuideFile(hourly("c1", from: now, count: count)))
    }

    func count(_ container: ModelContainer) throws -> Int {
        try ModelContext(container).fetchCount(FetchDescriptor<EPGListing>())
    }

    @Test func `first download imports the guide and remembers the server's answer`() async throws {
        let (container, states, refresher) = try setUp()
        let (url, path) = guideTestURL(), id = UUID()
        GuideStubProtocol.answer(path, .init(status: 200, headers: ["ETag": "\"a\"", "Last-Modified": built],
                                             body: try guide(3)))
        let outcome = try await refresher.refresh(sourceID: id, url: url, knownChannelIDs: ["c1"], force: false)
        #expect(outcome.claimedChannelIDs == ["c1"])
        #expect(try count(container) == 3)
        let s = states.state(for: id)
        #expect(s.etag == "\"a\"" && s.serverBuild == Date(timeIntervalSince1970: 1_790_637_091))
        #expect(s.lastUpdate == now && s.channelIDs == ["c1"])
    }

    @Test func `an unchanged answer keeps the guide and records the check`() async throws {
        let (container, states, refresher) = try setUp()
        let (url, path) = guideTestURL(), id = UUID()
        GuideStubProtocol.answer(path, .init(status: 200, headers: ["ETag": "\"a\""], body: try guide(2)))
        _ = try await refresher.refresh(sourceID: id, url: url, knownChannelIDs: ["c1"], force: false)
        GuideStubProtocol.answer(path, .init(status: 304))
        let outcome = try await refresher.refresh(sourceID: id, url: url, knownChannelIDs: ["c1"], force: false)
        #expect(outcome.claimedChannelIDs == ["c1"] && outcome.summary == "unchanged")
        #expect(GuideStubProtocol.lastRequest(path)?.value(forHTTPHeaderField: "If-None-Match") == "\"a\"")
        #expect(try count(container) == 2)
        #expect(states.state(for: id).lastCheck == now)
    }

    @Test func `sync now asks without the stored fingerprint`() async throws {
        let (_, _, refresher) = try setUp()
        let (url, path) = guideTestURL(), id = UUID()
        GuideStubProtocol.answer(path, .init(status: 200, headers: ["ETag": "\"a\""], body: try guide(1)))
        _ = try await refresher.refresh(sourceID: id, url: url, knownChannelIDs: ["c1"], force: false)
        _ = try await refresher.refresh(sourceID: id, url: url, knownChannelIDs: ["c1"], force: true)
        #expect(GuideStubProtocol.lastRequest(path)?.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func `an empty stored guide ignores the remembered fingerprint`() async throws {
        let (container, states, refresher) = try setUp()
        let (url, path) = guideTestURL(), id = UUID()
        states.update(id) { $0.recordImported(etag: "\"a\"", lastModified: built, serverBuild: nil, channelIDs: ["c1"],
                                              at: now) }
        GuideStubProtocol.answer(path, .init(status: 200, headers: ["ETag": "\"a\""], body: try guide(2)))
        _ = try await refresher.refresh(sourceID: id, url: url, knownChannelIDs: ["c1"], force: false)
        #expect(GuideStubProtocol.lastRequest(path)?.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(try count(container) == 2)
    }

    @Test func `a failed download keeps the guide and records why`() async throws {
        let (container, states, refresher) = try setUp()
        let (url, path) = guideTestURL(), id = UUID()
        GuideStubProtocol.answer(path, .init(status: 200, headers: ["ETag": "\"a\""], body: try guide(2)))
        _ = try await refresher.refresh(sourceID: id, url: url, knownChannelIDs: ["c1"], force: false)
        GuideStubProtocol.answer(path, .init(status: 503))
        await #expect(throws: M3UError.self) {
            _ = try await refresher.refresh(sourceID: id, url: url, knownChannelIDs: ["c1"], force: false)
        }
        #expect(try count(container) == 2)
        #expect(states.state(for: id).lastError != nil && states.state(for: id).etag == "\"a\"")
    }

    @Test func `a cut-off file keeps the old fingerprint so the next check downloads again`() async throws {
        let (container, states, refresher) = try setUp()
        let (url, path) = guideTestURL(), id = UUID()
        GuideStubProtocol.answer(path, .init(status: 200, headers: ["ETag": "\"a\""], body: try guide(2)))
        _ = try await refresher.refresh(sourceID: id, url: url, knownChannelIDs: ["c1"], force: false)
        let cut = try Data(contentsOf: writeGuideFile(hourly("c1", from: now, count: 4), cut: true))
        GuideStubProtocol.answer(path, .init(status: 200, headers: ["ETag": "\"b\""], body: cut))
        await #expect(throws: GuideRefresher.Failure.incompleteFile) {
            _ = try await refresher.refresh(sourceID: id, url: url, knownChannelIDs: ["c1"], force: false)
        }
        #expect(states.state(for: id).etag == "\"a\"")
        #expect(try count(container) >= 2)
    }

    @Test func `the same file again for the same channels is not imported again`() async throws {
        let (container, states, refresher) = try setUp()
        let (url, path) = guideTestURL(), id = UUID()
        // a server that sends no ETag or Last-Modified: the whole guide every time
        GuideStubProtocol.answer(path, .init(status: 200, body: try guide(3)))
        _ = try await refresher.refresh(sourceID: id, url: url, knownChannelIDs: ["c1"], force: false)
        let context = ModelContext(container)
        try context.delete(model: EPGListing.self, where: #Predicate { $0.title == "Show 0" })
        try context.save()
        let outcome = try await refresher.refresh(sourceID: id, url: url, knownChannelIDs: ["c1"], force: false)
        #expect(outcome.summary == "same file" && outcome.claimedChannelIDs == ["c1"])
        #expect(try count(container) == 2) // not imported again
        #expect(states.state(for: id).lastCheck == now && states.state(for: id).lastError == nil)
    }

    @Test func `new channels download the guide in full and import it`() async throws {
        let (container, _, refresher) = try setUp()
        let (url, path) = guideTestURL(), id = UUID()
        GuideStubProtocol.answer(path, .init(status: 200, headers: ["ETag": "\"a\""], body: try guide(2)))
        _ = try await refresher.refresh(sourceID: id, url: url, knownChannelIDs: ["c1"], force: false)
        let both = try Data(contentsOf: writeGuideFile(hourly("c1", from: now, count: 2) + hourly("c2", from: now,
                                                                                               count: 2)))
        GuideStubProtocol.answer(path, .init(status: 200, headers: ["ETag": "\"a\""], body: both))
        let outcome = try await refresher.refresh(sourceID: id, url: url, knownChannelIDs: ["c1", "c2"], force: false)
        #expect(GuideStubProtocol.lastRequest(path)?.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(outcome.claimedChannelIDs == ["c1", "c2"])
        #expect(try count(container) == 4)
    }
}
