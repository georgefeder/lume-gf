import CoreGraphics

nonisolated enum GFGuideGlass {
    static let slidesUnderSidebar = true
    static var isTV: Bool { false }

    struct Insets: Equatable, Sendable {
        var leading: CGFloat
        var trailing: CGFloat
        var top: CGFloat
    }

    static func contentPad(columnWidth: CGFloat, slidesUnder: Bool = slidesUnderSidebar) -> CGFloat { 0 }
    static func gridLeadingInset(columnWidth: CGFloat, slidesUnder: Bool = slidesUnderSidebar) -> CGFloat { 0 }
    static func visibleSize(measured: CGSize, pad: CGFloat, bottomFade: CGFloat) -> CGSize { .zero }
    static func realizeOrigin(offsetX: CGFloat, pad: CGFloat) -> CGFloat { 0 }
    static func stickyMinX(blockMinX: CGFloat, pad: CGFloat) -> CGFloat { 0 }
    static func bottomFade(safeAreaBottom: CGFloat, rowStride: CGFloat) -> CGFloat { 0 }
    static func topFade(tv: Bool) -> CGFloat { 0 }
    static func sidebarInsets(tv: Bool) -> Insets { Insets(leading: 0, trailing: 0, top: 0) }
    static func sidebarCornerRadius(tv: Bool) -> CGFloat { 0 }
    static let tvHighlightInset: CGFloat = 0
    static func tvHighlightWidth(columnWidth: CGFloat) -> CGFloat { 0 }
    static var tvHighlightLeading: CGFloat { 0 }
}
