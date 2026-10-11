#if os(tvOS)
    import UIKit

    /// Lume GF: where the focus engine's focus is right now, for SwiftUI code whose own focus state can only say "none
    /// of mine".
    @MainActor
    enum GFFocusProbe {
        /// Whether the focused item lies on `rect` (window coordinates, SwiftUI's `.global`). A long swipe hands focus
        /// to a scroll view's fast-scroll index (the dots along its edge) for as long as it runs; that index is no
        /// SwiftUI view, but it is still inside the scroll view (Georgs, 11 Oct: the category rail read it as focus
        /// leaving and snapped back to the selected category).
        static func focusIsInside(_ rect: CGRect) -> Bool {
            guard !rect.isEmpty, let window = keyWindow,
                  let item = UIFocusSystem.focusSystem(for: window)?.focusedItem,
                  let frame = frame(of: item, in: window)
            else { return false }
            return rect.intersects(frame)
        }

        private static var keyWindow: UIWindow? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
        }

        private static func frame(of item: UIFocusItem, in window: UIWindow) -> CGRect? {
            if let view = item as? UIView {
                return view.convert(view.bounds, to: window)
            }
            guard let space = item.parentFocusEnvironment?.focusItemContainer?.coordinateSpace else { return nil }
            return space.convert(item.frame, to: window)
        }
    }
#endif
