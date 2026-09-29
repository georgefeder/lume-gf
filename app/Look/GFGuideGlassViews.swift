import SwiftUI

extension EPGChannelCell {
    /// Lume's badge sizes: 17 pt on Apple TV, 11 on iPhone/iPad.
    var gfBadgeSize: CGFloat {
        #if os(tvOS)
            17
        #else
            11
        #endif
    }

    /// Grey badges turn dark on the Apple TV's white focus highlight (the guide's focus is virtual, so the cell says
    /// so itself).
    var gfBadgeTint: Color? {
        #if os(tvOS)
            isFocused ? .black.opacity(0.55) : nil
        #else
            nil
        #endif
    }
}

/// The guide's channel sidebar: one floating panel of Liquid Glass (Lume's `glassEffectCompat`: its frosted material
/// before iOS/tvOS 26). It runs on past the bottom edge, where the guide's fade ends it.
struct GFGuideSidebarPanel: View {
    var body: some View {
        let tv = GFGuideGlass.isTV
        let insets = GFGuideGlass.sidebarInsets(tv: tv)
        let radius = GFGuideGlass.sidebarCornerRadius(tv: tv)
        Color.clear
            .glassEffectCompat(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .padding(.leading, insets.leading)
            .padding(.trailing, insets.trailing)
            .padding(.top, insets.top)
            .padding(.bottom, -radius)
    }
}

/// The fade at the guide's top and bottom edges: both panes end on the same line (the Apple TV's bottom row).
struct GFGuideEdgeFade: View {
    enum Edge { case top, bottom }

    let edge: Edge
    let height: CGFloat

    /// The guide's own background (SwiftUI's background style, on every platform), faded by a gradient. The mask sits
    /// on this small strip only, never on the scrolling grid.
    var body: some View {
        Rectangle()
            .fill(.background)
            .mask(LinearGradient(colors: edge == .top ? [.black, .clear] : [.clear, .black],
                                 startPoint: .top, endPoint: .bottom))
            .frame(height: max(0, height))
            .allowsHitTesting(false)
    }
}

/// The focused programme on Apple TV: Lume's white focus glass.
struct GFGuideFocusGlass<S: Shape>: View {
    let shape: S

    var body: some View {
        Color.clear.glassEffectCompat(.tintedInteractive(.white), in: shape)
    }
}
