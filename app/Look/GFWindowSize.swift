#if os(iOS)
    import Observation
    import UIKit

    /// Lume GF: the size of the window the app shows in, for code that sized by the kind of device. Both of the
    /// iPhone Duo's displays are an iPhone, and folding or unfolding it resizes the window mid-session.
    @MainActor
    enum GFWindowSize {
        /// The foreground window's shorter side, in points; nil before there is one. A SwiftUI view that reads it
        /// redraws when the window resizes (subtitles on screen while the iPhone Duo folds or unfolds).
        static var shortSide: CGFloat? {
            _ = changes.count
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            scenes.forEach(changes.watch)
            let window = scenes.first { $0.activationState == .foregroundActive }?.keyWindow ?? scenes.first?.keyWindow
            guard let bounds = window?.bounds, !bounds.isEmpty else { return nil }
            return min(bounds.width, bounds.height)
        }

        private static let changes = Changes()

        /// Counts the window scenes' geometry changes (a fold or unfold, a turn), for SwiftUI to observe.
        @MainActor
        @Observable
        private final class Changes {
            private(set) var count = 0
            /// One observation per scene; a scene that goes away takes its entry with it.
            private let watched = NSMapTable<UIWindowScene, NSKeyValueObservation>.weakToStrongObjects()

            func watch(_ scene: UIWindowScene) {
                guard watched.object(forKey: scene) == nil else { return }
                let observation = scene.observe(\.effectiveGeometry) { @Sendable _, _ in
                    Task { @MainActor in GFWindowSize.changes.count &+= 1 }
                }
                watched.setObject(observation, forKey: scene)
            }
        }
    }
#endif
