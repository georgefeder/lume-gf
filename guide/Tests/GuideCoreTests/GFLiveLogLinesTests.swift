import Foundation
@testable import GuideCore
import Testing

struct GFLiveLogLinesTests {
    @Test func `a line that could carry an address or login never leaves`() {
        #expect(GFLiveLogLines.clean("opened https://example.org/live/u/p/1.ts") == nil)
        #expect(GFLiveLogLines.clean("guide xmltv.php?username=u") == nil)
        #expect(GFLiveLogLines.clean("mail me@example.org") == nil)
        #expect(GFLiveLogLines.clean("guide p=delta dl=210 ap=4800 ok=1") == "guide p=delta dl=210 ap=4800 ok=1")
    }

    @Test func `control characters go and long lines are cut`() {
        #expect(GFLiveLogLines.clean("a\u{7}b\n") == "ab")
        #expect(GFLiveLogLines.clean(String(repeating: "x", count: 500))?.count == GFLiveLogLines.maxLength)
        #expect(GFLiveLogLines.clean("   ") == nil)
    }

    @Test func `lines are sent in small batches, in order`() {
        let lines = (0 ..< 40).map { String(repeating: "x", count: 99) + "\($0 % 10)" }
        let batches = GFLiveLogLines.batches(lines)
        #expect(batches.count == 3 && batches.flatMap { $0 } == lines)
        #expect(batches.allSatisfy { $0.reduce(0) { $0 + $1.count + 1 } <= GFLiveLogLines.maxBatchCharacters })
    }

    @Test func `sent only with the app on screen, after a minute or with many lines`() {
        #expect(GFLiveLogLines.shouldSend(waiting: 3, sinceLast: 61, appActive: true))
        #expect(GFLiveLogLines.shouldSend(waiting: 40, sinceLast: 5, appActive: true))
        #expect(GFLiveLogLines.shouldSend(waiting: 3, sinceLast: 5, appActive: true) == false)
        #expect(GFLiveLogLines.shouldSend(waiting: 100, sinceLast: 600, appActive: false) == false)
        #expect(GFLiveLogLines.shouldSend(waiting: 0, sinceLast: 600, appActive: true) == false)
    }
}
