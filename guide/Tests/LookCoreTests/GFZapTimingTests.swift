@testable import LookCore
import Testing

/// A channel change's timings from KSPlayer's log, as sent to the server (Georgs, 4 Nov: measure, then start faster).
struct GFZapTimingTests {
    @Test func `each step in milliseconds since the change began, over once the picture moves`() {
        var timing = GFZapTiming(stream: "12345.ts", started: 100)
        let lines: [(String, Double)] = [
            ("replace with 12345.ts starts", 100.010),
            ("12345.ts open queued", 100.012),
            ("12345.ts waits for 999.ts to close", 100.013),
            ("999.ts close starts", 100.020),
            ("999.ts input closed", 100.240),
            ("12345.ts stops waiting: closed", 100.241),
            ("12345.ts input opened (0)", 101.100),
            ("12345.ts stream info (0, state opening)", 101.900),
            ("12345.ts decoders made (state opening)", 101.950),
            ("12345.ts first picture", 102.300),
            ("12345.ts playable", 102.310),
            ("12345.ts playable", 102.500)
        ]
        for (line, time) in lines {
            let over1 = timing.note(line, at: time)
            #expect(!over1)
        }
        let over2 = timing.note("picture moving", at: 103.400)
        #expect(over2)
        #expect(timing.query(device: "iphone", build: "95")
            == "d=iphone&b=95&ch=12345&close=240&open=1100&info=1900&dec=1950&pic=2300&play=2310&move=3400")
    }

    @Test func `a failed open ends it with what happened, the steps that did not are left out`() {
        var timing = GFZapTiming(stream: "77.ts", started: 10)
        let over1 = timing.note("77.ts input opened (-5)", at: 12.5)
        #expect(over1)
        #expect(timing.query(device: "atv", build: "95") == "d=atv&b=95&ch=77&open=2500")
        var info = GFZapTiming(stream: "78.ts", started: 10)
        let over2 = info.note("78.ts input opened (0)", at: 11)
        #expect(!over2)
        let over3 = info.note("78.ts stream info (-1094995529, state opening)", at: 13)
        #expect(over3)
    }

    @Test func `a picture moving before it is playable, or another stream's lines, do not count`() {
        var timing = GFZapTiming(stream: "5.ts", started: 0)
        let over1 = timing.note("picture moving", at: 0.5)
        #expect(!over1)
        let over2 = timing.note("6.ts input opened (0)", at: 0.6)
        #expect(!over2)
        let over3 = timing.note("6.ts playable", at: 0.7)
        #expect(!over3)
        #expect(timing.query(device: "ipad", build: "95") == "d=ipad&b=95&ch=5")
        // the player closed before the picture moved: over, with what there was
        let over4 = timing.note("5.ts playable", at: 1)
        #expect(!over4)
        let over5 = timing.note("5.ts shuts down (was playable, reading: true)", at: 2)
        #expect(over5)
        #expect(timing.query(device: "ipad", build: "95") == "d=ipad&b=95&ch=5&play=1000")
    }

    @Test func `the player's Low Latency and Live Buffer settings go with the timings`() {
        var timing = GFZapTiming(stream: "60412.ts", started: 0, lowLatency: true, liveBuffer: 2)
        let over = timing.note("60412.ts input opened (0)", at: 1.2)
        #expect(!over)
        #expect(timing.query(device: "iphone", build: "96") == "d=iphone&b=96&ch=60412&ll=1&lb=2&open=1200")
        let off = GFZapTiming(stream: "60412.ts", started: 0, lowLatency: false, liveBuffer: 4)
        #expect(off.query(device: "atv", build: "96") == "d=atv&b=96&ch=60412&ll=0&lb=4")
    }

    @Test func `the report carries only the channel's digits, never its address or name`() {
        let timing = GFZapTiming(stream: "index.m3u8", started: 0)
        #expect(timing.channelNumber == nil)
        #expect(timing.query(device: "iphone", build: "95 (x)") == "d=iphone&b=95")
    }
}
