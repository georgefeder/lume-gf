import SwiftUI

#if os(iOS)
    extension View {
        /// Lume GF: Live TV's category picker as a floating glass button above the tab bar (Georgs on build 21: the
        /// grey strip it sat in under the toolbar changed the background and crowded the top). The content keeps
        /// clear of it (a bottom safe-area inset), so a list's last row and the guide's bottom fade end above it.
        func gfCategoryButton(sections: [LiveTVSection], selection: Binding<LiveTVSection?>) -> some View {
            safeAreaInset(edge: .bottom, spacing: 0) {
                CategoryBar(sections: sections, selectedSection: selection)
                    .padding(.bottom, 10)
            }
        }
    }
#endif
