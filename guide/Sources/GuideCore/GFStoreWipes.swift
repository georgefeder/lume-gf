import Foundation

/// tvOS may delete an app's saved data when the Apple TV runs low on storage: everything but the app's small settings
/// is "purgeable". Lume then comes back empty, its playlists synced again behind the first-sync cover and the guide
/// imported again from nothing (Georgs, 8 Nov 2026: "every time I go into Apple TV, it shows like the syncing thing").
/// The settings survive a wipe, so they keep count: a store that had playlists at one launch and none at the next
/// was wiped. Deleting every playlist by hand counts once too; nothing else does.
nonisolated enum GFStoreWipes {
    static let hadPlaylistsKey = "gf.store.hadPlaylists"
    static let countKey = "gf.store.wipes"
    static let lastKey = "gf.store.lastWipe"
    static let watchedSinceKey = "gf.store.watchedSince"

    /// This launch's playlist count, read before anything syncs. Whether the store was wiped since the last launch.
    @discardableResult
    static func noteLaunch(playlistCount: Int, defaults: UserDefaults = .standard, now: Date = Date()) -> Bool {
        if defaults.object(forKey: watchedSinceKey) == nil { defaults.set(now, forKey: watchedSinceKey) }
        guard playlistCount == 0 else {
            defaults.set(true, forKey: hadPlaylistsKey)
            return false
        }
        guard defaults.bool(forKey: hadPlaylistsKey) else { return false }
        // counted once: the next launches find no playlists either until the sync has brought them back
        defaults.set(false, forKey: hadPlaylistsKey)
        defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey)
        defaults.set(now, forKey: lastKey)
        return true
    }

    /// The Apple TV's TV Guide settings line: kept since the counting began, or how often and when last cleared.
    static func line(defaults: UserDefaults = .standard, when: (Date) -> String) -> String {
        let since = (defaults.object(forKey: watchedSinceKey) as? Date).map(when)
        let count = defaults.integer(forKey: countKey)
        guard count > 0, let last = defaults.object(forKey: lastKey) as? Date else {
            return since.map { "Apple TV has kept Lume's saved channels and guide since \($0)" }
                ?? "Apple TV has kept Lume's saved channels and guide"
        }
        let times = count == 1 ? "once" : "\(count) times"
        return "Apple TV cleared Lume's saved channels and guide \(times), last \(when(last))"
    }
}
