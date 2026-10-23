#if os(iOS)
    import UIKit

    /// Lume GF: the size of the window the app shows in, for code that sized by the kind of device. Both of the
    /// iPhone Duo's displays are an iPhone, and folding or unfolding it resizes the window mid-session.
    @MainActor
    enum GFWindowSize {
        /// The foreground window's shorter side, in points; nil before there is one.
        static var shortSide: CGFloat? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let window = scenes.first { $0.activationState == .foregroundActive }?.keyWindow ?? scenes.first?.keyWindow
            guard let bounds = window?.bounds, !bounds.isEmpty else { return nil }
            return min(bounds.width, bounds.height)
        }
    }
#endif
