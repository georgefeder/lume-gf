import Foundation
@testable import GuideCore
import Testing

struct GuideClockTests {
    /// 29 Sep 2026 00:11:49 UTC, the server's build that night.
    let build = Date(timeIntervalSince1970: 1_790_640_709)
    let hour: TimeInterval = 3600, minute: TimeInterval = 60

    func next(check: Date?, attempt: Date? = nil, build: Date?, follow: Bool = true,
              interval: TimeInterval = 86400) -> Date {
        GuideClock.nextCheck(lastCheck: check, lastAttempt: attempt ?? check, serverBuild: build,
                             followServer: follow, interval: interval)
    }

    @Test func `never checked is due at once`() {
        #expect(next(check: nil, build: nil) == .distantPast)
    }

    @Test func `next check follows the server's build plus the margin`() {
        let check = build.addingTimeInterval(2 * minute)
        #expect(next(check: check, build: build) == build.addingTimeInterval(hour + 3 * minute))
    }

    @Test func `a late server is asked again every 15 minutes`() {
        let check = build.addingTimeInterval(hour + 4 * minute) // after the expected time, answer: unchanged
        #expect(next(check: check, build: build) == check.addingTimeInterval(15 * minute))
    }

    @Test func `a failed try waits 15 minutes, not a minute`() {
        let check = build.addingTimeInterval(2 * minute)
        let failed = build.addingTimeInterval(hour + 5 * minute)
        #expect(next(check: check, attempt: failed, build: build) == failed.addingTimeInterval(15 * minute))
    }

    @Test func `a failure before any good check is retried after 15 minutes`() {
        let failed = build
        #expect(next(check: nil, attempt: failed, build: nil) == failed.addingTimeInterval(15 * minute))
    }

    @Test func `without a build time the app checks an hour after the last check`() {
        let check = build
        #expect(next(check: check, build: nil) == check.addingTimeInterval(hour))
    }

    @Test func `a device clock hours behind never waits more than 63 minutes`() {
        let check = build.addingTimeInterval(-2 * hour) // the device thinks it is 22:11
        #expect(next(check: check, build: build) == check.addingTimeInterval(hour + 3 * minute))
    }

    @Test func `a device clock hours ahead asks at most every 15 minutes`() {
        let check = build.addingTimeInterval(2 * hour)
        #expect(next(check: check, build: build) == check.addingTimeInterval(15 * minute))
    }

    @Test func `with the switch off Lume's interval applies`() {
        let check = build
        #expect(next(check: check, build: build, follow: false, interval: 6 * hour) == check.addingTimeInterval(6 * hour))
    }

    @Test func `with the switch off a failure is retried after 15 minutes`() {
        let failed = build
        #expect(next(check: nil, attempt: failed, build: nil, follow: false) == failed.addingTimeInterval(15 * minute))
    }

    @Test func `a background request is never pushed out of reach`() {
        let now = build
        #expect(GuideClock.backgroundBeginDate(next: .distantFuture, now: now) == now.addingTimeInterval(hour + 3 * minute))
        #expect(GuideClock.backgroundBeginDate(next: .distantPast, now: now) == now.addingTimeInterval(minute))
        #expect(GuideClock.backgroundBeginDate(next: now.addingTimeInterval(30 * minute), now: now)
            == now.addingTimeInterval(30 * minute))
    }

    @Test func `several sources: the earliest one decides, none means never`() {
        var a = GuideSourceState(), b = GuideSourceState()
        a.recordImported(etag: nil, lastModified: nil, serverBuild: build, channelIDs: [], at: build.addingTimeInterval(minute))
        b.recordUnchanged(at: build.addingTimeInterval(-3 * hour))
        #expect(GuideClock.nextCheck(states: [a, b], followServer: true, interval: 86400)
            == build.addingTimeInterval(-2 * hour))
        #expect(GuideClock.nextCheck(states: [], followServer: true, interval: 86400) == .distantFuture)
    }

    // MARK: - status line

    func time(_ date: Date) -> String {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    @Test func `status line when never updated`() {
        #expect(GuideStatusSummary.line(for: [GuideSourceState()], time: time) == "Guide not updated yet")
    }

    @Test func `status line says when no guide source is switched on`() {
        // Georgs on build 16: the Apple TV's guide never loaded; a device without a source said "not updated yet"
        #expect(GuideStatusSummary.line(for: [], time: time) == "No guide source switched on")
    }

    @Test func `status line says why a guide that never loaded failed`() {
        // the first download failing said only "Guide not updated yet"
        var older = GuideSourceState(), newer = GuideSourceState()
        older.recordFailure("HTTP 500", at: build.addingTimeInterval(4 * minute))
        newer.recordFailure("HTTP 404", at: build.addingTimeInterval(9 * minute))
        #expect(GuideStatusSummary.line(for: [older, newer], time: time)
            == "Guide not updated yet · last check failed 00:20 (HTTP 404)")
    }

    @Test func `status line shows the update and the server's build time`() {
        var s = GuideSourceState()
        s.recordImported(etag: nil, lastModified: nil, serverBuild: build,
                         channelIDs: [], at: build.addingTimeInterval(90))
        #expect(GuideStatusSummary.line(for: [s], time: time) == "Guide updated 00:13 · server built 00:11")
    }

    @Test func `status line shows a later unchanged check`() {
        var s = GuideSourceState()
        s.recordImported(etag: nil, lastModified: nil, serverBuild: build, channelIDs: [], at: build.addingTimeInterval(90))
        s.recordUnchanged(at: build.addingTimeInterval(30 * minute))
        #expect(GuideStatusSummary.line(for: [s], time: time)
            == "Guide updated 00:13 · server built 00:11 · checked 00:41")
    }

    @Test func `status line picks the source that was updated last`() {
        var updated = GuideSourceState(), skipped = GuideSourceState()
        updated.recordImported(etag: nil, lastModified: nil, serverBuild: build, channelIDs: [], at: build.addingTimeInterval(90))
        skipped.recordUnchanged(at: build.addingTimeInterval(20 * minute)) // a source that never downloads (all channels covered)
        #expect(GuideStatusSummary.line(for: [updated, skipped], time: time) == "Guide updated 00:13 · server built 00:11")
    }

    @Test func `status line shows the last failure`() {
        var s = GuideSourceState()
        s.recordImported(etag: nil, lastModified: nil, serverBuild: build, channelIDs: [], at: build.addingTimeInterval(90))
        s.recordFailure("NSURLErrorDomain -1009", at: build.addingTimeInterval(hour + 4 * minute))
        #expect(GuideStatusSummary.line(for: [s], time: time)
            == "Guide updated 00:13 · last check failed 01:15 (NSURLErrorDomain -1009)")
    }
}
