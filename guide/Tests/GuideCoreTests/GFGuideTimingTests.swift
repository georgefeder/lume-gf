import Foundation
@testable import GuideCore
import Testing

struct GFGuideTimingTests {
    @Test func `a finished change import reports its steps, nothing it did not do`() {
        var timing = GFGuideTiming(kind: "wake")
        timing.path = "delta"
        timing.download = 210
        timing.apply = 4800
        timing.inserted = 9954
        timing.updated = 120
        timing.deleted = 29
        timing.finished = true
        #expect(timing.query(device: "iphone", build: "116")
            == "d=iphone&b=116&k=wake&p=delta&ok=1&dl=210&ap=4800&i=9954&u=120&x=29")
    }

    @Test func `a stopped whole import says why, odd characters dropped`() {
        var timing = GFGuideTiming(kind: "app")
        timing.path = "whole"
        timing.readStored = 31000
        timing.storedRows = 121_000
        timing.why = "stopped&x=1"
        #expect(timing.query(device: "iphone", build: "116")
            == "d=iphone&b=116&k=app&p=whole&ok=0&rd=31000&n=121000&why=stoppedx1")
    }

    @Test func `milliseconds are never negative`() {
        let now = Date()
        #expect(GFGuideTiming.ms(since: now.addingTimeInterval(1.5), now: now) == 0)
        #expect(GFGuideTiming.ms(since: now.addingTimeInterval(-1.5), now: now) == 1500)
    }
}
