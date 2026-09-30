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
    /// The panel's top in the rect it is drawn in: in the column `GFGuideGlass.panelTop` (on the Apple TV above the
    /// first channel), or 0 where the view itself already reaches up that far (the glass).
    var top: CGFloat

    func path(in rect: CGRect) -> Path {
        let tv = GFGuideGlass.isTV
        let insets = GFGuideGlass.sidebarInsets(tv: tv)
        let radius = GFGuideGlass.sidebarCornerRadius(tv: tv)
        let panel = CGRect(x: rect.minX + insets.leading, y: rect.minY + top,
                           width: max(0, rect.width - insets.leading - insets.trailing),
                           height: max(0, rect.height - top + radius))
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: panel)
    }
}

/// The guide's channel sidebar: one floating panel of Liquid Glass (Lume's `glassEffectCompat`: its frosted material
/// before iOS/tvOS 26). It runs on past the bottom edge, where the guide's fade ends it.
struct GFGuideSidebarPanel: View {
    /// `GFGuideGlass.panelTop`: the panel's top in the channel column.
    let top: CGFloat

    var body: some View {
        Color.clear
            .glassEffectCompat(.regular, in: GFGuideSidebarShape(top: max(0, top)))
            // the view reaches up as far as its panel does (on the Apple TV above the first channel)
            .padding(.top, min(0, top))
        #if GF_DEMO
            .opacity(GFDemo.noPanel ? 0 : 1)
        #endif
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

/// The Apple TV's fades: its backdrop is the system's gradient, not a colour a strip could match, so the rows
/// themselves fade out to it (a mask on the grid and on the channel rows, never on the glass panel). On the grid it
/// also fades the programmes out under the panel (`underPanel`, from the grid's leading edge: the column's).
struct GFGuideEdgeMask: View {
    let top: CGFloat
    let bottom: CGFloat
    var underPanel: GFGuideGlass.UnderPanel?

    var body: some View {
        // on into the side margins, where the programmes run on (the Apple TV's overscan; the guide's leading edge is
        // beside the category list, never in a margin, so the fade under the panel keeps its place). The channel rows
        // get no second mask: Lume found every extra layer in the Apple TV's scrolling.
        if let underPanel {
            fades
                .mask(alignment: .leading) { GFGuideUnderPanelFade(fade: underPanel) }
                .ignoresSafeArea(.container, edges: .horizontal)
        } else {
            fades.ignoresSafeArea(.container, edges: .horizontal)
        }
    }

    private var fades: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: max(0, top))
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: max(0, bottom))
        }
    }
}

/// How much of the programmes shows across the channel column (black shows): nothing up to the panel's middle, then
/// more and more, all of it from the panel's trailing edge on. `GFGuideGlass.underPanelFade`.
struct GFGuideUnderPanelFade: View {
    let fade: GFGuideGlass.UnderPanel

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: max(0, fade.gone))
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: max(0, fade.clear - fade.gone))
            Rectangle().fill(.black)
        }
    }
}

/// iPhone and iPad: the guide's own background over the programmes under the panel, faded the other way round (it
/// sits between the grid and the glass, so the glass still sees the programmes near its trailing edge). Covers the
/// strip beside the panel and its rounded corners too.
struct GFGuideUnderPanelCover: View {
    let fade: GFGuideGlass.UnderPanel

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(.background).frame(width: max(0, fade.gone))
            Rectangle().fill(.background)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: max(0, fade.clear - fade.gone))
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
}

extension View {
    /// The guide's top and bottom fades on one pane (the grid, the channel rows): Apple TV only, see `GFGuideEdgeMask`.
    /// The grid passes `underPanel` as well.
    @ViewBuilder
    func gfGuideRowFade(top: CGFloat, bottom: CGFloat, underPanel: GFGuideGlass.UnderPanel? = nil) -> some View {
        #if os(tvOS)
            mask { GFGuideEdgeMask(top: top, bottom: bottom, underPanel: underPanel) }
        #else
            self
        #endif
    }

    /// The guide's top and bottom fades over both panes: iPhone and iPad, a strip of the guide's own background.
    @ViewBuilder
    func gfGuideStripFade(top: CGFloat, bottom: CGFloat) -> some View {
        #if os(tvOS)
            self
        #else
            overlay(alignment: .top) { GFGuideEdgeFade(edge: .top, height: top) }
                .overlay(alignment: .bottom) { GFGuideEdgeFade(edge: .bottom, height: bottom) }
        #endif
    }
}

/// The ruler's Now pill: red-tinted glass that is a label, not a control (Lume's interactive tint reacts to input).
struct GFNowPillBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.glassEffectCompat(.tinted(.red), in: Capsule())
    }
}

/// The focused programme on Apple TV: Lume's white focus glass.
struct GFGuideFocusGlass<S: Shape>: View {
    let shape: S

    var body: some View {
        Color.clear.glassEffectCompat(.tintedInteractive(.white), in: shape)
    }
}
