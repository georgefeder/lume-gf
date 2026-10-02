import Foundation

/// A playlist added by hand on several devices exists once per device, each with its own id; with iCloud on, every
/// copy would show everywhere and download its catalogue again. Copies of the same source merge into the one with the
/// smallest id, the same choice on every device whatever order iCloud delivers them in (spec section 2).
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

    /// Same type, same server (scheme and host without case, default port and trailing slash dropped) and same user
    /// (a portal without a user: same MAC address) = the same source.
    static func sameSourceKey(_ identity: Identity) -> String {
        let who = identity.username.isEmpty ? "mac:" + identity.mac.lowercased() : "user:" + identity.username
        return [identity.sourceType.lowercased(), normalizedServer(identity.server), who].joined(separator: "|")
    }

    /// Every copy that is not the smallest id of its source, paired with that smallest id, in a stable order.
    static func plan(_ identities: [Identity]) -> [Merge] {
        var bySource: [String: Set<UUID>] = [:]
        for identity in identities {
            bySource[sameSourceKey(identity), default: []].insert(identity.id)
        }
        var merges: [Merge] = []
        for ids in bySource.values where ids.count > 1 {
            let sorted = ids.sorted { $0.uuidString < $1.uuidString }
            for drop in sorted.dropFirst() {
                merges.append(Merge(keep: sorted[0], drop: drop))
            }
        }
        return merges.sorted { ($0.keep.uuidString, $0.drop.uuidString) < ($1.keep.uuidString, $1.drop.uuidString) }
    }

    /// Lume's content ids start with their playlist's id (`"<playlist>-live-42"`): the id under the kept playlist, or
    /// nil when `id` does not belong to the dropped one.
    static func reprefixed(_ id: String, from drop: UUID, to keep: UUID) -> String? {
        let prefix = drop.uuidString + "-"
        guard id.hasPrefix(prefix), id.count > prefix.count else { return nil }
        return keep.uuidString + "-" + id.dropFirst(prefix.count)
    }

    static func normalizedServer(_ server: String) -> String {
        var text = server.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("/") { text.removeLast() }
        guard var parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(), let host = parts.host
        else { return text.lowercased() }
        parts.scheme = scheme
        parts.host = host.lowercased()
        if (scheme == "http" && parts.port == 80) || (scheme == "https" && parts.port == 443) { parts.port = nil }
        return parts.string ?? text.lowercased()
    }
}
