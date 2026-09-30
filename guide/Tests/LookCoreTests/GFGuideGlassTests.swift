import CoreGraphics
@testable import LookCore
import Testing

/// The glass guide's geometry (spec section 2): the grid runs under the sidebar with its content one sidebar-width in,
/// so Lume's scroll maths keep their meaning.
struct GFGuideGlassTests {
    @Test func `the grid's content starts one sidebar-width in`() {
        #expect(GFGuideGlass.contentPad(columnWidth: 300, slidesUnder: true) == 300)
        #expect(GFGuideGlass.gridLeadingInset(columnWidth: 300, slidesUnder: true) == 0)
    }

    @Test func `switched off, the grid starts beside the sidebar as in Lume`() {
        #expect(GFGuideGlass.contentPad(columnWidth: 300, slidesUnder: false) == 0)
        #expect(GFGuideGlass.gridLeadingInset(columnWidth: 300, slidesUnder: false) == 300)
    }

    @Test func `a scroll offset still means the time at the sidebar's edge`() {
        // a programme at timeline x 900, content padded by 300, scrolled to 600: it sits where Lume put it (900 - 600)
        let pad: CGFloat = 300, programme: CGFloat = 900, offset: CGFloat = 600
        let onScreen = programme + pad - offset
        #expect(GFGuideGlass.stickyMinX(blockMinX: onScreen, pad: pad) == programme - offset)
        #expect(GFGuideGlass.realizeOrigin(offsetX: offset, pad: pad) == offset - pad)
    }

    @Test func `the readable part leaves out the sidebar and the bottom fade`() {
        // Apple TV, as logged by the screenshot build: the grid fills the guide
        let size = GFGuideGlass.visibleSize(measured: CGSize(width: 1480, height: 952), guideHeight: 952, pad: 300,
                                            bottomFade: 65)
        #expect(size == CGSize(width: 1180, height: 887))
    }

    @Test func `the readable part ends at the guide's edge when the scroll view runs on below it`() {
        // iPhone above a tab bar: the guide is 718 high to the screen's edge, its scroll view 818
        let size = GFGuideGlass.visibleSize(measured: CGSize(width: 402, height: 818), guideHeight: 718, pad: 136,
                                            bottomFade: 134)
        #expect(size == CGSize(width: 266, height: 584))
    }

    @Test func `before the guide is measured the scroll view's height counts`() {
        let size = GFGuideGlass.visibleSize(measured: CGSize(width: 1500, height: 1000), guideHeight: 0, pad: 300,
                                            bottomFade: 125)
        #expect(size == CGSize(width: 1200, height: 875))
    }

