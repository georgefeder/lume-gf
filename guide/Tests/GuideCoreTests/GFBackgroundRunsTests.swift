import Foundation
@testable import GuideCore
import Testing

struct GFBackgroundRunsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private func at(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func clock(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour!, parts.minute!)
    }

    private func fresh() -> UserDefaults {
        let name = "GFBackgroundRunsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func `today's wakes are listed oldest first, one the system cut short marked`() {
        let defaults = fresh()
        GFBackgroundRuns.begin(at: at(day: 12, 3, 10), defaults: defaults)
        GFBackgroundRuns.finish(true, defaults: defaults)
        GFBackgroundRuns.begin(at: at(day: 12, 6, 12), defaults: defaults)
        GFBackgroundRuns.begin(at: at(day: 12, 9, 15), defaults: defaults)
        GFBackgroundRuns.finish(true, defaults: defaults)
        let line = GFBackgroundRuns.line(GFBackgroundRuns.load(defaults), now: at(day: 12, 11, 15), calendar: calendar,
                                         time: clock, when: clock)
        #expect(line == "Refreshed while closed today: 03:10, 06:12 (cut short), 09:15")
    }

    @Test func `a wake the server's push asked for is marked, cut short or not`() {
        let defaults = fresh()
        GFBackgroundRuns.begin(at: at(day: 12, 7, 16), defaults: defaults)
        GFBackgroundRuns.finish(true, defaults: defaults)
        GFBackgroundRuns.begin(at: at(day: 12, 8, 14), push: true, defaults: defaults)
        GFBackgroundRuns.finish(true, defaults: defaults)
        GFBackgroundRuns.begin(at: at(day: 12, 9, 14), push: true, defaults: defaults)
        let line = GFBackgroundRuns.line(GFBackgroundRuns.load(defaults), now: at(day: 12, 10), calendar: calendar,
                                         time: clock, when: clock)
        #expect(line == "Refreshed while closed today: 07:16, 08:14 (push), 09:14 (push, cut short)")
    }

    @Test func `no wake today names the last one, none at all says so`() {
        let defaults = fresh()
        let none = GFBackgroundRuns.line([], now: at(day: 12, 11), calendar: calendar, time: clock, when: clock)
        #expect(none == "Not refreshed while closed yet")
        GFBackgroundRuns.begin(at: at(day: 11, 23, 40), defaults: defaults)
        GFBackgroundRuns.finish(true, defaults: defaults)
        let line = GFBackgroundRuns.line(GFBackgroundRuns.load(defaults), now: at(day: 12, 11), calendar: calendar,
                                         time: clock, when: { "yesterday \(clock($0))" })
        #expect(line == "Last refreshed while closed: yesterday 23:40")
    }

    @Test func `wakes older than two days are dropped`() {
        let defaults = fresh()
        GFBackgroundRuns.begin(at: at(day: 9, 10), defaults: defaults)
        GFBackgroundRuns.begin(at: at(day: 12, 10), defaults: defaults)
        #expect(GFBackgroundRuns.load(defaults).map(\.at) == [at(day: 12, 10)])
    }
}
