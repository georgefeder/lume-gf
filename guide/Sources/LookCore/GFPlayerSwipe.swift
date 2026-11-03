import CoreGraphics

/// The player's level swipes (Georgs, 3 Nov: "swipe on the left side up and down its brightness, right is volume,
/// with a liquid glass pill at the top showing the percentage"): which level a drag sets, and to what.
nonisolated enum GFPlayerSwipe {
    enum Kind: Equatable, Sendable {
        case brightness, volume
    }

    /// The bands along the top and bottom edge where a drag is left alone: iOS starts Notification Centre, Control
    /// Centre and the home gesture there.
    static let edgeBand: CGFloat = 40
    /// How far a drag goes before it counts, and how much more up or down than sideways it must go.
    static let threshold: CGFloat = 10
    static let verticalBias: CGFloat = 1.4
    /// A swipe over this share of the player's height takes a level from none to all.
    static let fullSwipe: CGFloat = 0.6

    /// The level a drag that began at `start` on a `size` player sets: brightness on the left half, volume on the
    /// right; nil from the edge bands.
    static func kind(start: CGPoint, size: CGSize) -> Kind? {
        guard size.width > 0, size.height > 0, start.y >= edgeBand, start.y <= size.height - edgeBand else {
            return nil
        }
        return start.x < size.width / 2 ? .brightness : .volume
    }

    /// Whether a drag of `translation` so far is a level swipe: past the threshold and mostly up or down (a
    /// sideways one is left for the player).
    static func isVertical(_ translation: CGSize) -> Bool {
        let (dx, dy) = (abs(translation.width), abs(translation.height))
        return max(dx, dy) >= threshold && dy > dx * verticalBias
    }

    /// The level after a drag of `dy` points (down positive) from `start`, on a player `height` tall: up raises it.
    static func level(from start: Double, dy: CGFloat, height: CGFloat) -> Double {
        guard height > 0 else { return start }
        return min(1, max(0, start - Double(dy / (height * fullSwipe))))
    }

    static func percent(_ level: Double) -> Int {
        Int((min(1, max(0, level)) * 100).rounded())
    }

    /// The SF Symbol for a level: a small or a full sun; a speaker with no, one, two or three waves.
    static func symbol(_ kind: Kind, level: Double) -> String {
        switch kind {
        case .brightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            switch percent(level) {
            case 0: return "speaker.slash.fill"
            case ..<34: return "speaker.wave.1.fill"
            case ..<67: return "speaker.wave.2.fill"
            default: return "speaker.wave.3.fill"
            }
        }
    }
}
