import Foundation
@testable import LookCore
import Testing

enum GFEventKind: Sendable { case none, live, upcoming }

struct GFEventCase: Sendable, CustomTestStringConvertible {
    let raw: String, title: String, second: String?, quality: String?, kind: GFEventKind
    var testDescription: String { raw }
}

/// Event slots (events.py `pretty()`): "<icon> <when> · <title>[ · <competition>][ · <quality>]". The 29 shapes our
/// server wrote on 29 Sep 2026, each with a made-up title (at 12:00 Riga time on Saturday 26 Sep).
let gfEventCases: [GFEventCase] = {
    typealias Case = GFEventCase
    return [
        Case(raw: "▪ Darts Night", title: "Darts Night", second: nil, quality: nil, kind: .none),
        Case(raw: "⏰ Sun 17:55 · Japanese GP · Formula 1 · 4K", title: "Japanese GP", second: "Formula 1", quality: "4K", kind: .upcoming),
        Case(raw: "⏰ Sun 17:55 · Japanese GP · 4K", title: "Japanese GP", second: nil, quality: "4K", kind: .upcoming),
        Case(raw: "▪ Darts Night · HD", title: "Darts Night", second: nil, quality: "HD", kind: .none),
        Case(raw: "⏰ Wed 02:30 · Kings v Raiders · Hockey · HD · USA", title: "Kings v Raiders", second: "Hockey · USA", quality: "HD", kind: .upcoming),
        Case(raw: "⏰ 20:30 · Rangers v Celtic · FHD", title: "Rangers v Celtic", second: nil, quality: "FHD", kind: .upcoming),
        Case(raw: "▪ Boxing Night · Heavyweights", title: "Boxing Night", second: "Heavyweights", quality: nil, kind: .none),
        Case(raw: "⏰ 20:30 · Rangers v Celtic", title: "Rangers v Celtic", second: nil, quality: nil, kind: .upcoming),
        Case(raw: "⏰ 20:30 · Rangers v Celtic · Premiership · FHD", title: "Rangers v Celtic", second: "Premiership", quality: "FHD", kind: .upcoming),
        Case(raw: "⏰ Sun 17:55 · Japanese GP", title: "Japanese GP", second: nil, quality: nil, kind: .upcoming),
        Case(raw: "🔴 LIVE · Hawks v Eagles · Basketball · USA", title: "Hawks v Eagles", second: "Basketball · USA", quality: nil, kind: .live),
        Case(raw: "🔴 LIVE · Hawks v Eagles · HD", title: "Hawks v Eagles", second: nil, quality: "HD", kind: .live),
        Case(raw: "⏰ Sun 17:55 · Japanese GP · Formula 1 · Qualifying", title: "Japanese GP", second: "Formula 1 · Qualifying", quality: nil, kind: .upcoming),
        Case(raw: "🔴 LIVE · Hawks v Eagles · Basketball", title: "Hawks v Eagles", second: "Basketball", quality: nil, kind: .live),
        Case(raw: "🔴 LIVE · Hawks v Eagles", title: "Hawks v Eagles", second: nil, quality: nil, kind: .live),
        Case(raw: "⏰ Sun 17:55 · Japanese GP · Formula 1", title: "Japanese GP", second: "Formula 1", quality: nil, kind: .upcoming),
        Case(raw: "🔴 LIVE 12:00 · City v United · Premier League · Live", title: "City v United", second: "Premier League", quality: nil, kind: .live),
        Case(raw: "🔴 LIVE 12:00 · City v United · FHD", title: "City v United", second: nil, quality: "FHD", kind: .live),
        Case(raw: "⏰ 20:30 · Rangers v Celtic · Premiership", title: "Rangers v Celtic", second: "Premiership", quality: nil, kind: .upcoming),
        Case(raw: "⏰ 20:30 · College A vs College B _ Field Hockey (A vs B) · Live · HD · USA", title: "College A vs College B _ Field Hockey (A vs B)", second: "USA", quality: "HD", kind: .upcoming),
        Case(raw: "⏰ 20:30 · Rangers v Celtic · Premiership · Scotland", title: "Rangers v Celtic", second: "Premiership · Scotland", quality: nil, kind: .upcoming),
        Case(raw: "🔴 LIVE 12:00 · City v United · Premier League", title: "City v United", second: "Premier League", quality: nil, kind: .live),
        Case(raw: "🔴 LIVE 12:00 · City v United", title: "City v United", second: nil, quality: nil, kind: .live),
        Case(raw: "🔴 LIVE 12:00 · City v United · Soccer · HD · England", title: "City v United", second: "Soccer · England", quality: "HD", kind: .live),
        Case(raw: "🔴 LIVE 12:00 · City v United · Premier League · FHD", title: "City v United", second: "Premier League", quality: "FHD", kind: .live),
        Case(raw: "▪ Boxing Night · Heavyweights · HD", title: "Boxing Night", second: "Heavyweights", quality: "HD", kind: .none),
        Case(raw: "🔴 LIVE Fri 23:00 · Night Race · 4K", title: "Night Race", second: nil, quality: "4K", kind: .live),
        Case(raw: "🔴 LIVE Fri 23:00 · Night Race · Motorsport · Endurance", title: "Night Race", second: "Motorsport · Endurance", quality: nil, kind: .live),
        Case(raw: "⏰ Sun 17:55 · Kings v Raiders · Hockey · FHD", title: "Kings v Raiders", second: "Hockey", quality: "FHD", kind: .upcoming)
    ]
}()

