import Foundation
@testable import LookCore
import Testing

/// events.py writes event times in Riga time: "20:30" for today there, "Sun 17:55" for another day.
struct GFChannelLabelTimeTests {
    let london = TimeZone(identifier: "Europe/London")!
    let gb = Locale(identifier: "en_GB")

    func utc(_ text: String) -> Date {
        try! Date(text, strategy: .iso8601)
    }

    @Test func `today's time is its nearest occurrence`() {
        // Tue 29 Sep, 20:00 in Riga
        #expect(GFChannelLabelTime.resolve("20:30", now: utc("2026-09-29T17:00:00Z")) == utc("2026-09-29T17:30:00Z"))
    }

    @Test func `a time that just passed stays today`() {
        #expect(GFChannelLabelTime.resolve("20:30", now: utc("2026-09-29T18:00:00Z")) == utc("2026-09-29T17:30:00Z"))
    }

    @Test func `just after midnight a late-evening time is yesterday's`() {
        // Wed 30 Sep, 00:30 in Riga
        #expect(GFChannelLabelTime.resolve("23:50", now: utc("2026-09-29T21:30:00Z")) == utc("2026-09-29T20:50:00Z"))
    }

    @Test func `a weekday is the next such day`() {
        // Sat 26 Sep, 12:00 in Riga
        #expect(GFChannelLabelTime.resolve("Sun 17:55", now: utc("2026-09-26T09:00:00Z")) == utc("2026-09-27T14:55:00Z"))
    }

    @Test func `yesterday's weekday counts for 12 hours`() {
        // Mon 28 Sep, 03:00 in Riga: Sunday 17:55 was 9 hours ago
        #expect(GFChannelLabelTime.resolve("Sun 17:55", now: utc("2026-09-28T00:00:00Z")) == utc("2026-09-27T14:55:00Z"))
    }

    @Test func `after 12 hours the weekday means next week`() {
        #expect(GFChannelLabelTime.resolve("Sun 17:55", now: utc("2026-09-28T12:00:00Z")) == utc("2026-10-04T14:55:00Z"))
    }

    @Test func `today's weekday long gone means next week`() {
        // Sun 27 Sep, 20:00 in Riga; "Sun 05:00" was 15 hours ago
        #expect(GFChannelLabelTime.resolve("Sun 05:00", now: utc("2026-09-27T17:00:00Z")) == utc("2026-10-04T02:00:00Z"))
    }

    @Test(arguments: ["TBA", "25:00", "20:61", "Sunday 17:55", "Sun 1755", "17.55", "", "Sun  17:55"])
    func `unreadable times resolve to nothing`(text: String) {
        #expect(GFChannelLabelTime.resolve(text, now: utc("2026-09-26T09:00:00Z")) == nil)
    }

    @Test func `today shows just the time, in the device's zone`() {
        let text = GFChannelLabelTime.badgeText(start: utc("2026-09-27T14:55:00Z"), now: utc("2026-09-27T09:00:00Z"),
                                                zone: london, locale: gb)
        #expect(text == "15:55")
    }

    @Test func `another day shows the weekday`() {
        let text = GFChannelLabelTime.badgeText(start: utc("2026-09-27T14:55:00Z"), now: utc("2026-09-26T09:00:00Z"),
                                                zone: london, locale: gb)
        #expect(text == "Sun 15:55")
    }

    @Test func `a Riga time just after midnight is tonight in the UK`() {
        // Sat 26 Sep, 20:00 in London; "Sun 00:30" in Riga is 22:30 in London the same evening
        let now = utc("2026-09-26T19:00:00Z")
        let start = GFChannelLabelTime.resolve("Sun 00:30", now: now)
        #expect(start == utc("2026-09-26T21:30:00Z"))
        #expect(start.map { GFChannelLabelTime.badgeText(start: $0, now: now, zone: london, locale: gb) } == "22:30")
    }

    @Test func `Riga is two hours ahead of the UK in summer and in winter`() {
        let summerNow = utc("2026-09-26T09:00:00Z"), winterNow = utc("2026-10-31T09:00:00Z")
        let summer = GFChannelLabelTime.resolve("Sun 17:55", now: summerNow)
        let winter = GFChannelLabelTime.resolve("Sun 17:55", now: winterNow)
        #expect(summer.map { GFChannelLabelTime.badgeText(start: $0, now: summerNow, zone: london, locale: gb) } == "Sun 15:55")
        #expect(winter == utc("2026-11-01T15:55:00Z"))
        #expect(winter.map { GFChannelLabelTime.badgeText(start: $0, now: winterNow, zone: london, locale: gb) } == "Sun 15:55")
    }

    @Test func `the night the clocks go forward still resolves`() {
        // Riga skips 03:00-04:00 on Sun 28 Mar 2027; "Sun 03:30" lands within the hour of 01:30 UTC
        let start = GFChannelLabelTime.resolve("Sun 03:30", now: utc("2027-03-27T20:00:00Z"))
        #expect(start.map { abs($0.timeIntervalSince(utc("2027-03-28T01:30:00Z"))) <= 3600 } == true)
    }

    @Test func `12-hour locales keep their style`() {
        let text = GFChannelLabelTime.badgeText(start: utc("2026-09-27T14:55:00Z"), now: utc("2026-09-27T09:00:00Z"),
                                                zone: london, locale: Locale(identifier: "en_US"))
        #expect(text.contains("3:55") && !text.contains("15:55"))
    }
}
