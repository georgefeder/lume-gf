@testable import LookCore
import Testing

struct GFEnhancePlanTests {
    @Test func `SD doubles, as 3x would be taller than 4K`() {
        #expect(GFEnhancePlan.scale(width: 720, height: 576, supported: [2, 3, 4]) == 2)
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
}
