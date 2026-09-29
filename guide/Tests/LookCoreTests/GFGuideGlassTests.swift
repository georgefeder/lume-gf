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
        let size = GFGuideGlass.visibleSize(measured: CGSize(width: 1500, height: 1000), scrollInset: 0, pad: 300,
                                            bottomFade: 125)
        #expect(size == CGSize(width: 1200, height: 875))
    }

    @Test func `the readable part leaves out what the scroll view runs on below the screen`() {
        // iPhone above a tab bar: the scroll view reaches 99 points past the screen's edge and insets its content by as
        // much; the guide above the tab bar is 718 high and fades over its last 135
        let size = GFGuideGlass.visibleSize(measured: CGSize(width: 402, height: 817), scrollInset: 99, pad: 136,
                                            bottomFade: 135)
        #expect(size == CGSize(width: 266, height: 583))
    }

    @Test func `a short guide never gets a negative size`() {
        #expect(GFGuideGlass.visibleSize(measured: CGSize(width: 100, height: 80), scrollInset: 30, pad: 300,
                                         bottomFade: 125) == .zero)
    }

    @Test func `the bottom fade covers the safe area and half a row`() {
        #expect(GFGuideGlass.bottomFade(safeAreaBottom: 60, rowStride: 130) == 125) // Apple TV
        #expect(GFGuideGlass.bottomFade(safeAreaBottom: 83, rowStride: 72) == 119) // iPhone above a tab bar
        #expect(GFGuideGlass.bottomFade(safeAreaBottom: -5, rowStride: 72) == 36)
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
