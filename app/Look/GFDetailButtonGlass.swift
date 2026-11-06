import SwiftUI

extension View {
    /// Lume GF: the film and series pages' own glass circle under each toolbar button (back, download, watched,
    /// favourite), below iOS 26 only. iOS 26 puts toolbar buttons on Liquid Glass itself, and the circle drew glass on
    /// glass, buttons inside buttons (Georgs, 6 Nov, the iPhone Duo); with plain icons the system's own pill is the only
    /// glass, and it can carry the buttons from one screen to the next as iOS does in its own apps.
    @ViewBuilder func gfDetailButtonGlass() -> some View {
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            self
        } else {
            foregroundStyle(.white)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 0.5))
        }
    }
}
