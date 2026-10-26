@testable import LookCore
import Testing

struct GFEnhancePlanTests {
    @Test func `SD triples where it can, as 4x would be taller than 4K`() {
        #expect(GFEnhancePlan.scale(width: 720, height: 576, supported: [2, 3, 4]) == 3)
        #expect(GFEnhancePlan.scaled(width: 720, height: 576, by: 3) == (2160, 1728))
        #expect(GFEnhancePlan.scale(width: 720, height: 576, supported: [2]) == 2)
        #expect(GFEnhancePlan.scaled(width: 720, height: 576, by: 2) == (1440, 1152))
    }

    @Test func `720p triples to exactly 4K when the upscaler can`() {
        #expect(GFEnhancePlan.scale(width: 1280, height: 720, supported: [2, 3]) == 3)
        #expect(GFEnhancePlan.scaled(width: 1280, height: 720, by: 3) == (3840, 2160))
        #expect(GFEnhancePlan.scale(width: 1280, height: 720, supported: [2]) == 2)
    }

    @Test func `1080p and up, and sizes the upscaler can't do, stay as they are`() {
        #expect(GFEnhancePlan.scale(width: 1920, height: 1080, supported: [2]) == nil)
        #expect(GFEnhancePlan.scale(width: 3840, height: 2160, supported: [2]) == nil)
        #expect(GFEnhancePlan.scale(width: 1280, height: 720, supported: []) == nil)
        #expect(GFEnhancePlan.scale(width: 1280, height: 720, supported: [1, 4]) == nil) // 4x is past 4K
    }

    @Test func `odd results are made even`() {
        #expect(GFEnhancePlan.scaled(width: 704, height: 405, by: 1.5) == (1056, 608))
    }

    @Test func `a letterboxed or anamorphic full HD frame is not upscaled`() {
        #expect(GFEnhancePlan.scale(width: 1920, height: 800, supported: [2]) == nil)
        #expect(GFEnhancePlan.scale(width: 1440, height: 1080, supported: [2]) == nil)
        #expect(GFEnhancePlan.isBelowFullHD(width: 960, height: 540))
        #expect(!GFEnhancePlan.isBelowFullHD(width: 0, height: 576))
    }

    private let v420 = GFEnhancePlan.videoRange420BiPlanar, f420bi = GFEnhancePlan.fullRange420BiPlanar
    private let y420 = GFEnhancePlan.videoRange420Planar, tenBit: UInt32 = 0x7834_3230 // 'x420'

    @Test func `the format keeps the source's own, else its range, and is never 10-bit`() {
        #expect(GFEnhancePlan.format(for: y420, from: [v420, f420bi]) == v420) // KSPlayer's channels
        #expect(GFEnhancePlan.format(for: y420, from: [y420, v420]) == y420)
        #expect(GFEnhancePlan.format(for: f420bi, from: [v420, f420bi]) == f420bi)
        #expect(GFEnhancePlan.format(for: v420, from: [tenBit, f420bi]) == f420bi)
        #expect(GFEnhancePlan.format(for: v420, from: [tenBit]) == nil)
    }

    @Test func `only 8-bit 4:2:0 sources are upscaled`() {
        #expect(GFEnhancePlan.format(for: tenBit, from: [v420, tenBit]) == nil) // may be HDR
        #expect(GFEnhancePlan.format(for: 0x4247_5241, from: [v420]) == nil) // BGRA
    }

    @Test func `odd sizes and factors that miss whole even pixels are left alone`() {
        #expect(GFEnhancePlan.scale(width: 853, height: 480, supported: [2, 3]) == nil)
        #expect(GFEnhancePlan.scale(width: 722, height: 576, supported: [1.5]) == nil) // 1083 wide
        #expect(GFEnhancePlan.scale(width: 704, height: 576, supported: [1.5]) == 1.5) // 1056x864
        #expect(GFEnhancePlan.scale(width: 720, height: 576, supported: [1.5, 2.5]) == 2.5) // 1800x1440
    }

    @Test func `formats are named by their four characters`() {
        #expect(GFEnhancePlan.name(of: v420) == "420v")
        #expect(GFEnhancePlan.name(of: y420) == "y420")
        #expect(GFEnhancePlan.name(of: 1) == "1")
    }
}
