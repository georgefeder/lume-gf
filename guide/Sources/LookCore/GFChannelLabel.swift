import Foundation

/// A live channel's name as Lume GF shows it (spec: docs/superpowers/specs/2026-09-29-lume-gf-3-look-design.md).
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
        unchanged(raw)
    }
}
