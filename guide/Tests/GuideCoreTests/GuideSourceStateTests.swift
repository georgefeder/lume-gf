import Foundation
@testable import GuideCore
import Testing

struct GuideSourceStateTests {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "gss-\(UUID().uuidString)/GuideSourceState.json")
    }

    @Test func `a new source knows nothing`() {
        #expect(GuideSourceStateStore(fileURL: tempFile()).state(for: UUID()) == GuideSourceState())
    }

    @Test func `an imported guide becomes the current one`() {
        var s = GuideSourceState()
        s.recordImported(etag: "\"a\"", lastModified: "Mon, 28 Sep 2026 23:11:31 GMT",
                         serverBuild: t0, channelIDs: ["1", "2"], at: t0)
        #expect(s.etag == "\"a\"" && s.serverBuild == t0 && s.channelIDs == ["1", "2"])
        #expect(s.lastCheck == t0 && s.lastAttempt == t0 && s.lastUpdate == t0 && s.lastError == nil)
    }

    @Test func `unchanged only records the check`() {
        var s = GuideSourceState()
        s.recordImported(etag: "\"a\"", lastModified: nil, serverBuild: t0, channelIDs: ["1"], at: t0)
        s.recordFailure("offline", at: t0.addingTimeInterval(60))
        s.recordUnchanged(at: t0.addingTimeInterval(120))
        #expect(s.lastCheck == t0.addingTimeInterval(120) && s.lastAttempt == t0.addingTimeInterval(120))
        #expect(s.lastUpdate == t0 && s.etag == "\"a\"" && s.lastError == nil)
    }

    @Test func `a failure keeps the previous guide's fingerprint`() {
        var s = GuideSourceState()
        s.recordImported(etag: "\"a\"", lastModified: "x", serverBuild: t0, channelIDs: ["1"], at: t0)
        s.recordFailure("guide file incomplete", at: t0.addingTimeInterval(60))
        #expect(s.etag == "\"a\"" && s.lastModified == "x" && s.lastCheck == t0)
        #expect(s.lastAttempt == t0.addingTimeInterval(60) && s.lastError == "guide file incomplete")
    }

    @Test func `the store survives a restart`() {
        let file = tempFile(), id = UUID()
        GuideSourceStateStore(fileURL: file).update(id) {
            $0.recordImported(etag: "\"b\"", lastModified: nil, serverBuild: t0, channelIDs: ["9"], at: t0)
        }
        let again = GuideSourceStateStore(fileURL: file)
        #expect(again.state(for: id).etag == "\"b\"")
        #expect(again.all().count == 1)
    }

    @Test func `a damaged file starts empty`() throws {
        let file = tempFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        #expect(GuideSourceStateStore(fileURL: file).all().isEmpty)
    }

    @Test func `the same file for the same channels is recognised, other channels are not`() {
        var s = GuideSourceState()
        s.recordImported(etag: nil, lastModified: nil, serverBuild: nil, channelIDs: ["1"], at: t0, fileHash: "h",
                         channelsKey: 7)
        #expect(s.isSameFile(hash: "h", channelsKey: 7))
        #expect(!s.isSameFile(hash: "h", channelsKey: 8))
        #expect(!s.isSameFile(hash: "other", channelsKey: 7))
        #expect(!s.isSameFile(hash: nil, channelsKey: 7))
        #expect(s.mayAskUnchanged(channelsKey: 7) && !s.mayAskUnchanged(channelsKey: 8))
    }

    @Test func `the same file again counts as a good check and keeps the new validators`() {
        var s = GuideSourceState()
        s.recordFailure("x", at: t0)
        s.recordSameFile(etag: "\"e\"", lastModified: nil, serverBuild: nil, at: t0.addingTimeInterval(60))
        #expect(s.lastCheck == t0.addingTimeInterval(60) && s.lastError == nil && s.etag == "\"e\"")
        #expect(s.lastUpdate == nil)
    }

    @Test func `forgetting the files makes every source download and import in full`() {
        let store = GuideSourceStateStore(fileURL: tempFile()), id = UUID()
        store.update(id) {
            $0.recordImported(etag: "\"a\"", lastModified: "x", serverBuild: nil, channelIDs: ["1"], at: t0,
                              fileHash: "h", channelsKey: 7)
        }
        store.forgetFiles()
        let s = store.state(for: id)
        #expect(s.fileHash == nil && s.channelsKey == nil && s.etag == nil && s.lastModified == nil)
        #expect(s.channelIDs == ["1"])
    }
}
