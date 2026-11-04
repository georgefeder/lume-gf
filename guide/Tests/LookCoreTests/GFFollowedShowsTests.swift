import Foundation
@testable import LookCore
import Testing

/// Following shows (Georgs, 4 Nov: Shark Tank on ABC, a heads-up on the day and a reminder an hour before, wherever he
/// is).
struct GFFollowedShowsTests {
    private let london = Self.calendar("Europe/London")
    private let riga = Self.calendar("Europe/Riga")
    private let locale = Locale(identifier: "en_GB")
    private let shark = GFFollowedShow(title: "Shark Tank", channel: "ABC", followedAt: Date(timeIntervalSince1970: 0))

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    /// 2026-11-06 (a Friday) at `hour`:`minute` London time (GMT then), plus `days`.
    private func date(_ hour: Int, _ minute: Int = 0, days: Int = 0) -> Date {
        let components = DateComponents(year: 2026, month: 11, day: 6 + days, hour: hour, minute: minute)
        return london.date(from: components)!
    }

    private func listing(_ title: String, _ channelId: String, start: Date, minutes: Double = 60)
        -> GFFollowedShows.Listing {
        GFFollowedShows.Listing(title: title, channelId: channelId, start: start,
                                end: start.addingTimeInterval(minutes * 60))
    }

    private let channels = [
        GFFollowedShows.Channel(epgId: "abc.us", name: "ABC HD", streamID: "p-live-1"),
        GFFollowedShows.Channel(epgId: "abc4k.us", name: "ABC 4K", streamID: "p-live-2"),
        GFFollowedShows.Channel(epgId: "cnbc.us", name: "CNBC HD", streamID: "p-live-3")
    ]

