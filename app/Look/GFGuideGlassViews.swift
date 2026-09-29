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

    /// Lume's catch-up clock beside the name: on Apple TV. The iPhone's 136-point column would give it a third of the
    /// name's width, so there it follows the badges (`gfCatchupSymbol`).
    var gfCatchupBesideName: Bool {
        GFGuideGlass.isTV
    }

    var gfCatchupSymbol: GFBadgeSymbol? {
        guard row.catchupCapable, !gfCatchupBesideName else { return nil }
        return GFBadgeSymbol(systemName: "clock.arrow.circlepath", color: .blue,
                             accessibilityLabel: Text("Catch-up available"))
    }

    /// The iPhone's narrow column: names step their text size down before a word breaks.
    var gfFitsWords: Bool {
        !GFGuideGlass.isTV
    }
}

/// The sidebar panel's outline: inset from the column, round-cornered, running on past the bottom edge (where the
/// guide's fade ends it). The glass is drawn in it and the channel rows are clipped to it, so a row scrolling up
/// slides under the panel's top edge instead of showing beside its corner.
nonisolated struct GFGuideSidebarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let tv = GFGuideGlass.isTV
        let insets = GFGuideGlass.sidebarInsets(tv: tv)
        let radius = GFGuideGlass.sidebarCornerRadius(tv: tv)
        let panel = CGRect(x: rect.minX + insets.leading, y: rect.minY + insets.top,
                           width: max(0, rect.width - insets.leading - insets.trailing),
                           height: max(0, rect.height - insets.top + radius))
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: panel)
    }
}

/// The guide's channel sidebar: one floating panel of Liquid Glass (Lume's `glassEffectCompat`: its frosted material
/// before iOS/tvOS 26). It runs on past the bottom edge, where the guide's fade ends it.
struct GFGuideSidebarPanel: View {
    var body: some View {
        Color.clear.glassEffectCompat(.regular, in: GFGuideSidebarShape())
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
            // on into the side margins, where the programmes run on (the Apple TV's overscan)
            .ignoresSafeArea(.container, edges: .horizontal)
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
