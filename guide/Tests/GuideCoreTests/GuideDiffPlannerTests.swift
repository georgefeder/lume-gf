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

    @Test func `old programmes the file still carries are stored (catch-up)`() {
        var p = GuideDiffPlanner(stored: [:], claimableChannels: ["a"], now: now)
        #expect(p.plan([item("a", -48), item("a", 0)]).inserts == [item("a", -48).id, item("a", 0).id])
    }

    @Test func `an old programme the file still carries is not deleted`() {
        var p = GuideDiffPlanner(stored: stored([item("a", -14)]), claimableChannels: ["a"], now: now)
        _ = p.plan([item("a", -14), item("a", 0)])
        #expect(p.deletions(fileCompleted: true).isEmpty)
    }

    @Test func `old programmes the file dropped are cleared, and those of channels no playlist has`() {
        var p = GuideDiffPlanner(stored: stored([item("a", -14), item("b", -20)]), claimableChannels: ["a"], now: now,
                                 allChannels: ["a"])
        _ = p.plan([item("a", 0)])
        #expect(p.deletions(fileCompleted: true) == [item("a", -14).id, item("b", -20).id].sorted())
    }

    @Test func `another source's old programmes stay (its catch-up is its own)`() {
        // source 1 may claim b too, but its file does not guide b: source 2's file does
        var p = GuideDiffPlanner(stored: stored([item("a", -14), item("b", -20)]), claimableChannels: ["a", "b"],
                                 now: now, allChannels: ["a", "b"])
        _ = p.plan([item("a", 0)])
        #expect(p.deletions(fileCompleted: true) == [item("a", -14).id])
    }

    @Test func `the stored rows are handed back once`() {
        var p = GuideDiffPlanner(stored: stored([item("a", 0)]), claimableChannels: ["a"], now: now)
        #expect(p.releaseStored().count == 1)
        #expect(p.releaseStored().isEmpty)
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

    @Test func `a stale stored guide takes what is on now first`() {
        let current = stored([item("a", -0.5), item("b", -0.5), item("c", -0.5)])
        let dayOld = stored([item("a", -24), item("b", -24), item("c", -0.5)])
        #expect(!GuideDiffPlanner.wantsNowFirst(stored: current, channels: ["a", "b", "c"], now: now))
        #expect(GuideDiffPlanner.wantsNowFirst(stored: dayOld, channels: ["a", "b", "c"], now: now))
        #expect(GuideDiffPlanner.wantsNowFirst(stored: [:], channels: ["a"], now: now)) // first import
        #expect(!GuideDiffPlanner.wantsNowFirst(stored: [:], channels: [], now: now))
        // half on now is not stale; other channels' programmes don't count
        #expect(!GuideDiffPlanner.wantsNowFirst(stored: stored([item("a", 0)]), channels: ["a", "b"], now: now))
        #expect(GuideDiffPlanner.wantsNowFirst(stored: stored([item("x", 0), item("y", 0)]), channels: ["a", "b"],
                                               now: now))
    }
}