    @Test func `a short guide never gets a negative size`() {
        #expect(GFGuideGlass.visibleSize(measured: CGSize(width: 100, height: 80), guideHeight: 80, pad: 300,
                                         bottomFade: 125) == .zero)
    }

    @Test func `the room under the last row makes up for a scroll view running on below the guide`() {
        // the last row can always scroll up to the fade: the fade's room, plus the run-on, less the scroll view's own
        #expect(GFGuideGlass.bottomPadding(bottomRoom: 65, scrollHeight: 952, guideHeight: 952, scrollInset: 0) == 65)
        #expect(GFGuideGlass.bottomPadding(bottomRoom: 134, scrollHeight: 818, guideHeight: 718, scrollInset: 0) == 234)
        #expect(GFGuideGlass.bottomPadding(bottomRoom: 134, scrollHeight: 916, guideHeight: 718, scrollInset: 98) == 234)
        #expect(GFGuideGlass.bottomPadding(bottomRoom: 134, scrollHeight: 718, guideHeight: 718, scrollInset: 98) == 36)
        #expect(GFGuideGlass.bottomPadding(bottomRoom: 30, scrollHeight: 718, guideHeight: 718, scrollInset: 98) == 0)
    }

    @Test func `the safe area under the guide is measured from where it ends`() {
        // inside the layer that runs under the tab bar SwiftUI reports no inset, so the guide measures it
        #expect(GFGuideGlass.safeAreaBottom(guideMaxY: 874, safeMaxY: 791) == 83) // iPhone: to the tab bar's top
        #expect(GFGuideGlass.safeAreaBottom(guideMaxY: 1080, safeMaxY: 1020) == 60) // Apple TV overscan
        #expect(GFGuideGlass.safeAreaBottom(guideMaxY: 874, safeMaxY: 0) == 0) // not measured yet
        #expect(GFGuideGlass.safeAreaBottom(guideMaxY: 700, safeMaxY: 791) == 0)
    }

    @Test func `the bottom fade covers the safe area and half a row`() {
        #expect(GFGuideGlass.bottomFade(safeAreaBottom: 60, rowStride: 130) == 125) // Apple TV
        #expect(GFGuideGlass.bottomFade(safeAreaBottom: 83, rowStride: 72) == 119) // iPhone above a tab bar
        #expect(GFGuideGlass.bottomFade(safeAreaBottom: -5, rowStride: 72) == 36)
    }

    @Test func `the grid's content starts one sidebar-width in from the guide's edge, wherever its scroll view starts`() {
        // iPhone in landscape: the scroll view runs on 62 points into the notch margin and insets its content by as
        // much; the content moves in by the same so the ruler's times stay level with the programmes
        #expect(GFGuideGlass.gridContentPad(contentPad: 136, scrollInsetLeading: 62) == 198)
        #expect(GFGuideGlass.gridContentPad(contentPad: 136, scrollInsetLeading: 0) == 136)
        #expect(GFGuideGlass.gridContentPad(contentPad: 300, scrollInsetLeading: -4) == 300)
    }

    @Test func `the panes follow the grid into its leading room but not past its start`() {
        // Lume clamps a bounce past the start; with room kept on the left the start itself is at minus that room
        #expect(GFGuideGlass.mirrorOffset(CGPoint(x: -62, y: -5), scrollInsetLeading: 62) == CGPoint(x: -62, y: 0))
        #expect(GFGuideGlass.mirrorOffset(CGPoint(x: -80, y: 10), scrollInsetLeading: 62) == CGPoint(x: -62, y: 10))
        #expect(GFGuideGlass.mirrorOffset(CGPoint(x: 500, y: 20), scrollInsetLeading: 0) == CGPoint(x: 500, y: 20))
        #expect(GFGuideGlass.mirrorOffset(CGPoint(x: -3, y: 0), scrollInsetLeading: 0) == CGPoint(x: 0, y: 0))
    }

    @Test func `only the iPhone fades rows under the ruler`() {
        // the Apple TV's rows meet the ruler as in Lume: a fade there painted a dark band over its backdrop
        #expect(GFGuideGlass.topFade(tv: true) == 0)
        #expect(GFGuideGlass.topFade(tv: false) == 10)
    }

    @Test func `Lume's panel corners: 36 on Apple TV, 16 on iPhone`() {
        #expect(GFGuideGlass.sidebarCornerRadius(tv: true) == 36)
        #expect(GFGuideGlass.sidebarCornerRadius(tv: false) == 16)
    }

    @Test func `the Apple TV focus highlight fits inside the sidebar`() {
        let insets = GFGuideGlass.sidebarInsets(tv: true)
        let right = GFGuideGlass.tvHighlightLeading + GFGuideGlass.tvHighlightWidth(columnWidth: 300)
        #expect(GFGuideGlass.tvHighlightLeading >= insets.leading)
        #expect(right <= 300 - insets.trailing)
        #expect(GFGuideGlass.tvHighlightWidth(columnWidth: 300) > 200)
    }

    @Test func `the tests run on the Mac, so this is not the Apple TV`() {
        #expect(!GFGuideGlass.isTV)
    }
}
