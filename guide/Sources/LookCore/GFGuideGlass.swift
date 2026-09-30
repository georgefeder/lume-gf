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
    /// false puts the grid beside the sidebar again: nothing slides under the glass (if the Apple TV stutters).
    static let slidesUnderSidebar = true

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
        tv ? Insets(leading: 0, trailing: 16, top: -16) : Insets(leading: 6, trailing: 6, top: 4)
    }

    /// Lume's own panel sizes: 36 for its big Apple TV panels, 16 for its glass cards.
    static func sidebarCornerRadius(tv: Bool) -> CGFloat {
        tv ? 36 : 16
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
