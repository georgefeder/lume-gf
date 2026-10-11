#if os(tvOS)
    import UIKit

    /// Lume GF: where the focus engine's focus is right now, for SwiftUI code whose own focus state can only say "none
    /// of mine".
    @MainActor
    enum GFFocusProbe {
        /// Whether the focused item's centre lies on `rect` (window coordinates, SwiftUI's `.global`) or just past its
        /// edge: a large item only overlapping it (a full-screen view) is not on it. A long swipe hands focus
        /// to a scroll view's fast-scroll index (the dots along its edge) for as long as it runs; that index is no
        /// SwiftUI view, but it is still inside the scroll view (Georgs, 11 Oct: the category rail read it as focus
        /// leaving and snapped back to the selected category).
        static func focusIsInside(_ rect: CGRect) -> Bool {
            guard !rect.isEmpty, let window = keyWindow,
                  let item = UIFocusSystem.focusSystem(for: window)?.focusedItem,
                  let focusedFrame = frame(of: item, in: window)
            else { return false }
            return rect.insetBy(dx: -16, dy: -16).contains(CGPoint(x: focusedFrame.midX, y: focusedFrame.midY))
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
            // the frame is in the space of the container holding the item: the nearest one up the environments
            var environment = item.parentFocusEnvironment
            while let current = environment {
                if let container = current.focusItemContainer {
                    return container.coordinateSpace.convert(item.frame, to: window)
                }
                environment = current.parentFocusEnvironment
            }
            return nil
        }
    }
#endif
