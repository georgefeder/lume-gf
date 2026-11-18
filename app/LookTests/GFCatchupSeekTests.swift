import Foundation
@testable import Lume
import Testing

/// Lume GF: a seek in a catch-up programme asks the archive again from that minute (GFCatchupSeek).
struct GFCatchupSeekTests {
    let base = URL(string: "http://example.com:8080/timeshift/user/pass/60/2026-11-18:14-00/60412.ts")!
    var window: GFCatchupSeek.Window {
        GFCatchupSeek.Window(baseURL: base, baseID: "catchup-a-1", length: 3600, offset: 0)
    }

    @Test func `a later start moves the start on and cuts the minutes to what is left`() {
        let url = GFCatchupSeek.url(window, offset: 25 * 60)
        #expect(url?.absoluteString == "http://example.com:8080/timeshift/user/pass/35/2026-11-18:14-25/60412.ts")
    }

    @Test func `the start goes over the hour and the day`() {
        let late = URL(string: "http://example.com/timeshift/user/pass/90/2026-11-18:23-30/7.ts")!
        let window = GFCatchupSeek.Window(baseURL: late, baseID: "x", length: 5400, offset: 0)
        let url = GFCatchupSeek.url(window, offset: 45 * 60)
        #expect(url?.absoluteString == "http://example.com/timeshift/user/pass/45/2026-11-19:00-15/7.ts")
    }

    @Test func `only an Xtream timeshift address gets a window`() {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(1800)
        #expect(GFCatchupSeek.window(url: base, id: "x", start: start, end: end)?.length == 1800)
        let flussonic = URL(string: "http://example.com/channel/index-1700000000-3600.m3u8")!
        #expect(GFCatchupSeek.window(url: flussonic, id: "x", start: start, end: end) == nil)
        let live = URL(string: "http://example.com/live/user/pass/60412.ts")!
        #expect(GFCatchupSeek.window(url: live, id: "x", start: start, end: end) == nil)
    }

    @Test func `a place on the bar goes to its minute`() {
        #expect(GFCatchupSeek.offset(for: .to(1530), current: 100, in: window) == 1500)
        #expect(GFCatchupSeek.offset(for: .to(10), current: 1600, in: window) == 0)
        // the end of the programme: its last minute
        #expect(GFCatchupSeek.offset(for: .to(3600), current: 100, in: window) == 3540)
    }

    @Test func `a step forward moves at least a minute, a step back restarts its minute`() {
        let playing = GFCatchupSeek.Window(baseURL: base, baseID: "x", length: 3600, offset: 300)
        #expect(GFCatchupSeek.offset(for: .by(15), current: 310, in: playing) == 360)
        #expect(GFCatchupSeek.offset(for: .by(300), current: 310, in: playing) == 600)
        #expect(GFCatchupSeek.offset(for: .by(-15), current: 350, in: playing) == 300)
        #expect(GFCatchupSeek.offset(for: .by(-15), current: 305, in: playing) == 240)
        // forward inside the minute already playing: nothing to do
        #expect(GFCatchupSeek.offset(for: .to(330), current: 310, in: playing) == nil)
        // nothing after the last minute
        let last = GFCatchupSeek.Window(baseURL: base, baseID: "x", length: 3600, offset: 3540)
        #expect(GFCatchupSeek.offset(for: .by(15), current: 3550, in: last) == nil)
    }

    @Test func `a jump is a new item for the same programme`() {
        let start = Date(timeIntervalSince1970: 1_763_474_400)
        var media = PlayableMedia(
            id: "catchup-a-1", url: base, title: "BBC News", subtitle: "News", posterURL: nil,
            kind: .vod, startTime: 0, contentRef: .live("a")
        )
        #expect(media.gfCatchupShifted(to: 600) == nil) // not a catch-up item
        media = PlayableMedia.gfWithCatchup(media, start: start, end: start.addingTimeInterval(3600))
        let next = media.gfCatchupShifted(to: 600)
        #expect(next?.id == "catchup-a-1+10m")
        #expect(next?.url.absoluteString == "http://example.com:8080/timeshift/user/pass/50/2026-11-18:14-10/60412.ts")
        #expect(next?.gfCatchup?.offset == 600)
        #expect(next?.title == "BBC News")
        // back to the start: the programme's own item again
        let back = next?.gfCatchupShifted(to: 0)
        #expect(back?.id == "catchup-a-1")
        #expect(back?.url == base)
    }
}
