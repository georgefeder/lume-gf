import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

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
}
