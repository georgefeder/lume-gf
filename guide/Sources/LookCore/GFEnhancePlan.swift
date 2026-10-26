/// Which channels the Apple TV upscales, and by how much (Georgs, 26 Oct 2026: SD and 720p "definitely whack", 1080p
/// and 4K fine). Apple's low-latency super resolution says which factors it supports for a frame size; this picks one.
/// The upscaling itself is `GFEnhancer`, behind Settings ▸ KSPlayer ▸ "Enhance SD & 720p" (`settingKey`).
nonisolated enum GFEnhancePlan {
    /// The Apple TV setting, off until switched on.
    static let settingKey = "gf.player.enhanceLowRes"
    /// Frames with this many lines or more are left alone: 1080p and up already look fine.
    static let fullHDLines = 1000
    /// The biggest picture worth making: the Apple TV's 4K output.
    static let maximumWidth = 3840, maximumHeight = 2160

    /// The factor for a `width`×`height` frame, from the factors the upscaler supports for it: the largest whose
    /// result still fits 4K (SD 2×, 720p 3×). Nil for 1080p and up, or when none fits.
    static func scale(width: Int, height: Int, supported: [Float]) -> Float? {
        guard width > 0, height > 0, height < fullHDLines else { return nil }
        return supported.filter { factor in
            let size = scaled(width: width, height: height, by: factor)
            return factor > 1 && size.width <= maximumWidth && size.height <= maximumHeight
        }.max()
    }

    /// A frame's size at `factor`, in whole pixels, even (4:2:0 frames need even sizes).
    static func scaled(width: Int, height: Int, by factor: Float) -> (width: Int, height: Int) {
        func even(_ value: Int, _ factor: Float) -> Int {
            Int((Float(value) * factor / 2).rounded()) * 2
        }
        return (even(width, factor), even(height, factor))
    }
}
