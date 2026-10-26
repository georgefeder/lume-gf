/// Which channels the Apple TV upscales, and by how much (Georgs, 26 Oct 2026: SD and 720p "definitely whack", 1080p
/// and 4K fine). Apple's low-latency super resolution says which factors it supports for a frame size; this picks one.
/// The upscaling itself is `GFEnhancer`, behind Settings ▸ KSPlayer ▸ "Enhance SD & 720p" (`settingKey`).
nonisolated enum GFEnhancePlan {
    /// The Apple TV setting, off until switched on.
    static let settingKey = "gf.player.enhanceLowRes"
    /// Frames with this many lines or more are left alone: 1080p and up already look fine.
    static let fullHDLines = 1000
    /// Frames this wide or wider are left alone too: a 1080p film letterboxed to 1920x800 is already full HD.
    static let fullHDColumns = 1800
    /// The biggest picture worth making: the Apple TV's 4K output.
    static let maximumWidth = 3840, maximumHeight = 2160

    /// SD and 720p: fewer lines and columns than full HD.
    static func isBelowFullHD(width: Int, height: Int) -> Bool {
        width > 0 && height > 0 && height < fullHDLines && width < fullHDColumns
    }

    /// The factor for a `width`×`height` frame, from the factors the upscaler supports for it: the largest whose
    /// result still fits 4K (SD and 720p up to 3×). Nil for full HD and up, or when none fits.
    static func scale(width: Int, height: Int, supported: [Float]) -> Float? {
        guard isBelowFullHD(width: width, height: height) else { return nil }
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

    // MARK: - Pixel formats (Core Video's four-character codes)

    /// 8-bit 4:2:0 in two planes ('420v', '420f') and three ('y420', KSPlayer's own channels, and 'f420').
    static let videoRange420BiPlanar: UInt32 = 0x3432_3076, fullRange420BiPlanar: UInt32 = 0x3432_3066
    static let videoRange420Planar: UInt32 = 0x7934_3230, fullRange420Planar: UInt32 = 0x6634_3230

    /// The format to hand the upscaler, or ask it for, with a `source` frame, from the formats it `offers`: 8-bit 4:2:0
    /// only (KSPlayer takes a 10-bit frame for HDR and would switch the TV's mode for an SD channel), the source's own
    /// if offered, else the source's range (video range for anything else), two planes before three. Nil when it
    /// offers no 8-bit 4:2:0 format.
    static func format(for source: UInt32, from offers: [UInt32]) -> UInt32? {
        let fullRange = source == fullRange420BiPlanar || source == fullRange420Planar
        let video = [videoRange420BiPlanar, videoRange420Planar], full = [fullRange420BiPlanar, fullRange420Planar]
        let eightBit = fullRange ? full + video : video + full
        return ([source] + eightBit).first { eightBit.contains($0) && offers.contains($0) }
    }

    /// A four-character code as text ("420v"), for the diagnostic report.
    static func name(of format: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: format >> $0) }
        guard bytes.allSatisfy({ (0x20 ... 0x7E).contains($0) }) else { return String(format) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
