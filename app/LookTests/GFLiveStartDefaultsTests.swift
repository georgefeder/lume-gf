import Foundation
@testable import Lume
import Testing

/// Lume GF's live-TV start (docs/lume-gf/2026-09-29-live-tv-handover.md, finding 1, measured on 29 Sep): KSPlayer
/// opens live channels with "Fast Open" and a 2-second buffer by default. A device where the value was changed by hand
/// keeps its own (they are settings defaults).
struct GFLiveStartDefaultsTests {
    @Test func `KSPlayer starts live channels fast by default`() {
        #expect(PlayerSettings.KSPlayer.secondOpenDefault)
        #expect(PlayerSettings.KSPlayer.liveBufferDefault == 2)
    }

    @Test func `on-demand keeps Lume's longer buffer`() {
        #expect(PlayerSettings.KSPlayer.vodBufferDefault == 8)
    }
}
