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

    static func parse(_ raw: String) -> GFChannelLabel {
        parseOrdinary(raw)
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
}
