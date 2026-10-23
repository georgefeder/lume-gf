import CoreGraphics
@testable import LookCore
import Testing

struct GFSubtitleScaleTests {
    @Test func `a phone keeps Lume's size`() {
        #expect(GFSubtitleScale.phonePointSize(shortSide: 393) == 16) // iPhone 17
        #expect(GFSubtitleScale.phonePointSize(shortSide: 440) == 16) // the largest iPhone (Pro Max)
        #expect(GFSubtitleScale.phonePointSize(shortSide: nil) == 16)
    }

    @Test func `a bigger screen grows the subtitles up to an iPad's`() {
        #expect(GFSubtitleScale.phonePointSize(shortSide: 466) == 17) // iPhone Duo, outer display (1398 px at 3x)
        #expect(GFSubtitleScale.phonePointSize(shortSide: 669) == 24) // iPhone Duo, inner display (2007 px at 3x)
        #expect(GFSubtitleScale.phonePointSize(shortSide: 744) == 26)
        #expect(GFSubtitleScale.phonePointSize(shortSide: 1024) == 26)
    }

    @Test func `the preview canvas grows with the subtitles`() {
        #expect(GFSubtitleScale.phonePreviewCanvas(pointSize: 16) == CGSize(width: 720, height: 405))
        #expect(GFSubtitleScale.phonePreviewCanvas(pointSize: 24) == CGSize(width: 1080, height: 607.5))
        #expect(GFSubtitleScale.phonePreviewCanvas(pointSize: 12) == CGSize(width: 720, height: 405))
    }
}
