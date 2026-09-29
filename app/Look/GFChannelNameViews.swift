import SwiftUI

/// The badges after a clean name: "● LIVE" (Lume's `LiveBadge`) or the start time, then the quality — Lume's own
/// `StatusCapsule` recipe, grey for everything but LIVE. Where the row is narrow (the iPhone guide's channel column)
/// SwiftUI's `ViewThatFits` takes the first form that fits: all badges, then without the quality, then the short
/// form (LIVE's red dot alone, "15:55" or only "Sun" for a start).
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
        ViewThatFits(in: .horizontal) {
            badges(short: false, quality: true)
            badges(short: false, quality: false)
            badges(short: true, quality: false)
        }
    }

    private func badges(short: Bool, quality: Bool) -> some View {
        HStack(spacing: fontSize * 0.4) {
            status(short: short)
            if quality, let text = label.quality {
                StatusCapsule(fontSize: fontSize, tint: tint) { Text(verbatim: text) }
                    .accessibilityLabel(Text(verbatim: text))
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func status(short: Bool) -> some View {
        switch label.status {
        case .live:
            if short {
                StatusCapsule(fontSize: fontSize, tint: .red) {
                    Circle().fill(.red).frame(width: fontSize * 0.55, height: fontSize * 0.55)
                }
                .accessibilityLabel(Text("Live"))
            } else {
                LiveBadge(fontSize: fontSize)
            }
        case let .upcoming(start):
            let text = short ? GFChannelLabelTime.compactBadgeText(start: start, now: .now)
                : GFChannelLabelTime.badgeText(start: start, now: .now)
            StatusCapsule(fontSize: fontSize, tint: tint) { Text(verbatim: text) }
                .accessibilityLabel(Text("Starts \(GFChannelLabelTime.badgeText(start: start, now: .now))"))
        case .none:
            EmptyView()
        }
    }
}

/// A small symbol after the badges: the iPhone guide's catch-up clock, which Lume puts beside the name, where it
/// would take a third of the name's width.
struct GFBadgeSymbol {
    let systemName: String
    let color: Color
    let accessibilityLabel: Text
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
    /// Shown after the badges (placement `.below`).
    var badgeSymbol: GFBadgeSymbol?
    /// A narrow column (the iPhone guide): the title steps its text size down, at most twice, until every word fits
    /// on a line, before a word would break.
    var fitsWords = false
    @AppStorage(GFChannelNames.settingKey) private var enabled = true
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The caller's text size and up to two steps smaller.
    static func fittingTypeSizes(from size: DynamicTypeSize) -> [DynamicTypeSize] {
        let all = DynamicTypeSize.allCases
        guard let index = all.firstIndex(of: size) else { return [size] }
        return (0 ... 2).compactMap { step in index - step >= 0 ? all[index - step] : nil }
    }

    var body: some View {
        let label = GFChannelNames.label(for: raw, enabled: enabled)
        if !enabled {
            VStack(alignment: .leading, spacing: badgeSize * 0.3) {
                title(raw)
                if let badgeSymbol { symbol(badgeSymbol) }
            }
        } else {
            VStack(alignment: .leading, spacing: badgeSize * 0.3) {
                if placement == .trailing {
                    HStack(spacing: badgeSize * 0.6) {
                        title(label.title)
                        badges(label)
                    }
                } else {
                    title(label.title)
                    if GFChannelBadges.hasBadges(label) || badgeSymbol != nil {
                        HStack(spacing: badgeSize * 0.4) {
                            if GFChannelBadges.hasBadges(label) { badges(label) }
                            if let badgeSymbol { symbol(badgeSymbol) }
                        }
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

    @ViewBuilder
    private func title(_ text: String) -> some View {
        if fitsWords {
            let sizes = Self.fittingTypeSizes(from: typeSize)
            ViewThatFits(in: .horizontal) {
                wholeWords(text).dynamicTypeSize(sizes[0])
                wholeWords(text).dynamicTypeSize(sizes[min(1, sizes.count - 1)])
                Text(verbatim: text).lineLimit(titleLineLimit).dynamicTypeSize(sizes[sizes.count - 1])
            }
        } else {
            Text(verbatim: text).lineLimit(titleLineLimit)
        }
    }

    /// The title, measured by its widest word: `ViewThatFits` takes it only where every word fits on a line.
    private func wholeWords(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .leading) {
                ForEach(Array(text.split(separator: " ").enumerated()), id: \.offset) { word in
                    Text(verbatim: String(word.element)).fixedSize()
                }
            }
            .frame(height: 0)
            .hidden()
            Text(verbatim: text)
                .lineLimit(titleLineLimit)
                .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
    }

    private func symbol(_ symbol: GFBadgeSymbol) -> some View {
        Image(systemName: symbol.systemName)
            .font(.system(size: badgeSize * 1.1, weight: .semibold))
            .foregroundStyle(symbol.color)
            .accessibilityLabel(symbol.accessibilityLabel)
    }

    private func badges(_ label: GFChannelLabel) -> GFChannelBadges {
        GFChannelBadges(label: label, fontSize: badgeSize, neutralTint: neutralTint, darkensOnFocus: darkensOnFocus)
    }
}
