import Foundation

/// What a device played last (spec section 5): one record in the private iCloud database, overwritten by whichever
/// device plays.
nonisolated struct GFLastPlayedNote: Equatable, Sendable {
    enum Kind: String, Sendable { case channel, film, episode }

    var deviceID: String
    var deviceKind: String
    var kind: Kind
    var contentId: String
    var title: String
    var artworkURL: String?
    var position: Double
    var duration: Double
    var playing: Bool
    var updatedAt: Date
}

/// When the continue banner offers the note (spec section 5).
nonisolated enum GFContinueOffer {
    static let window: TimeInterval = 3 * 3600

    static func dismissalKey(_ note: GFLastPlayedNote) -> String {
        "\(note.contentId)@\(Int(note.updatedAt.timeIntervalSince1970))"
    }

    static func offer(_ note: GFLastPlayedNote?, myDeviceID: String, now: Date, dismissed: Set<String>,
                      inCatalog: Bool, playingHere: Bool) -> GFLastPlayedNote? {
        guard let note, note.deviceID != myDeviceID, !playingHere, inCatalog,
              now.timeIntervalSince(note.updatedAt) <= window,
              !dismissed.contains(dismissalKey(note)) else { return nil }
        return note
    }

    static func subtitle(_ note: GFLastPlayedNote, now: Date) -> String {
        var parts: [String] = []
        if note.kind != .channel, note.position > 0 { parts.append(clock(note.position)) }
        parts.append("from \(note.deviceKind)")
        parts.append(ago(now.timeIntervalSince(note.updatedAt)))
        return parts.joined(separator: " · ")
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
    }

    private static func ago(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        return "\(Int(seconds / 3600)) h ago"
    }
}
