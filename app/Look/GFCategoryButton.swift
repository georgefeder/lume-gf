import SwiftUI

#if os(iOS)
    extension View {
        /// Lume GF: Live TV's category picker as a floating glass button above the tab bar (Georgs on build 21: the
        /// grey strip it sat in under the toolbar changed the background and crowded the top). In the guide it floats
        /// over the programmes: Lume 2.4's channel column stops at a bottom inset while its grid runs on under it, so
        /// an inset cut the last channel off above the button. A list keeps clear of it (a bottom safe-area inset), so
        /// its last row ends above it. `guide` nil: Live TV's own List/Guide setting.
        func gfCategoryButton(sections: [LiveTVSection], selection: Binding<LiveTVSection?>, guide: Bool? = nil)
            -> some View {
            modifier(GFCategoryButtonPlacement(sections: sections, selection: selection, guide: guide))
        }
    }

    private struct GFCategoryButtonPlacement: ViewModifier {
        let sections: [LiveTVSection]
        @Binding var selection: LiveTVSection?
        let guide: Bool?
        @AppStorage(LiveTVLayoutMode.storageKey) private var layoutModeRaw = LiveTVLayoutMode.defaultMode.rawValue

        private var isGuide: Bool {
            guide ?? ((LiveTVLayoutMode(rawValue: layoutModeRaw) ?? .defaultMode) == .guide)
        }

        @ViewBuilder
        func body(content: Content) -> some View {
            if isGuide {
                content.overlay(alignment: .bottom) { button }
            } else {
                content.safeAreaInset(edge: .bottom, spacing: 0) { button }
            }
        }

        private var button: some View {
            CategoryBar(sections: sections, selectedSection: $selection)
                .padding(.bottom, 10)
        }
    }
#endif
