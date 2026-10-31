#if os(iOS)
    import Observation
    import UIKit

    /// Lume GF: the size of the window the app shows in, for code that sized by the kind of device. Both of the
    /// iPhone Duo's displays are an iPhone, and folding or unfolding it resizes the window mid-session.
    @MainActor
    enum GFWindowSize {
        /// The foreground window scene's shorter side, in points; nil before there is one. A SwiftUI view that reads it
        /// redraws when the window resizes (subtitles on screen while the iPhone Duo folds or unfolds).
        static var shortSide: CGFloat? {
            _ = changes.count
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .filter { $0.session.role == .windowApplication }
            scenes.forEach(changes.watch)
            // the scene's own bounds: there is always one, where its key window can be missing mid-fold
            guard let bounds = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?
                .coordinateSpace.bounds, !bounds.isEmpty else { return nil }
            return min(bounds.width, bounds.height)
        }

        /// Whether the window stands upright with a safe-area inset at one side: the iPhone Duo's outer screen keeps
        /// a column down its side for the clock, the signal and the camera (`GFTabletopLayout.controlsUseWholeWidth`).
        /// Read from the window itself: a SwiftUI view that ignores the safe area is told it has none. Redraws a
        /// SwiftUI view that reads it when the window resizes or turns.
        static var hasSideColumn: Bool {
            _ = changes.count
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .filter { $0.session.role == .windowApplication }
            scenes.forEach(changes.watch)
            guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
                  let window = scene.keyWindow ?? scene.windows.first else { return false }
            let insets = window.safeAreaInsets
            return GFTabletopLayout.controlsUseWholeWidth(size: window.bounds.size, leading: insets.left,
                                                          trailing: insets.right)
        }

        /// The window's size and side insets, for the diagnostic report.
        static var sideColumnDescription: String {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let window = scenes.compactMap({ $0.keyWindow ?? $0.windows.first }).first else { return "no window" }
            let (size, insets) = (window.bounds.size, window.safeAreaInsets)
            return "\(Int(size.width))x\(Int(size.height)), insets \(Int(insets.left)) and \(Int(insets.right))"
        }

        private static let changes = Changes()

        /// Counts the window scenes' geometry changes (a fold or unfold, a turn), for SwiftUI to observe. Fileprivate:
        /// @Observable's conformance is written outside the enum.
        @MainActor
        @Observable
        fileprivate final class Changes {
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
