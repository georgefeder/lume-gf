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

    @Test func `rows fade under the ruler, on the Apple TV only above where the first tile starts`() {
        // Apple TV: half Lume's 14-point row gap, the space above each programme tile (a mask, so no painted band)
        #expect(GFGuideGlass.topFade(tv: true) == 7)
        #expect(GFGuideGlass.topFade(tv: false) == 10)
    }

    @Test func `the Apple TV channel highlight is as tall as the programme tiles beside it`() {
        // Lume leaves the row gap around each programme tile: 116 - 14 = 102 on the Apple TV
        #expect(GFGuideGlass.tileHeight(rowHeight: 116, rowSpacing: 14) == 102)
        #expect(GFGuideGlass.tileHeight(rowHeight: 10, rowSpacing: 14) == 0)
    }

    @Test func `the Apple TV panel reaches above the first channel, clear of its rounded corner`() {
        let insets = GFGuideGlass.sidebarInsets(tv: true)
        #expect(insets.top < 0)
        let firstTileTop = -insets.top + 14 / 2
        let corner = GFGuideGlass.cornerIntrusion(radius: GFGuideGlass.sidebarCornerRadius(tv: true),
                                                  inset: GFGuideGlass.tvHighlightLeading - insets.leading)
        #expect(firstTileTop > corner)
        #expect(GFGuideGlass.sidebarInsets(tv: false) == GFGuideGlass.Insets(leading: 16, trailing: 6, top: -4))
    }

    @Test func `a rounded corner reaches down less the further in you go`() {
        #expect(GFGuideGlass.cornerIntrusion(radius: 36, inset: 0) == 36)
        #expect(abs(GFGuideGlass.cornerIntrusion(radius: 36, inset: 8) - 13.37) < 0.01)
        #expect(GFGuideGlass.cornerIntrusion(radius: 36, inset: 40) == 0)
    }

    @Test func `panel corners: Lume's 36 on Apple TV; on iPhone parallel to the channel boxes'`() {
        #expect(GFGuideGlass.sidebarCornerRadius(tv: true) == 36)
        #expect(GFGuideGlass.sidebarCornerRadius(tv: false) == GFGuideGlass.phoneTileRadius + GFGuideGlass.phoneBoxGap)
    }

    @Test func `the iPhone's panel leaves the same gap above the first channel as beside every channel`() {
        // Georgs on build 22: the first channel sat on the panel's top edge
        let firstTileTop = GFGuideGlass.gridTopRoom(tv: false, rowSpacing: 4) + 4 / 2
        let gapAbove = firstTileTop - GFGuideGlass.panelTop(tv: false, rowSpacing: 4)
        let box = GFGuideGlass.channelBoxInset(tv: false)!, panel = GFGuideGlass.sidebarInsets(tv: false)
        #expect(gapAbove == GFGuideGlass.phoneBoxGap)
        #expect(box.leading - panel.leading == GFGuideGlass.phoneBoxGap)
        #expect(box.trailing - panel.trailing == GFGuideGlass.phoneBoxGap)
    }

    @Test func `the Apple TV focus highlight fits inside the sidebar`() {
        let insets = GFGuideGlass.sidebarInsets(tv: true)
        let right = GFGuideGlass.tvHighlightLeading + GFGuideGlass.tvHighlightWidth(columnWidth: 300)
        #expect(GFGuideGlass.tvHighlightLeading >= insets.leading)
        #expect(right <= 300 - insets.trailing)
        #expect(GFGuideGlass.tvHighlightWidth(columnWidth: 300) > 200)
    }

    @Test func `the first row starts below the top fade, so nothing fades until you scroll`() {
        // Georgs on build 9: the first channel and programmes sat where the fade already starts
        #expect(GFGuideGlass.gridTopRoom(tv: true, rowSpacing: 14) == 14)
        #expect(GFGuideGlass.gridTopRoom(tv: false, rowSpacing: 4) == 22)
        for (tv, spacing) in [(true, CGFloat(14)), (false, CGFloat(4))] {
            let firstTileTop = GFGuideGlass.gridTopRoom(tv: tv, rowSpacing: spacing) + spacing / 2
            #expect(firstTileTop - GFGuideGlass.topFade(tv: tv) == spacing + GFGuideGlass.topBreathingRoom(tv: tv))
        }
    }

    @Test func `the iPhone's first row starts 24 points under the ruler`() {
        // Georgs on build 16: the first channel still sat too close under the ruler (14 points)
        #expect(GFGuideGlass.gridTopRoom(tv: false, rowSpacing: 4) + 4 / 2 == 24)
        #expect(GFGuideGlass.topBreathingRoom(tv: false) == 10)
        #expect(GFGuideGlass.topBreathingRoom(tv: true) == 0) // the Apple TV's panel already reaches above its first row
    }

    @Test func `the panel's top moves down with the first row`() {
        #expect(GFGuideGlass.panelTop(tv: true, rowSpacing: 14) == -2) // still reaching above the first channel
        #expect(GFGuideGlass.panelTop(tv: false, rowSpacing: 4) == 18)
        let firstTileTop = GFGuideGlass.gridTopRoom(tv: true, rowSpacing: 14) + 7
        let corner = GFGuideGlass.cornerIntrusion(radius: GFGuideGlass.sidebarCornerRadius(tv: true),
                                                  inset: GFGuideGlass.tvHighlightLeading)
        #expect(firstTileTop - GFGuideGlass.panelTop(tv: true, rowSpacing: 14) > corner)
    }

    @Test func `programmes fade out under the panel, gone by its middle`() {
        // Georgs on build 9: tiles showed on the panel's left side (the Apple TV's glass bends what is under its edge)
        #expect(GFGuideGlass.underPanelFade(columnWidth: 300, tv: true) == GFGuideGlass.UnderPanel(gone: 142, clear: 284))
        #expect(GFGuideGlass.underPanelFade(columnWidth: 154, tv: false) == GFGuideGlass.UnderPanel(gone: 82, clear: 148))
        #expect(GFGuideGlass.underPanelFade(columnWidth: 4, tv: false) == GFGuideGlass.UnderPanel(gone: 16, clear: 16))
    }

    @Test func `a focused programme grows by Lume's 4 percent, but never over the gap to its neighbour`() {
        // Georgs on build 9: a focused five-hour programme spread 75 points over the tile before it
        #expect(GFGuideGlass.focusScale(width: 200, rowSpacing: 14) == 1.04)
        #expect(GFGuideGlass.focusScale(width: 3850, rowSpacing: 14) == 1 + 12.0 / 3850)
        #expect(GFGuideGlass.focusScale(width: 200, rowSpacing: 4) == 1.01)
        #expect(GFGuideGlass.focusScale(width: 0, rowSpacing: 14) == 1)
        for width: CGFloat in [100, 300, 1000, 3850, 10000] {
            let growth = width * (GFGuideGlass.focusScale(width: width, rowSpacing: 14) - 1) / 2
            #expect(growth <= 6.0001)
        }
    }

    @Test func `the Apple TV scrolls a row into view below the top room`() {
        // Lume's rows start `gridTopRoom` down: a row above lands there, a row below ends at the readable bottom
        func target(_ row: Int, from y: CGFloat) -> CGFloat {
            GFGuideGlass.rowScrollTarget(row: row, currentY: y, viewportHeight: 800, rowHeight: 116, rowSpacing: 14,
                                         topRoom: 14)
        }
        #expect(target(0, from: 300) == 0)
        #expect(target(2, from: 300) == 260)
        #expect(target(3, from: 0) == 0) // in view: 404...520
        #expect(target(6, from: 0) == 110) // its bottom, 910, ends at 800
    }

    @Test func `the Apple TV scrolls no further than the last row`() {
        #expect(GFGuideGlass.maxScrollY(rows: 20, viewportHeight: 800, rowHeight: 116, rowSpacing: 14, topRoom: 14)
            == 1800)
        #expect(GFGuideGlass.maxScrollY(rows: 3, viewportHeight: 800, rowHeight: 116, rowSpacing: 14, topRoom: 14) == 0)
    }

    @Test func `each iPhone channel box is as tall as its programme tiles and sits just inside the panel`() {
        let box = GFGuideGlass.channelBoxInset(tv: false)!, panel = GFGuideGlass.sidebarInsets(tv: false)
        #expect(box.leading == panel.leading + 6 && box.trailing == panel.trailing + 6)
        #expect(GFGuideGlass.tileHeight(rowHeight: 68, rowSpacing: 4) == 64) // the box's height on iPhone
        #expect(GFGuideGlass.channelBoxInset(tv: true) == nil)
        let content = GFGuideGlass.channelContentPadding(tv: false)
        #expect(content.leading == box.leading + 4 && content.trailing == box.trailing + 4)
    }

    @Test func `the iPhone's glass column starts on the toolbar's edge and keeps the panel and names their width`() {
        let panel = GFGuideGlass.sidebarInsets(tv: false), content = GFGuideGlass.channelContentPadding(tv: false)
        #expect(panel.leading == 16) // the toolbar's leading margin
        #expect(GFGuideGlass.phoneColumnWidth - panel.leading - panel.trailing == 132)
        let lumeNameRoom: CGFloat = 136 - 24 // Lume's column less its 12-point margins
        #expect(GFGuideGlass.phoneColumnWidth - content.leading - content.trailing == lumeNameRoom) // the names' room
        #expect(GFGuideGlass.headerTopGap(tv: false) == 10 && GFGuideGlass.headerTopGap(tv: true) == 0)
    }

    @Test func `the Now button lines up with the panel's edges`() {
        let button = GFGuideGlass.nowButtonInsets(tv: false), panel = GFGuideGlass.sidebarInsets(tv: false)
        #expect(button.leading == panel.leading && button.trailing == panel.trailing)
    }

    @Test func `the ruler's times fade at both ends, on the Apple TV as wide as the programmes' blurred edge`() {
        let phone = GFGuideGlass.rulerFade(tv: false), tv = GFGuideGlass.rulerFade(tv: true)
        #expect(phone.leading > 0 && phone.trailing > 0)
        #expect(tv.leading == GFGuideGlass.gridEdge(tv: true) && tv.trailing > 0)
    }

    @Test func `text blurs more the further it reaches into the edge, and is sharp past it`() {
        #expect(GFGuideGlass.edgeBlur(textMinX: 48, edge: 48) == 0)
        #expect(GFGuideGlass.edgeBlur(textMinX: 200, edge: 48) == 0)
        #expect(GFGuideGlass.edgeBlur(textMinX: 24, edge: 48) == 4)
        #expect(GFGuideGlass.edgeBlur(textMinX: 0, edge: 48) == 8)
        #expect(GFGuideGlass.edgeBlur(textMinX: -30, edge: 48) == 8)
        #expect(GFGuideGlass.edgeBlur(textMinX: 0, edge: 0) == 0)
    }

    @Test func `only the Apple TV's programmes blur at the channel column (the iPhone's slide under its glass)`() {
        #expect(GFGuideGlass.gridEdge(tv: true) == 48)
        #expect(GFGuideGlass.gridEdge(tv: false) == 0)
    }

    @Test func `the tests run on the Mac, so this is not the Apple TV`() {
        #expect(!GFGuideGlass.isTV)
    }

    @Test func `the guide as drawn keeps the iPhone's top room (the tests run on the Mac, not the Apple TV)`() {
        #expect(GFGuideGlass.topRoom(rowSpacing: 4) == GFGuideGlass.gridTopRoom(tv: false, rowSpacing: 4))
        #expect(GFGuideGlass.slidesUnderSidebar)
    }

    @Test func `short programmes: a title when one fits, else a plain tile, a sliver for minutes`() {
        #expect(GFGuideGlass.tileContent(width: 90) == .full) // half an hour on iPhone
        #expect(GFGuideGlass.tileContent(width: 45) == .blank) // a quarter of an hour: only "…" would fit
        #expect(GFGuideGlass.tileContent(width: 9) == .sliver) // three minutes
        #expect(GFGuideGlass.tileContent(width: 50) == .full)
    }

    @Test func `a time label under the Now pill fades out, its neighbours stay`() {
        let width = GFGuideGlass.rulerLabelWidth(text: "23:00", isHour: true)
        #expect(GFGuideGlass.rulerLabelHidden(labelMinX: 7, labelWidth: width, nowX: 15)) // 23:05, label at 23:00
        #expect(!GFGuideGlass.rulerLabelHidden(labelMinX: 97, labelWidth: width, nowX: 15)) // 23:30
        #expect(!GFGuideGlass.rulerLabelHidden(labelMinX: -83, labelWidth: width, nowX: 15)) // 22:30
        #expect(GFGuideGlass.rulerLabelWidth(text: "11:00 PM", isHour: true)
            > GFGuideGlass.rulerLabelWidth(text: "23:00", isHour: true))
    }
}
