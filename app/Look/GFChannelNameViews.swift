import SwiftUI

/// The badges after a clean name: "● LIVE" (Lume's `LiveBadge`) or the start time, then the quality — Lume's own
/// `StatusCapsule` recipe, grey for everything but LIVE.
struct GFChannelBadges: View {
    let label: GFChannelLabel
    let fontSize: CGFloat
    /// Overrides the grey (the Apple TV guide column passes a darker one on its white focus highlight).
    var neutralTint: Color?
    /// Rows whose focus turns solid white (the Apple TV player's channel browser, the multi-view picker).
    var darkensOnFocus = false
    @Environment(\.isFocused) private var isFocused

    static func hasBadges(_ label: GFChannelLabel) -> Bool {
        label.status != .none || label.quality != nil
    }

    private var tint: Color {
        if let neutralTint { return neutralTint }
        return darkensOnFocus && isFocused ? .black.opacity(0.55) : .secondary
    }

    var body: some View {
        HStack(spacing: fontSize * 0.4) {
            switch label.status {
            case .live:
                LiveBadge(fontSize: fontSize)
            case let .upcoming(start):
                let text = GFChannelLabelTime.badgeText(start: start, now: .now)
                StatusCapsule(fontSize: fontSize, tint: tint) { Text(verbatim: text) }
                    .accessibilityLabel(Text("Starts \(text)"))
            case .none:
                EmptyView()
            }
            if let quality = label.quality {
                StatusCapsule(fontSize: fontSize, tint: tint) { Text(verbatim: quality) }
                    .accessibilityLabel(Text(verbatim: quality))
            }
        }
        .fixedSize()
    }
}

/// A live channel's name as Lume GF shows it: the clean title, the badges (after the name or under it) and, where
/// there is room, the second line. Callers keep their own font and colour for the title. With "Clean Channel Names"
/// off it is exactly the server's name.
struct GFChannelName: View {
    enum BadgePlacement { case trailing, below }

    let raw: String
    let badgeSize: CGFloat
    var placement: BadgePlacement = .below
    var titleLineLimit = 1
    var showsSecondLine = false
    var secondLineFont: Font = .caption
    var neutralTint: Color?
    var darkensOnFocus = false
    @AppStorage(GFChannelNames.settingKey) private var enabled = true

    var body: some View {
        let label = GFChannelNames.label(for: raw, enabled: enabled)
        if !enabled {
            Text(verbatim: raw).lineLimit(titleLineLimit)
        } else {
            VStack(alignment: .leading, spacing: badgeSize * 0.3) {
                if placement == .trailing {
                    HStack(spacing: badgeSize * 0.6) {
                        Text(verbatim: label.title).lineLimit(titleLineLimit)
                        badges(label)
                    }
                } else {
                    Text(verbatim: label.title).lineLimit(titleLineLimit)
                    if GFChannelBadges.hasBadges(label) {
                        badges(label)
                    }
                }
                if showsSecondLine, let second = label.secondLine {
                    Text(verbatim: second)
                        .font(secondLineFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func badges(_ label: GFChannelLabel) -> GFChannelBadges {
        GFChannelBadges(label: label, fontSize: badgeSize, neutralTint: neutralTint, darkensOnFocus: darkensOnFocus)
    }
}
