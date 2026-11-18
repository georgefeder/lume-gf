import Foundation
@testable import GuideCore
import Testing

struct GFGuidePauseTests {
    @Test func `nothing playing: no wait`() {
        let pause = GFGuidePause()
        var naps = 0
        #expect(pause.waitWhileHeld(shouldStop: { false }, nap: { _ in naps += 1 }) == false)
        #expect(naps == 0)
    }

    @Test func `video playing: waits until it ends`() {
        let pause = GFGuidePause()
        pause.hold(true)
        var naps = 0
        let waited = pause.waitWhileHeld(shouldStop: { false }, nap: { _ in
            naps += 1
            if naps == 3 { pause.hold(false) }
        })
        #expect(waited)
        #expect(naps == 3)
        #expect(pause.isHeld == false)
    }

    @Test func `a stop ends the wait while video still plays`() {
        let pause = GFGuidePause()
        pause.hold(true)
        var naps = 0
        pause.waitWhileHeld(shouldStop: { naps >= 2 }, nap: { _ in naps += 1 })
        #expect(naps == 2)
        #expect(pause.isHeld)
    }
}
