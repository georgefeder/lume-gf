import CoreGraphics

/// Subtitle size by the size of the screen the player is on (Georgs, 23 Oct 2026: on the iPhone Duo). Lume sizes
/// subtitles by the kind of device, 16 pt on an iPhone and 26 pt on an iPad, and both of the iPhone Duo's displays are
/// an iPhone: its 7.6" inner display got a phone's subtitles.
nonisolated enum GFSubtitleScale {
    /// Lume's standard sizes.
    static let phoneSize: CGFloat = 16
    static let tabletSize: CGFloat = 26
    /// The short sides those sizes belong to: the largest iPhone's (440 pt, the Pro Max) and the iPad mini's (744 pt).
    static let phoneShortSide: CGFloat = 440
    static let tabletShortSide: CGFloat = 744

    /// An iPhone's standard subtitle size on a screen whose short side is `shortSide` points: a phone's up to a
    /// phone's short side, an iPad's from an iPad mini's, in proportion between (the iPhone Duo's inner display gets
    /// about 24 pt). Unknown: a phone's.
    static func phonePointSize(shortSide: CGFloat?) -> CGFloat {
        guard let shortSide, shortSide > phoneShortSide else { return phoneSize }
        let share = min(1, (shortSide - phoneShortSide) / (tabletShortSide - phoneShortSide))
        return (phoneSize + share * (tabletSize - phoneSize)).rounded()
    }

    /// Lume's iPhone subtitle preview canvas (720 x 405), grown with the subtitle size so the preview keeps the
    /// proportion between the picture and its subtitles.
    static func phonePreviewCanvas(pointSize: CGFloat) -> CGSize {
        let grow = max(1, pointSize / phoneSize)
        return CGSize(width: 720 * grow, height: 405 * grow)
    }
}
