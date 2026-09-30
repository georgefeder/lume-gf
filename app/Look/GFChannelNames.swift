import Foundation

/// Lume GF's clean channel names (spec: docs/superpowers/specs/2026-09-29-lume-gf-3-look-design.md, section 1): the
/// setting and the helpers every name site uses. Search, sorting, the Sports Hub's matching and the settings lists keep
/// reading the raw `LiveStream.name`.
nonisolated enum GFChannelNames {
    /// Settings → TV Guide → Clean Channel Names (default on).
    static let settingKey = "gf.cleanChannelNames"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    /// The label for a raw channel name; exactly the raw name when the setting is off.
    static func label(for raw: String, enabled: Bool = isEnabled, now: Date = .now) -> GFChannelLabel {
        enabled ? GFChannelLabel.parse(raw, now: now) : .unchanged(raw)
    }

    /// Text-only places: the player title, the lock screen, navigation titles, the Sports Hub.
    static func title(for raw: String, enabled: Bool = isEnabled) -> String {
        label(for: raw, enabled: enabled).title
    }
}
