import CoreGraphics
@testable import LookCore
import Testing

/// The player's level swipes (Georgs, 3 Nov): left half brightness, right half volume, up raises.
struct GFPlayerSwipeTests {
    private let landscape = CGSize(width: 874, height: 402)

    @Test func `the left half sets brightness, the right half volume, the edges neither`() {
        #expect(GFPlayerSwipe.kind(start: CGPoint(x: 100, y: 200), size: landscape) == .brightness)
        #expect(GFPlayerSwipe.kind(start: CGPoint(x: 700, y: 200), size: landscape) == .volume)
        #expect(GFPlayerSwipe.kind(start: CGPoint(x: 700, y: 20), size: landscape) == nil) // Control Centre's
        #expect(GFPlayerSwipe.kind(start: CGPoint(x: 100, y: 390), size: landscape) == nil) // the home gesture's
        #expect(GFPlayerSwipe.kind(start: CGPoint(x: 100, y: 200), size: .zero) == nil)
    }

    @Test func `only a drag mostly up or down, past ten points, is a swipe`() {
        #expect(GFPlayerSwipe.isVertical(CGSize(width: 2, height: -14)))
        #expect(!GFPlayerSwipe.isVertical(CGSize(width: 2, height: -6))) // not far enough yet
        #expect(!GFPlayerSwipe.isVertical(CGSize(width: 30, height: -20))) // more sideways than up
        #expect(GFPlayerSwipe.isVertical(CGSize(width: 10, height: 20)))
    }

    @Test func `up raises the level, six tenths of the height takes it all the way, within none and all`() {
        let height = landscape.height
        #expect(abs(GFPlayerSwipe.level(from: 0, dy: -height * 0.3, height: height) - 0.5) < 0.0001)
        #expect(GFPlayerSwipe.level(from: 0.5, dy: -height, height: height) == 1)
        #expect(abs(GFPlayerSwipe.level(from: 0.5, dy: height * 0.15, height: height) - 0.25) < 0.0001)
        #expect(GFPlayerSwipe.level(from: 0.1, dy: height, height: height) == 0)
        #expect(GFPlayerSwipe.level(from: 0.4, dy: 0, height: 0) == 0.4)
    }

    @Test func `the pill's percentage and icon follow the level`() {
        #expect(GFPlayerSwipe.percent(0.625) == 63)
        #expect(GFPlayerSwipe.percent(1.2) == 100)
        #expect(GFPlayerSwipe.symbol(.brightness, level: 0.2) == "sun.min.fill")
        #expect(GFPlayerSwipe.symbol(.brightness, level: 0.8) == "sun.max.fill")
        #expect(GFPlayerSwipe.symbol(.volume, level: 0) == "speaker.slash.fill")
        #expect(GFPlayerSwipe.symbol(.volume, level: 0.2) == "speaker.wave.1.fill")
        #expect(GFPlayerSwipe.symbol(.volume, level: 0.5) == "speaker.wave.2.fill")
        #expect(GFPlayerSwipe.symbol(.volume, level: 0.9) == "speaker.wave.3.fill")
    }
}
