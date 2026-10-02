import Foundation
import OSLog
import SwiftData

/// Lume GF (Part 4, spec section 2): copies of the same playlist, one per device that added it by hand, merge into
/// the copy with the smallest id before Lume's playlist pass. The dropped copy's state (also any its catalogue holds
/// that never reached the cloud store) moves to the kept playlist's ids, merged with Lume's never-lose-a-favourite
/// rule; then the copy, its mirror and its baseline go. A device that only had the dropped copy downloads the kept
/// playlist's catalogue once (Lume creates the local playlist from its mirror in the same reconcile).
extension CloudSyncEngine {
    @discardableResult
    func gfMergeDuplicatePlaylists() throws -> Int {
        let locals = try fetchLocalPlaylists()
        let mirrors = try fetchPlaylistMirrors()
        var identities: [GFPlaylistMerge.Identity] = []
        for (id, playlist) in locals {
            identities.append(.init(id: id, sourceType: playlist.sourceTypeRaw, server: playlist.serverURL,
                                    username: playlist.username, mac: playlist.macAddress ?? ""))
        }
        for (id, mirror) in mirrors {
            identities.append(.init(id: id, sourceType: mirror.sourceTypeRaw, server: mirror.serverURL,
                                    username: mirror.username, mac: mirror.macAddress))
        }
        let merges = GFPlaylistMerge.plan(identities)
        guard !merges.isEmpty else { return 0 }
        for merge in merges {
            try gfCaptureUnsyncedState(of: merge)
            try gfMoveContentState(of: merge)
            try gfMoveRestrictions(of: merge)
            if let local = locals[merge.drop] {
                PlaylistDeletion.delete(local, in: catalogContext)
            }
            if let mirror = mirrors[merge.drop] {
                cloudContext.delete(mirror)
            }
            shadow.setPlaylistShadow(merge.drop.uuidString, nil)
            Logger.sync.info("Lume GF: merged playlist \(merge.drop.uuidString) into \(merge.keep.uuidString)")
        }
        try saveStores()
        return merges.count
    }

    /// State the dropped copy's catalogue holds but the cloud store does not yet (set since the last reconcile).
    private func gfCaptureUnsyncedState(of merge: GFPlaylistMerge.Merge) throws {
        let prefix = merge.drop.uuidString + "-"
        let mirrored = Set(try cloudContext.fetch(FetchDescriptor<UserContentState>(
            predicate: #Predicate { $0.contentId.starts(with: prefix) }
        )).map(\.contentId))
        for (id, entry) in try fetchLocalContentValues() where id.hasPrefix(prefix) && !mirrored.contains(id) {
            cloudContext.insert(UserContentState(
                contentId: id, kind: entry.kind, profileID: activeProfileID,
                watchProgress: entry.values.watchProgress, isWatched: entry.values.isWatched,
                lastWatchedDate: entry.values.lastWatchedDate, isFavorite: entry.values.isFavorite,
                addedToWatchlistDate: entry.values.addedToWatchlistDate, favoriteOrder: entry.values.favoriteOrder,
                recommendationVoteRaw: entry.values.recommendationVoteRaw, isHidden: entry.values.isHidden,
                customOrder: entry.values.customOrder
            ))
        }
    }

    /// Every profile's state under the dropped copy's ids moves to the kept copy's ids; where both exist they combine.
    private func gfMoveContentState(of merge: GFPlaylistMerge.Merge) throws {
        let dropPrefix = merge.drop.uuidString + "-"
        let moving = try cloudContext.fetch(FetchDescriptor<UserContentState>(
            predicate: #Predicate { $0.contentId.starts(with: dropPrefix) }
        ))
        for state in moving {
            guard let newID = GFPlaylistMerge.reprefixed(state.contentId, from: merge.drop, to: merge.keep)
            else { continue }
            let profile = state.profileID
            let existing = try cloudContext.fetch(FetchDescriptor<UserContentState>(
                predicate: #Predicate { $0.contentId == newID }
            )).first { $0.profileID == profile }
            if let existing {
                let combined = ContentStateValues.mergeConflict(local: Self.values(from: existing),
                                                                cloud: Self.values(from: state))
                existing.watchProgress = combined.watchProgress
                existing.isWatched = combined.isWatched
                existing.lastWatchedDate = combined.lastWatchedDate
                existing.isFavorite = combined.isFavorite
                existing.addedToWatchlistDate = combined.addedToWatchlistDate
                existing.favoriteOrder = combined.favoriteOrder
                existing.recommendationVoteRaw = combined.recommendationVoteRaw
                existing.isHidden = combined.isHidden
                existing.customOrder = combined.customOrder
                existing.updatedAt = Date()
                cloudContext.delete(state)
            } else {
                state.contentId = newID
                state.updatedAt = Date()
            }
        }
    }

    private func gfMoveRestrictions(of merge: GFPlaylistMerge.Merge) throws {
        let dropPrefix = merge.drop.uuidString + "-"
        for restriction in try cloudContext.fetch(FetchDescriptor<SyncedCategoryRestriction>(
            predicate: #Predicate { $0.categoryID.starts(with: dropPrefix) }
        )) {
            if let newID = GFPlaylistMerge.reprefixed(restriction.categoryID, from: merge.drop, to: merge.keep) {
                restriction.categoryID = newID
                restriction.updatedAt = Date()
            }
        }
    }
}
