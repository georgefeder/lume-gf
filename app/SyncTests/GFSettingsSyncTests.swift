import Foundation
@testable import Lume
import Testing

@MainActor
final class FakeKeyValueStore: GFKeyValueStore {
    var values: [String: Any] = [:]
    /// every write, also one that stores the same value again (an echo would not change `values`)
    var writes = 0
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) {
        values[key] = value
        writes += 1
    }

    var dictionaryRepresentation: [String: Any] { values }
    func synchronize() -> Bool { true }
}

@MainActor
struct GFSettingsSyncTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "gf.settings.test.\(UUID().uuidString)")! }

    @Test func `every Lume setting is placed in a group`() {
        #expect(GFSettingsCatalog.group(for: HomeLayoutSettings.sectionOrderKey) == .tv) // a TV's Home is the TV's
        #expect(GFSettingsCatalog.group(for: PlayerSettings.Language.preferredAudioLanguagesKey) == .all)
        #expect(GFSettingsCatalog.group(for: PlaylistSelectionStore.key) == .device)
        #expect(GFSettingsCatalog.group(for: "not.a.lume.key") == nil)
    }

    @Test func `every cloud key fits iCloud's 64-byte limit, and no setting is placed twice`() {
        // the key-value store refuses a longer key without an error we would see: that setting would quietly stay put
        #expect(!GFSettingsCatalog.keys.isEmpty)
        for (key, group) in GFSettingsCatalog.keys where group != .device {
            for cloudGroup in group == .tv ? [GFSettingsGroup.tv, .ios] : [group] {
                let cloudKey = GFSettingsPlan.cloudKey(key, group: cloudGroup) ?? ""
                #expect(cloudKey.utf8.count <= 64, "\(cloudKey) is \(cloudKey.utf8.count) bytes")
            }
        }
        let listed = GFSettingsCatalog.everywhere.count + GFSettingsCatalog.perKind.count
            + GFSettingsCatalog.deviceOnly.count
        #expect(GFSettingsCatalog.keys.count == listed)
    }

    @Test func `the first sync waits for iCloud's first download`() async {
        // Review Focus 1: this device has a value, iCloud has not arrived yet → nothing is uploaded
        let store = FakeKeyValueStore(), ud = defaults()
        ud.set("dark", forKey: AppAppearance.storageKey)
        let sync = GFSettingsSync(store: store, defaults: ud, deviceGroup: .ios, fallbackDelay: .seconds(60))
        sync.start()
        #expect(store.values.isEmpty)
        // iCloud's first download arrives with another device's value
        store.values = [GFSettingsPlan.readyMarker: true, "gf.settings.ios.\(AppAppearance.storageKey)": "light"]
        sync.storeDidChange(keys: Array(store.values.keys), initialDownload: true)
        #expect(ud.string(forKey: AppAppearance.storageKey) == "light")
    }

    @Test func `with iCloud proved empty, this device's settings go up`() async throws {
        let store = FakeKeyValueStore(), ud = defaults()
        ud.set("dark", forKey: AppAppearance.storageKey)
        let sync = GFSettingsSync(store: store, defaults: ud, deviceGroup: .ios, fallbackDelay: .milliseconds(50))
        sync.start()
        // up to 3 s: a parallel run can hold the main thread far longer than the 50 ms wait (decision 10)
        for _ in 0 ..< 60 where store.values[GFSettingsPlan.readyMarker] == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(store.values["gf.settings.ios.\(AppAppearance.storageKey)"] as? String == "dark")
        #expect(store.values[GFSettingsPlan.readyMarker] as? Bool == true)
    }

    @Test func `a change here goes up, a change from iCloud comes down without echo`() async throws {
        let store = FakeKeyValueStore(), ud = defaults()
        store.values = [GFSettingsPlan.readyMarker: true]
        let sync = GFSettingsSync(store: store, defaults: ud, deviceGroup: .tv, fallbackDelay: .seconds(60))
        sync.start()
        ud.set(true, forKey: PlayerSettings.Playback.autoPlayNextKey)
        sync.defaultsDidChange()
        #expect(store.values["gf.settings.all.\(PlayerSettings.Playback.autoPlayNextKey)"] as? Bool == true)

        let cloudKey = "gf.settings.tv.\(HomeLayoutSettings.sectionOrderKey)"
        store.values[cloudKey] = "sports,favorites"
        let writesBefore = store.writes
        sync.storeDidChange(keys: [cloudKey], initialDownload: false)
        sync.defaultsDidChange() // the write above must not be sent back
        #expect(ud.string(forKey: HomeLayoutSettings.sectionOrderKey) == "sports,favorites")
        #expect(store.writes == writesBefore)
    }

    @Test func `another kind of device's settings are left alone`() {
        let store = FakeKeyValueStore(), ud = defaults()
        store.values = [GFSettingsPlan.readyMarker: true, "gf.settings.tv.\(HomeLayoutSettings.sectionOrderKey)": "x"]
        let sync = GFSettingsSync(store: store, defaults: ud, deviceGroup: .ios, fallbackDelay: .seconds(60))
        sync.start()
        sync.storeDidChange(keys: Array(store.values.keys), initialDownload: true)
        #expect(ud.string(forKey: HomeLayoutSettings.sectionOrderKey) == nil)
    }
}
