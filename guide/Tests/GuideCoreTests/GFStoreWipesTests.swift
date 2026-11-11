import Foundation
@testable import GuideCore
import Testing

struct GFStoreWipesTests {
    private let start = Date(timeIntervalSince1970: 1_794_700_000)

    private func fresh() -> UserDefaults {
        let name = "GFStoreWipesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func stamp(_ date: Date) -> String {
        "t\(Int(date.timeIntervalSince(start)))"
    }

    @Test func `a store that had playlists and comes back without any was wiped, counted once`() {
        let defaults = fresh()
        #expect(!GFStoreWipes.noteLaunch(playlistCount: 1, defaults: defaults, now: start))
        let wiped = GFStoreWipes.noteLaunch(playlistCount: 0, defaults: defaults, now: start + 60)
        #expect(wiped)
        // still empty at the next launch (nothing synced yet): the same wipe, not another
        let again = GFStoreWipes.noteLaunch(playlistCount: 0, defaults: defaults, now: start + 120)
        #expect(!again)
        #expect(defaults.integer(forKey: GFStoreWipes.countKey) == 1)
        #expect(GFStoreWipes.line(defaults: defaults, when: stamp) == "Apple TV cleared Lume's saved channels and guide once, last t60")
    }

    @Test func `a new install with no playlists yet is no wipe`() {
        let defaults = fresh()
        let first = GFStoreWipes.noteLaunch(playlistCount: 0, defaults: defaults, now: start)
        #expect(!first)
        #expect(GFStoreWipes.line(defaults: defaults, when: stamp) == "Apple TV has kept Lume's saved channels and guide since t0")
    }

    @Test func `each wipe after the playlists came back counts, the line says how often and when last`() {
        let defaults = fresh()
        GFStoreWipes.noteLaunch(playlistCount: 2, defaults: defaults, now: start)
        GFStoreWipes.noteLaunch(playlistCount: 0, defaults: defaults, now: start + 10)
        GFStoreWipes.noteLaunch(playlistCount: 2, defaults: defaults, now: start + 20)
        GFStoreWipes.noteLaunch(playlistCount: 0, defaults: defaults, now: start + 30)
        #expect(defaults.integer(forKey: GFStoreWipes.countKey) == 2)
        #expect(GFStoreWipes.line(defaults: defaults, when: stamp) == "Apple TV cleared Lume's saved channels and guide 2 times, last t30")
    }
}
