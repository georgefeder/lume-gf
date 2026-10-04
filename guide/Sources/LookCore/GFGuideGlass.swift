import CoreGraphics

/// Where the guide's glass sidebar sits and how the programme grid runs underneath it (spec:
/// docs/superpowers/specs/2026-09-29-lume-gf-3-look-design.md, section 2).
///
/// The grid's scroll area spans the whole guide and its content starts one sidebar-width in (`contentPad`), so a
/// scroll offset keeps meaning "the time at the sidebar's edge" and Lume's scroll maths keep working. Lume's code
/// learns about the pad in three places: sticky titles (`stickyMinX`), the realise window (`realizeOrigin`) and the
/// size the viewer can read (`visibleSize`), which the Apple TV's keep-the-focus-visible uses — the bottom fade counts
/// as outside.
nonisolated enum GFGuideGlass {
    /// false puts the grid beside the sidebar again: nothing slides under the glass. Off on the Apple TV, whose guide
    /// is Lume 2.3's own design (Georgs' look applies to iPhone and iPad).
    static var slidesUnderSidebar: Bool {
        !isTV
    }

    static var isTV: Bool {
        #if os(tvOS)
            true
        #else
            false
        #endif
    }

    struct Insets: Equatable, Sendable {
        var leading: CGFloat
        var trailing: CGFloat
        var top: CGFloat
    }

    static func contentPad(columnWidth: CGFloat, slidesUnder: Bool = slidesUnderSidebar) -> CGFloat {
        slidesUnder ? columnWidth : 0
    }

    static func gridLeadingInset(columnWidth: CGFloat, slidesUnder: Bool = slidesUnderSidebar) -> CGFloat {
        slidesUnder ? 0 : columnWidth
    }

    /// What the grid's scroll view reports in one reading: its offset, its size and the room it keeps below its
    /// content. Under the iPhone's tab bar it runs on past the guide's edge (the screen's): its size is not what shows.
    nonisolated struct ScrollFrame: Equatable, Sendable {
        var offset: CGPoint
        var size: CGSize
        var insetBottom: CGFloat
        /// iPhone in landscape: the room kept at the content's start, as far as the scroll view runs into the notch
        /// margin; the content is drawn from there, not from the guide's edge.
        var insetLeading: CGFloat
    }

    /// The guide's own coordinate space (its leading edge at the sidebar's): sticky titles measure from here, whatever
    /// the scroll view's frame and insets.
    static let spaceName = "gfGuide"

    /// The grid content's leading padding: one sidebar-width in from the guide's edge, plus the room the scroll view
    /// keeps where it runs on into a side margin, so the ruler's times stay level with the programmes.
    static func gridContentPad(contentPad: CGFloat, scrollInsetLeading: CGFloat) -> CGFloat {
        contentPad + max(0, scrollInsetLeading)
    }

    /// The offset the ruler and channel column mirror: Lume clamps a bounce past the grid's start, which sits at minus
    /// the room kept on the left.
    static func mirrorOffset(_ offset: CGPoint, scrollInsetLeading: CGFloat) -> CGPoint {
        CGPoint(x: max(-max(0, scrollInsetLeading), offset.x), y: max(0, offset.y))
    }

    /// The part the viewer reads: right of the sidebar, above the bottom fade, within the guide (`guideHeight`, the
    /// guide's height on screen; 0 before it is measured).
    static func visibleSize(measured: CGSize, guideHeight: CGFloat, pad: CGFloat, bottomFade: CGFloat) -> CGSize {
        let height = guideHeight > 0 ? min(measured.height, guideHeight) : measured.height
        return CGSize(width: max(0, measured.width - pad), height: max(0, height - bottomFade))
    }

    /// The room under the last row, so it can always scroll up to the fade: the fade's room, plus however far the
    /// scroll view runs on below the guide, less the room the scroll view keeps below its content itself.
    static func bottomPadding(bottomRoom: CGFloat, scrollHeight: CGFloat, guideHeight: CGFloat,
                              scrollInset: CGFloat) -> CGFloat {
        let runOn = guideHeight > 0 ? max(0, scrollHeight - guideHeight) : 0
        return max(0, bottomRoom + runOn - max(0, scrollInset))
    }

    /// The timeline x at the scroll area's leading edge (under the sidebar), for the realise window.
    static func realizeOrigin(offsetX: CGFloat, pad: CGFloat) -> CGFloat {
        offsetX - pad
    }

    /// A programme's leading edge measured from the sidebar's edge, which is what Lume's sticky titles expect.
    static func stickyMinX(blockMinX: CGFloat, pad: CGFloat) -> CGFloat {
        blockMinX - pad
    }

    /// How far the guide runs on past its safe area at the bottom (under the iPhone's tab bar, into the Apple TV's
    /// overscan). SwiftUI reports no inset inside a layer that runs on under it, so it is measured: the guide's bottom
    /// edge less where the safe area ends (`safeMaxY`, 0 before it is measured).
    static func safeAreaBottom(guideMaxY: CGFloat, safeMaxY: CGFloat) -> CGFloat {
        safeMaxY > 0 ? max(0, guideMaxY - safeMaxY) : 0
    }

    /// Through the safe area (the TV's overscan, the iPhone's tab bar) and half a row more.
    static func bottomFade(safeAreaBottom: CGFloat, rowStride: CGFloat) -> CGFloat {
        max(0, safeAreaBottom) + rowStride / 2
    }

    /// Rows scrolling under the ruler fade out: on the Apple TV over the space above each programme tile (half Lume's
    /// 14-point row gap, so the first tile starts below it; a mask there, no painted band), on iPhone over 10 points.
    static func topFade(tv: Bool) -> CGFloat {
        tv ? 7 : 10
    }

    /// The height of a programme tile: Lume leaves the row gap around each (the Apple TV's channel highlight matches).
    static func tileHeight(rowHeight: CGFloat, rowSpacing: CGFloat) -> CGFloat {
        max(0, rowHeight - rowSpacing)
    }

    /// How far a rounded corner of `radius` reaches down from the top edge at `inset` in from the side.
    static func cornerIntrusion(radius: CGFloat, inset: CGFloat) -> CGFloat {
        guard inset < radius else { return 0 }
        let across = radius - max(0, inset)
        return radius - (radius * radius - across * across).squareRoot()
    }

    static func sidebarInsets(tv: Bool) -> Insets {
        // Apple TV: the panel reaches 16 points above the first channel, which then sits in the glass like the
        // programme tiles beside it (not on its edge)
        // iPhone: the panel's leading edge on the toolbar's (16 points in), so the Now button and the glass column
        // line up with the buttons above them (Georgs on build 21)
        tv ? Insets(leading: 0, trailing: 16, top: -16) : Insets(leading: 16, trailing: 6, top: 4)
    }

    /// Lume's own panel sizes: 36 for its big Apple TV panels, 16 for its glass cards.
    static func sidebarCornerRadius(tv: Bool) -> CGFloat {
        tv ? 36 : 16
    }

    /// iPhone and iPad: each channel sits in a box as tall as the programme tiles beside it, 2 points inside the panel
    /// (Georgs on build 17). nil on the Apple TV, whose focused channel has its own highlight.
    static func channelBoxInset(tv: Bool) -> (leading: CGFloat, trailing: CGFloat)? {
        guard !tv else { return nil }
        let insets = sidebarInsets(tv: tv)
        return (insets.leading + 2, insets.trailing + 2)
    }

    /// The iPhone's channel column: as wide as Lume's 136 plus the 10 points the panel moved in by, so names keep their
    /// room.
    static let phoneColumnWidth: CGFloat = 146

    /// A channel's logo and name inside its box: 4 points from the box on each side.
    static func channelContentPadding(tv: Bool) -> (leading: CGFloat, trailing: CGFloat) {
        guard let box = channelBoxInset(tv: tv) else { return (12, 12) }
        return (box.leading + 4, box.trailing + 4)
    }

    /// iPhone: room between the toolbar and the Now button (the category strip that sat between them is gone).
    static func headerTopGap(tv: Bool) -> CGFloat {
        tv ? 0 : 10
    }

    /// The jump-to-now button spans the glass panel under it, edge to edge (Georgs on build 18: it sat off the panel's
    /// lines): its side insets are the panel's.
    static func nowButtonInsets(tv: Bool) -> (leading: CGFloat, trailing: CGFloat) {
        let insets = sidebarInsets(tv: tv)
        return (insets.leading, insets.trailing)
    }

    /// How far the ruler's times blur and fade out at the channel column's edge and the screen's (Georgs on builds 18
    /// and 21); on the Apple TV as wide as the programmes' blurred edge below them.
    static func rulerFade(tv: Bool) -> (leading: CGFloat, trailing: CGFloat) {
        tv ? (gridEdge(tv: true), 40) : (36, 28)
    }

    /// The Apple TV guide: programmes blur and fade out over this many points as they reach the channel column, and
    /// their titles park just past it (Georgs on build 21). The iPhone's programmes slide under its glass column.
    static func gridEdge(tv: Bool) -> CGFloat {
        tv ? 48 : 0
    }

    /// How blurred a programme's text is when it starts at `textMinX` (in the guide's scroll view): sharp from the end
    /// of the blurred edge on, `maxBlur` points at the channel column, in proportion between (a programme ending inside
    /// the edge pushes its text there; any other title parks past it).
    static func edgeBlur(textMinX: CGFloat, edge: CGFloat, maxBlur: CGFloat = 8) -> CGFloat {
        guard edge > 0, textMinX < edge else { return 0 }
        return maxBlur * min(1, (edge - textMinX) / edge)
    }

    /// Room above the first row: the top fade, the iPhone's breathing room, then the half row gap Lume leaves above
    /// every tile, so the first row starts below the fade and rows only fade once you scroll (Georgs on build 9: the
    /// first channel and programmes sat where the fade already starts). Both panes and the scroll maths start their
    /// rows this far down.
    static func gridTopRoom(tv: Bool, rowSpacing: CGFloat) -> CGFloat {
        topFade(tv: tv) + topBreathingRoom(tv: tv) + rowSpacing / 2
    }

    /// The room above the first row in the guide as drawn: `gridTopRoom` on iPhone and iPad, none on the Apple TV (Lume
    /// 2.3's own guide lays its rows out itself).
    static func topRoom(rowSpacing: CGFloat) -> CGFloat {
        isTV ? 0 : gridTopRoom(tv: false, rowSpacing: rowSpacing)
    }

    /// The iPhone's first row starts 24 points under the ruler, not 14 (Georgs on build 16: the first channel still
    /// sat too close to it); the Apple TV's panel already reaches above its first row.
    static func topBreathingRoom(tv: Bool) -> CGFloat {
        tv ? 0 : 10
    }

    /// The panel's top in the channel column: `sidebarInsets.top` from the first row, which starts `gridTopRoom` down.
    static func panelTop(tv: Bool, rowSpacing: CGFloat) -> CGFloat {
        gridTopRoom(tv: tv, rowSpacing: rowSpacing) + sidebarInsets(tv: tv).top
    }

    /// Where programmes fade out under the panel, measured from the channel column's leading edge: whole up to its
    /// trailing edge (`clear`), gone by its middle (`gone`) and everywhere left of that. Nothing is left under the
    /// panel's left side for the Apple TV's glass to bend into view (Georgs on build 9: tiles showed along its left
    /// edge), and nothing shows beside it (the iPhone's strip left of the panel).
    struct UnderPanel: Equatable, Sendable {
        var gone: CGFloat
        var clear: CGFloat
    }

    static func underPanelFade(columnWidth: CGFloat, tv: Bool) -> UnderPanel {
        let insets = sidebarInsets(tv: tv)
        let clear = max(insets.leading, columnWidth - insets.trailing)
        return UnderPanel(gone: (insets.leading + clear) / 2, clear: clear)
    }

    /// Lume grows a focused programme by 4 percent, which on a five-hour programme is 75 points each side, over the
    /// tile before it (Georgs on build 9, "No Pr…" showing through the focused glass). Here it grows by at most half
    /// the gap between tiles less a point, whatever its length; short tiles keep Lume's 4 percent.
    static func focusScale(width: CGFloat, rowSpacing: CGFloat, lumeScale: CGFloat = 1.04) -> CGFloat {
        guard width > 0 else { return 1 }
        let maxGrowth = max(0, (rowSpacing - 2) / 2)
        return min(lumeScale, 1 + 2 * maxGrowth / width)
    }

    /// Lume's keep-the-focused-row-visible (Apple TV) with its rows `topRoom` down: a row above the view scrolls to
    /// where the first row sits at rest, a row below until it ends at the readable area's bottom.
    static func rowScrollTarget(row: Int, currentY: CGFloat, viewportHeight: CGFloat, rowHeight: CGFloat,
                                rowSpacing: CGFloat, topRoom: CGFloat) -> CGFloat {
        let top = CGFloat(row) * (rowHeight + rowSpacing)
        if top < currentY {
            return top
        }
        let bottom = topRoom + top + rowHeight
        if bottom > currentY + viewportHeight {
            return bottom - viewportHeight
        }
        return currentY
    }

    /// How far down the guide scrolls: until the last row ends at the readable area's bottom.
    static func maxScrollY(rows: Int, viewportHeight: CGFloat, rowHeight: CGFloat, rowSpacing: CGFloat,
                           topRoom: CGFloat) -> CGFloat {
        let content = topRoom + CGFloat(rows) * (rowHeight + rowSpacing) - rowSpacing
        return max(0, content - viewportHeight)
    }

    /// Apple TV: the focused channel's white highlight, inset inside the sidebar.
    static let tvHighlightInset: CGFloat = 8

    static func tvHighlightWidth(columnWidth: CGFloat) -> CGFloat {
        let insets = sidebarInsets(tv: true)
        return max(0, columnWidth - insets.leading - insets.trailing - 2 * tvHighlightInset)
    }

    static var tvHighlightLeading: CGFloat {
        sidebarInsets(tv: true).leading + tvHighlightInset
    }
}
