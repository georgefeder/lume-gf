import Foundation

/// A live channel's name as Lume GF shows it (spec: docs/superpowers/specs/2026-09-29-lume-gf-3-look-design.md):
/// the name without its quality word, an optional second line, the quality badge and a live/upcoming status.
/// Our server writes ordinary names ("BBC One FHD", organise.py) and event slots ("🔴 LIVE 20:00 · Arsenal v Chelsea ·
/// Premier League · FHD", events.py `pretty()`); anything else is shown exactly as written.
nonisolated struct GFChannelLabel: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case none
        case live
        /// Starts at this moment (the server's Riga time, resolved).
        case upcoming(start: Date)
    }

    var title: String
    var secondLine: String?
    var quality: String?
    var status: Status

    static let qualityWords: Set<String> = ["4K", "UHD", "FHD", "HD", "SD", "RAW"]

    static func unchanged(_ raw: String) -> GFChannelLabel {
        GFChannelLabel(title: raw, secondLine: nil, quality: nil, status: .none)
    }

    static func parse(_ raw: String, now: Date = .now,
                      serverTimeZone: TimeZone = GFChannelLabelTime.serverTimeZone) -> GFChannelLabel {
        guard let kind = eventKind(raw) else { return parseOrdinary(raw) }
        return parseEvent(raw, kind: kind, now: now, serverTimeZone: serverTimeZone) ?? unchanged(raw)
    }

    /// A narrow column's last resort, once no text size fits the title on its lines (the iPhone guide): one word per
    /// line, so a word too wide shrinks instead of breaking (Georgs on build 16: "BLOOMBER / G"); more words than lines
    /// are split where the lines come out most even, to shrink together (before build 23: "Sky / Sports…").
    static func lastResortLines(_ title: String, lineLimit: Int) -> (text: String, lineLimit: Int) {
        let words = title.split(separator: " ").map(String.init)
        guard !words.isEmpty, lineLimit > 0 else { return (title, lineLimit) }
        guard words.count > lineLimit else { return (words.joined(separator: "\n"), words.count) }
        let longest = { (lines: [String]) in lines.map(\.count).max() ?? 0 }
        let even = splits(words[...], into: lineLimit).min { longest($0) < longest($1) } ?? [title]
        return (even.joined(separator: "\n"), lineLimit)
    }

    /// The ways a narrow column tries to set a title, in order: on 1 to `lineLimit` lines, fewer lines first, then the
    /// longest first line (where natural wrapping fits, it comes first). At most 24.
    static func lineSplits(_ title: String, lineLimit: Int) -> [[String]] {
        let words = title.split(separator: " ").map(String.init)
        guard !words.isEmpty, lineLimit > 0 else { return [[title.trimmingCharacters(in: .whitespaces)]] }
        let all = (1 ... min(lineLimit, words.count)).flatMap { splits(words[...], into: $0) }
        return Array(all.prefix(24))
    }

    /// `words` in order on exactly `lines` lines, the longest first line first.
    private static func splits(_ words: ArraySlice<String>, into lines: Int) -> [[String]] {
        guard lines > 1 else { return [[words.joined(separator: " ")]] }
        var result: [[String]] = []
        for count in stride(from: words.count - lines + 1, through: 1, by: -1) {
            let first = words.prefix(count).joined(separator: " ")
            result += splits(words.dropFirst(count), into: lines - 1).map { [first] + $0 }
        }
        return result
    }

    /// "BBC One FHD" → "BBC One" + FHD. Nothing else is touched (a provider prefix like "AR| " stays).
    static func parseOrdinary(_ raw: String) -> GFChannelLabel {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard let space = name.lastIndex(of: " ") else { return unchanged(raw) }
        let word = String(name[name.index(after: space)...])
        let rest = name[..<space].trimmingCharacters(in: .whitespaces)
        guard qualityWords.contains(word), !rest.isEmpty else { return unchanged(raw) }
        return GFChannelLabel(title: rest, secondLine: nil, quality: word, status: .none)
    }

    private enum EventKind { case live, upcoming, untimed }

    private static let separator = " · "

    /// 🔴 live, ⏰ start known, ▪ no time — each followed by a space (events.py `pretty()`).
    private static func eventKind(_ raw: String) -> EventKind? {
        guard let first = raw.first, let scalar = first.unicodeScalars.first, raw.dropFirst().first == " " else {
            return nil
        }
        switch scalar.value {
        case 0x1F534: return .live
        case 0x23F0: return .upcoming
        case 0x25AA: return .untimed
        default: return nil
        }
    }

    /// Title = the first part after the time; quality = the last part that is exactly a quality word; second line =
    /// the other parts without "Live" (the badge says it). nil when no title is left.
    private static func parseEvent(_ raw: String, kind: EventKind, now: Date,
                                   serverTimeZone: TimeZone) -> GFChannelLabel? {
        // the leading space lets an empty first part split off too ("▪ · HD" has no title)
        var parts = (" " + raw.dropFirst(2)).components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var status = Status.none
        switch kind {
        case .live:
            status = .live
            if let head = parts.first, head == "LIVE" || head.hasPrefix("LIVE ") { parts.removeFirst() }
        case .upcoming:
            // events.py always writes the start first; one that cannot be read leaves out only the time badge
            guard parts.count > 1 else { return nil }
            let head = parts.removeFirst()
            if let start = GFChannelLabelTime.resolve(head, now: now, serverTimeZone: serverTimeZone) {
                status = .upcoming(start: start)
            }
        case .untimed:
            break
        }
        guard let title = parts.first, !title.isEmpty else { return nil }
        let extras = parts.dropFirst().filter { !$0.isEmpty }
        let quality = extras.last { qualityWords.contains($0) }
        let second = extras.filter { !qualityWords.contains($0) && $0.caseInsensitiveCompare("Live") != .orderedSame }
        return GFChannelLabel(title: title, secondLine: second.isEmpty ? nil : second.joined(separator: separator),
                              quality: quality, status: status)
    }
}
