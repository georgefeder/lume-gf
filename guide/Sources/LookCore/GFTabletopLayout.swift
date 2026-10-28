import CoreGraphics
import Foundation

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

    /// The picture above the fold, standing on it: as big as its shape fits in `video`, centred across, its reflection
    /// starting faintly below the crease (Georgs, 24 Oct, on Netflix's). All of `video` while the shape is unknown.
    static func picture(in video: CGRect, aspect: CGFloat?) -> CGRect {
        guard let aspect, aspect > 0 else { return video }
        let height = min(video.height, video.width / aspect)
        let width = min(video.width, height * aspect)
        return CGRect(x: video.midX - width / 2, y: video.maxY - height, width: width, height: height)
    }

    /// How long the reflection below the fold is, as a share of the picture's height, at a hinge angle in degrees (0
    /// closed, 180 flat; nil unknown: 1). What a mirror lying where the lower half lies would show of the upper half to
    /// someone in front of the phone (eye 5 heights of the upper half in front of the fold and 3.75 above the table):
    /// about as long as the picture when it stands upright, longer as it leans forward, shorter as it opens, gone near
    /// flat (Georgs, 24 Oct: Netflix's "stretches depending on the hinge, constantly reacts").
    /// The longest the reflection gets, leaning far forward: the glow is drawn this long and stretched to the hinge's.
    static let longestStretch: CGFloat = 1.6

    static func reflectionStretch(hingeDegrees: Double?) -> CGFloat {
        guard let hingeDegrees else { return 1 }
        let angle = hingeDegrees * .pi / 180
        let eyeOut = 5.0, eyeUp = 3.75
        let reach = eyeOut + eyeUp * (cos(angle) - eyeOut) / (eyeUp + sin(angle))
        return min(longestStretch, max(0.15, CGFloat(reach)))
    }

    /// A pretend fold across the middle, for test builds' screenshots (no simulator command folds an iPhone Duo).
    static func demoFold(size: CGSize) -> CGRect {
        CGRect(x: 0, y: size.height / 2 - 12, width: size.width, height: 24)
    }
}
