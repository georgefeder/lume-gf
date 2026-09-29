import Foundation
@testable import GuideCore
import Testing

struct GuideDiffPlannerTests {
    let now = Date(timeIntervalSince1970: 1_790_640_000) // an hour boundary
    let hour: TimeInterval = 3600

    func at(_ h: Double) -> Date { now.addingTimeInterval(h * hour) }
    func item(_ ch: String, _ h: Double, fp: UInt64 = 1) -> GuideDiffPlanner.Incoming {
        .init(id: GuideDiffPlanner.id(channelId: ch, start: at(h)), channelId: ch, start: at(h), end: at(h + 1),
              fingerprint: fp)
    }
    func stored(_ items: [GuideDiffPlanner.Incoming]) -> [String: GuideDiffPlanner.Stored] {
        Dictionary(uniqueKeysWithValues: items.map {
            ($0.id, .init(channelId: $0.channelId, start: $0.start, end: $0.end, fingerprint: $0.fingerprint))
        })
    }

    @Test func `id is Lume's channel-and-start key`() {
        #expect(GuideDiffPlanner.id(channelId: "12", start: now) == "12-1790640000")
    }

    @Test func `first import inserts everything`() {
        var p = GuideDiffPlanner(stored: [:], claimableChannels: ["a"], now: now)
        #expect(p.plan([item("a", 0), item("a", 1)]).inserts.count == 2)
        #expect(p.deletions(fileCompleted: true).isEmpty)
    }

    @Test func `identical file changes nothing`() {
        let file = [item("a", 0), item("a", 1)]
        var p = GuideDiffPlanner(stored: stored(file), claimableChannels: ["a"], now: now)
        #expect(p.plan(file) == .init())
        #expect(p.deletions(fileCompleted: true).isEmpty)
    }

    @Test func `a changed programme is updated`() {
        var p = GuideDiffPlanner(stored: stored([item("a", 0)]), claimableChannels: ["a"], now: now)
        #expect(p.plan([item("a", 0, fp: 2)]).updates == [item("a", 0).id])
    }

    @Test func `a programme gone inside the covered span is deleted`() {
        var p = GuideDiffPlanner(stored: stored([item("a", 0), item("a", 1), item("a", 2)]),
                                 claimableChannels: ["a"], now: now)
        _ = p.plan([item("a", 0), item("a", 2)])
        #expect(p.deletions(fileCompleted: true) == [item("a", 1).id])
    }

    @Test func `earlier programmes before the file's first one stay`() {
        var p = GuideDiffPlanner(stored: stored([item("a", -3), item("a", 0)]), claimableChannels: ["a"], now: now)
        _ = p.plan([item("a", 0), item("a", 1)]) // the server dropped the past hours
        #expect(p.deletions(fileCompleted: true).isEmpty)
    }

    @Test func `the hourly shift inserts the new hour and keeps history`() {
        let before = (-2 ... 2).map { item("a", Double($0)) }
        let after = (-1 ... 3).map { item("a", Double($0)) }
        var p = GuideDiffPlanner(stored: stored(before), claimableChannels: ["a"], now: now)
        #expect(p.plan(after).inserts == [item("a", 3).id])
        #expect(p.deletions(fileCompleted: true).isEmpty)
    }

    @Test func `channels missing from the file keep their programmes`() {
        var p = GuideDiffPlanner(stored: stored([item("a", 0), item("b", 0)]), claimableChannels: ["a", "b"], now: now)
        _ = p.plan([item("a", 0)])
        #expect(p.deletions(fileCompleted: true).isEmpty)
        #expect(p.claimedChannels == ["a"])
    }

    @Test func `a cut-off file deletes nothing`() {
        var p = GuideDiffPlanner(stored: stored([item("a", 0), item("a", 1)]), claimableChannels: ["a"], now: now)
        _ = p.plan([item("a", 0)])
        #expect(p.deletions(fileCompleted: false).isEmpty)
    }

    @Test func `programmes older than 12 hours are dropped and not inserted`() {
        var p = GuideDiffPlanner(stored: stored([item("a", -14)]), claimableChannels: ["a"], now: now)
        #expect(p.plan([item("a", -13.5), item("a", 0)]).inserts == [item("a", 0).id])
        #expect(p.deletions(fileCompleted: true) == [item("a", -14).id])
    }

    @Test func `channels this source may not claim are ignored`() {
        var p = GuideDiffPlanner(stored: [:], claimableChannels: ["a"], now: now)
        #expect(p.plan([item("z", 0)]) == .init())
        #expect(p.claimedChannels.isEmpty)
    }

    @Test func `a duplicate in the file: the first one wins`() {
        var p = GuideDiffPlanner(stored: [:], claimableChannels: ["a"], now: now)
        #expect(p.plan([item("a", 0, fp: 1), item("a", 0, fp: 2)]).inserts == [item("a", 0).id])
    }
}