struct GFChannelLabelEventTests {
    /// Saturday 26 Sep 2026, 12:00 in Riga.
    let now = try! Date("2026-09-26T09:00:00Z", strategy: .iso8601)

    func kind(_ status: GFChannelLabel.Status) -> GFEventKind {
        switch status {
        case .none: GFEventKind.none
        case .live: GFEventKind.live
        case .upcoming: GFEventKind.upcoming
        }
    }

    @Test(arguments: gfEventCases)
    func `an event slot reads as title, second line and badges`(c: GFEventCase) {
        let label = GFChannelLabel.parse(c.raw, now: now)
        #expect(label.title == c.title)
        #expect(label.secondLine == c.second)
        #expect(label.quality == c.quality)
        #expect(kind(label.status) == c.kind)
    }

    @Test func `the start time is resolved from Riga time`() {
        let label = GFChannelLabel.parse("⏰ Sun 17:55 · Japanese GP · 4K", now: now)
        #expect(label.status == .upcoming(start: try! Date("2026-09-27T14:55:00Z", strategy: .iso8601)))
    }

    @Test func `the last quality word is the badge and none reaches the second line`() {
        let label = GFChannelLabel.parse("⏰ Sun 17:55 · Kings v Raiders · HD · USA · FHD", now: now)
        #expect(label.quality == "FHD")
        #expect(label.secondLine == "USA")
    }

    @Test(arguments: ["⏰ 25:99 · Rangers v Celtic · FHD", "⏰ TBA · Rangers v Celtic · FHD"])
    func `an unreadable time drops only the time badge`(raw: String) {
        #expect(GFChannelLabel.parse(raw, now: now)
            == GFChannelLabel(title: "Rangers v Celtic", secondLine: nil, quality: "FHD", status: .none))
    }

    @Test(arguments: ["🔴 LIVE", "⏰ Sun 17:55", "▪ ", "🔴 LIVE · ", "▪ · HD", "⏰ "])
    func `an event name without a title is shown as written`(raw: String) {
        #expect(GFChannelLabel.parse(raw, now: now) == .unchanged(raw))
    }

    @Test func `a name cut at 255 characters still reads`() {
        let raw = String(("⏰ Sun 17:55 · " + String(repeating: "Very Long Title ", count: 30)).prefix(255))
        let label = GFChannelLabel.parse(raw, now: now)
        #expect(label.title.hasPrefix("Very Long Title"))
        #expect(kind(label.status) == .upcoming)
    }

    @Test func `the clock emoji with a variation selector counts`() {
        #expect(GFChannelLabel.parse("⏰\u{FE0F} Sun 17:55 · Japanese GP · 4K", now: now)
            == GFChannelLabel.parse("⏰ Sun 17:55 · Japanese GP · 4K", now: now))
    }

    @Test func `an icon without a space is an ordinary name`() {
        #expect(GFChannelLabel.parse("🔴Arsenal FHD", now: now)
            == GFChannelLabel(title: "🔴Arsenal", secondLine: nil, quality: "FHD", status: .none))
    }
}
