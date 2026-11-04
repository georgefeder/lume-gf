import SwiftUI

extension View {
    /// Lume GF: a list of categories opens where the chosen one is, in the middle, instead of at the top (Georgs, 4
    /// Nov: picking a category far down, then opening the list again, it was back at the top). Only on opening: a tap
    /// in the list leaves it where it is. iPhone and iPad; the Apple TV's lists follow the focus.
    @ViewBuilder func gfShowsSelection<ID: Hashable>(_ id: ID?, in proxy: ScrollViewProxy) -> some View {
        #if os(iOS)
            onAppear {
                guard let id else { return }
                // after the list's first layout: before it, the row to scroll to is not there yet
                DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
            }
        #else
            self
        #endif
    }
}
