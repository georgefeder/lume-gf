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

    static func visibleSize(measured: CGSize, pad: CGFloat, bottomFade: CGFloat) -> CGSize {
        CGSize(width: max(0, measured.width - pad), height: max(0, measured.height - bottomFade))
    }

    /// The timeline x at the scroll area's leading edge (under the sidebar), for the realise window.
    static func realizeOrigin(offsetX: CGFloat, pad: CGFloat) -> CGFloat {
        offsetX - pad
    }

    /// A programme's leading edge measured from the sidebar's edge, which is what Lume's sticky titles expect.
    static func stickyMinX(blockMinX: CGFloat, pad: CGFloat) -> CGFloat {
        blockMinX - pad
    }

    /// Through the safe area (the TV's overscan, the iPhone's tab bar) and half a row more.
    static func bottomFade(safeAreaBottom: CGFloat, rowStride: CGFloat) -> CGFloat {
        max(0, safeAreaBottom) + rowStride / 2
    }

    static func topFade(tv: Bool) -> CGFloat {
        tv ? 18 : 10
    }

    static func sidebarInsets(tv: Bool) -> Insets {
        tv ? Insets(leading: 0, trailing: 16, top: 2) : Insets(leading: 6, trailing: 6, top: 4)
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
