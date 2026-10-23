import CoreGraphics

/// The iPhone Duo stood up half folded like a small laptop (Georgs, 23 Oct 2026: "like Netflix"): the picture goes above
/// the fold and the player's controls below it. iOS 27.1 reports the fold as a reserved region of kind `.division`
/// while the phone is partly open; this works out the two areas from it.
nonisolated enum GFTabletopLayout {
    struct Split: Equatable {
        /// Above the fold: the picture.
        var video: CGRect
        /// Below the fold: the controls.
        var panel: CGRect
    }

    /// The least height either side of the fold needs before the player splits: the controls' bars and buttons need
    /// about this much below it.
    static let minimumSide: CGFloat = 320

    /// The split for a view of `size` with the fold areas iOS reports for it (same coordinates), or nil: no fold
    /// across the view (flat open, closed, or folded like a book, where the fold runs top to bottom), or one too near
    /// an edge to leave room on both sides.
    static func split(size: CGSize, folds: [CGRect]) -> Split? {
        guard let fold = folds.first(where: { $0.width > $0.height }),
              fold.minY >= minimumSide, size.height - fold.maxY >= minimumSide
        else { return nil }
        return Split(video: CGRect(x: 0, y: 0, width: size.width, height: fold.minY),
                     panel: CGRect(x: 0, y: fold.maxY, width: size.width, height: size.height - fold.maxY))
    }

    /// A pretend fold across the middle, for test builds' screenshots (no simulator command folds an iPhone Duo).
    static func demoFold(size: CGSize) -> CGRect {
        CGRect(x: 0, y: size.height / 2 - 12, width: size.width, height: 24)
    }
}