    @Test func `a show is followed on a channel without its picture quality, and unfollowed again`() {
        let followed = GFFollowedShows.toggled([], title: "Shark Tank", streamName: "ABC 4K", now: .now)
        #expect(followed.map(\.channel) == ["ABC"])
        #expect(GFFollowedShows.isFollowed(followed, title: "Shark Tank", streamName: "ABC HD"))
        #expect(!GFFollowedShows.isFollowed(followed, title: "Shark Tank", streamName: "CNBC HD"))
        #expect(GFFollowedShows.toggled(followed, title: "Shark Tank", streamName: "ABC FHD", now: .now).isEmpty)
        // an event slot is never the same show twice: nothing to follow
        #expect(GFFollowedShows.toggled([], title: "Arsenal v Chelsea",
                                        streamName: "🔴 LIVE 20:00 · Arsenal v Chelsea · Premier League · FHD",
                                        now: .now).isEmpty)
    }

    @Test func `the list goes through its stored form unchanged, and a broken one reads as empty`() {
        let shows = [shark, GFFollowedShow(title: "Panorama", channel: "BBC One", followedAt: Date(timeIntervalSince1970: 9))]
        #expect(GFFollowedShows.decode(GFFollowedShows.encode(shows)) == shows)
        #expect(GFFollowedShows.decode("not json").isEmpty)
        #expect(GFFollowedShows.decode(nil).isEmpty)
    }

    @Test(arguments: [("Shark Tank", true), ("Shark Tank (New)", true), ("Shark Tank S17E03", true),
                      ("SHARK TANK - Season Finale", true), ("Shark Tank Mexico", false), ("Shark Tanks", false),
                      ("Tank", false)])
    func `a guide's own additions to the title still match, another show does not`(title: String, matches: Bool) {
        #expect(GFFollowedShows.titleMatches(GFFollowedShows.titleWords("Shark Tank"),
                                             GFFollowedShows.titleWords(title)) == matches)
    }

    @Test func `the next airings are on the best picture of the followed channel, repeats elsewhere left out`() {
        let now = date(8)
        let listings = [
            listing("Shark Tank", "abc.us", start: date(1, days: 1)),       // Friday night, 01:00
            listing("Shark Tank", "abc4k.us", start: date(1, days: 1)),     // the same airing in 4K
            listing("Shark Tank", "cnbc.us", start: date(14)),              // a repeat elsewhere
            listing("Shark Tank", "abc.us", start: date(6), minutes: 60),   // ended at 07:00
            listing("Shark Tank (New)", "abc.us", start: date(1, days: 8)), // a week later
            listing("World News Tonight", "abc.us", start: date(23))
        ]
        let airings = GFFollowedShows.airings(of: [shark], listings: listings, channels: channels, now: now)
        #expect(airings.map(\.start) == [date(1, days: 1), date(1, days: 8)])
        #expect(airings.map(\.channel.name) == ["ABC 4K", "ABC HD"])
        #expect(GFFollowedShows.airings(of: [], listings: listings, channels: channels, now: now).isEmpty)
    }

    @Test func `the row says when in words, from the TV day that starts at five`() {
        func when(_ start: Date, now: Date) -> String {
            let airing = GFFollowedShows.Airing(show: shark, title: "Shark Tank", start: start,
                                                end: start.addingTimeInterval(3600), channel: channels[0])
            return GFFollowedShows.when(airing, now: now, calendar: london, locale: locale)
        }
        #expect(when(date(7), now: date(7, 30)) == "Live now")
        #expect(when(date(14), now: date(8)) == "Today 14:00")
        #expect(when(date(20), now: date(8)) == "Tonight 20:00")
        #expect(when(date(1, days: 1), now: date(8)) == "Tonight 01:00")
        #expect(when(date(20, days: 1), now: date(8)) == "Tomorrow 20:00")
        #expect(when(date(1, days: 2), now: date(8)) == "Tomorrow night 01:00")
        #expect(when(date(20, days: 4), now: date(8)) == "Tuesday 20:00")
        #expect(when(date(1, days: 5), now: date(8)) == "Tuesday night 01:00")
        #expect(when(date(20, days: 9), now: date(8)) == "15 Nov 20:00")
    }

    @Test func `a heads-up on the day and a reminder an hour before, in the phones own time zone`() {
        let airing = GFFollowedShows.Airing(show: shark, title: "Shark Tank", start: date(1, days: 1),
                                            end: date(2, days: 1), channel: channels[1])
        // Glasgow: the heads-up at ten on Friday, the reminder at midnight
        let here = GFFollowedShows.reminders(for: [airing], now: date(8), calendar: london)
        #expect(here.map(\.kind) == [.headsUp, .hourBefore])
        #expect(here.map(\.fire) == [date(10), date(0, days: 1)])
        #expect(here[0].title == "Shark Tank")
        #expect(here[0].body(calendar: london, locale: locale) == "Tonight at 01:00 on ABC")
        #expect(here[1].body(calendar: london, locale: locale) == "Starts in an hour, at 01:00, on ABC")
        // Riga, two hours ahead: the same programme starts at 03:00 there, its heads-up at ten Riga time
        let away = GFFollowedShows.reminders(for: [airing], now: date(6), calendar: riga)
        #expect(away.map(\.fire) == [date(8), date(0, days: 1)])
        #expect(away[0].body(calendar: riga, locale: locale) == "Tonight at 03:00 on ABC")
    }

    @Test func `nothing already past, no heads-up after its reminder, one heads-up a show a day`() {
        func airing(_ start: Date) -> GFFollowedShows.Airing {
            GFFollowedShows.Airing(show: shark, title: "Shark Tank", start: start, end: start.addingTimeInterval(3600),
                                   channel: channels[0])
        }
        // followed at noon: the heads-up time has gone, the reminder is still to come
        #expect(GFFollowedShows.reminders(for: [airing(date(20))], now: date(12), calendar: london).map(\.kind)
            == [.hourBefore])
        // on at ten past ten in the morning: its reminder comes before ten, so no heads-up after it
        #expect(GFFollowedShows.reminders(for: [airing(date(10, 10))], now: date(6), calendar: london).map(\.kind)
            == [.hourBefore])
        // twice tonight: one heads-up, for the first
        let twice = GFFollowedShows.reminders(for: [airing(date(20)), airing(date(1, days: 1))], now: date(8),
                                              calendar: london)
        #expect(twice.filter { $0.kind == .headsUp }.map(\.airing.start) == [date(20)])
        #expect(twice.filter { $0.kind == .hourBefore }.count == 2)
        // the soonest few only
        let many = (0 ..< 40).map { airing(date(20, days: $0)) }
        #expect(GFFollowedShows.reminders(for: many, now: date(8), calendar: london).count
            == GFFollowedShows.reminderLimit)
    }

    @Test func `the guide is narrowed by the title's longest word as written`() {
        #expect(GFFollowedShows.searchWord("Shark Tank") == "Shark")
        #expect(GFFollowedShows.searchWord("Акули бізнесу") == "бізнесу")
        #expect(GFFollowedShows.searchWord("!!") == nil)
    }
}
