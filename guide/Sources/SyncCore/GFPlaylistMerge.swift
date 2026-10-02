import Foundation

nonisolated enum GFPlaylistMerge {
    struct Identity: Equatable, Sendable {
        var id: UUID
        var sourceType: String
        var server: String
        var username: String
        var mac: String
    }

    struct Merge: Equatable, Sendable {
        var keep: UUID
        var drop: UUID
    }

    static func sameSourceKey(_ identity: Identity) -> String {
        identity.id.uuidString
    }

    static func plan(_: [Identity]) -> [Merge] {
        []
    }

    static func reprefixed(_: String, from _: UUID, to _: UUID) -> String? {
        nil
    }
}
