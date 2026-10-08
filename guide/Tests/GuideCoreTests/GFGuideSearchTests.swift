import Foundation
@testable import GuideCore
import Testing

struct GFGuideSearchTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private let locale = Locale(identifier: "en_GB")

    /// Thu 8 Oct 2026 21:57 in London
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 21, minute: 57))!
    }

    private func at(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func hit(_ id: String, channel: String = "bbc2", start: Date, minutes: Double = 60) -> GFGuideSearchHit {
        GFGuideSearchHit(listingID: id, channelId: channel, title: "Shark Tank", subtitle: nil, detail: "",
                         start: start, end: start.addingTimeInterval(minutes * 60))
    }

    @Test func `what is on now comes first, then the rest by start time`() {
        let later = hit("later", start: at(day: 9, 20))
        let soon = hit("soon", start: at(day: 8, 22, 30))
        let live = hit("live", channel: "cnbc", start: at(day: 8, 21, 30))
        let hits = GFGuideSearch.hits([later, soon, live], channels: ["bbc2", "cnbc"], now: now)
        #expect(hits.map(\.listingID) == ["live", "soon", "later"])
    }

    @Test func `only this playlist's channels, nothing that has ended, each programme once`() {
        let other = hit("other", channel: "not-mine", start: at(day: 9, 20))
        let ended = hit("ended", start: at(day: 8, 20), minutes: 30)
        let twice = hit("twice", start: at(day: 9, 21))
        let hits = GFGuideSearch.hits([other, ended, twice, twice], channels: ["bbc2"], now: now)
        #expect(hits.map(\.listingID) == ["twice"])
    }

    @Test func `at most the limit`() {
        let many = (0 ..< 50).map { hit("p\($0)", start: at(day: 9, 6).addingTimeInterval(Double($0) * 3600)) }
        #expect(GFGuideSearch.hits(many, channels: ["bbc2"], now: now).count == GFGuideSearch.limit)
        #expect(GFGuideSearch.hits(many, channels: ["bbc2"], now: now, limit: 3).map(\.listingID) == ["p0", "p1", "p2"])
    }

    @Test func `the time reads as the day it airs`() {
        func when(_ start: Date, minutes: Double = 60) -> String {
            GFGuideSearch.whenLabel(start: start, end: start.addingTimeInterval(minutes * 60), now: now,
                                    calendar: calendar, locale: locale)
        }
        #expect(when(at(day: 8, 21, 30)) == "Live now")
        #expect(when(at(day: 8, 22, 30)) == "Today 22:30")
        #expect(when(at(day: 9, 9, 30)) == "Tomorrow 09:30")
        #expect(when(at(day: 11, 20)) == "Sun 20:00")
        #expect(when(at(day: 18, 20)) == "18 Oct 20:00")
    }
}
