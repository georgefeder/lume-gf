import Foundation
@testable import LookCore
import Testing

/// A match on now leads Top Results, not its replays (Georgs, 5 Nov: Celtic v Beşiktaş was live on TNT Sports 3, and
/// Top Results led with three later replays titled "Celtic vs Beşiktaş").
struct GFSearchMatchTests {
    private let evening = Date(timeIntervalSince1970: 1_793_908_800) // 5 Nov 2026, 20:00 UTC

    private func airing(_ title: String, hours: Double, length: Double = 2) -> GFSearchEvents.Airing {
        let start = evening.addingTimeInterval(hours * 3600)
        return GFSearchEvents.Airing(title: title, start: start, end: start.addingTimeInterval(length * 3600))
    }

    @Test func `the match on now and its replays within a day are one, another show with the word is not`() {
        let airings = [
            airing("Live UEL: Celtic v Besiktas", hours: 0),                 // on now
            airing("UEFA Europa League: Celtic - Besiktas", hours: 0),       // the same, another channel
            airing("Celtic vs Beşiktaş", hours: 1.83),                       // today 21:50
            airing("UEL: Celtic v Besiktas", hours: 6.5),                    // tomorrow 02:30
            airing("Celtic Woman 20th Anniversary Concert", hours: 1),
            airing("Celtic vs Beşiktaş", hours: 50)                          // two days on: another showing
        ]
        let matches = GFSearchEvents.matches(airings, searched: ["celtic"])
        #expect(matches[0] == matches[1] && matches[1] == matches[2] && matches[2] == matches[3])
        #expect(matches[4] != matches[0])
        #expect(matches[5] != matches[0])
    }

    @Test func `two matches of a league searched by its name stay apart`() {
        let airings = [airing("Premier League: Arsenal v Chelsea", hours: -5),
                       airing("Premier League: Spurs v City", hours: -2.5)]
        let matches = GFSearchEvents.matches(airings, searched: ["premier", "league"])
        #expect(matches[0] != matches[1])
    }

    @Test func `the airing on now leads its family, which keeps its place among the others`() {
        typealias Row = GFSearchLayout.Row<String>
        let rows = [
            Row(kind: .programme, id: "replay-bein", score: 0.984, family: "match 0"),
            Row(kind: .programme, id: "replay-later", score: 0.955, family: "match 0"),
            Row(kind: .programme, id: "live-tnt", score: 0.953, family: "match 0"),
            Row(kind: .programme, id: "live-m", score: 0.90, family: "match 0"),
            Row(kind: .channel, id: "celtic-tv", score: 0.97),
            Row(kind: .film, id: "film", score: 0.5),
            Row(kind: .series, id: "series", score: 0.4)
        ]
        let led = GFSearchLayout.liveFirst(rows, live: ["live-tnt", "live-m"])
        let sections = GFSearchLayout.sections(led, allKinds: true)
        #expect(sections.first?.kind == nil)
        #expect(sections.first?.ids == ["live-tnt", "celtic-tv", "film"])
        // the match's other rows below, the ones on now first
        let programmes = sections.first { $0.kind == .programme }?.ids
        #expect(programmes == ["live-m", "replay-bein", "replay-later"])
    }
}
