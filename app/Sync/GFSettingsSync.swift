import Foundation

/// The key-value store as GFSettingsSync uses it (iCloud's in the app, a fake in tests).
@MainActor
protocol GFKeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    var dictionaryRepresentation: [String: Any] { get }
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: GFKeyValueStore {}

/// Settings follow the viewer (spec section 3): Lume's settings in `UserDefaults` ↔ the iCloud key-value store, in the
/// groups of `GFSettingsCatalog`. A device takes iCloud's settings once they have arrived (`gf.settings.ready` shows a
/// device has synced before) and uploads its own only when iCloud proved empty (`fallbackDelay` after start).
/// Applying a value from iCloud never sends it back.
@MainActor
final class GFSettingsSync {
    static let shared = GFSettingsSync(store: NSUbiquitousKeyValueStore.default, defaults: .standard,
                                       deviceGroup: GFSettingsSync.thisDeviceGroup, fallbackDelay: .seconds(20))

    private let store: GFKeyValueStore
    private let defaults: UserDefaults
    private let deviceGroup: GFSettingsGroup
    private let fallbackDelay: Duration
    private var started = false
    private var firstSyncDone = false
    private var applying = false
    private var snapshot: [String: NSObject] = [:]
    private var observers: [NSObjectProtocol] = []

    init(store: GFKeyValueStore, defaults: UserDefaults, deviceGroup: GFSettingsGroup, fallbackDelay: Duration) {
        self.store = store
        self.defaults = defaults
        self.deviceGroup = deviceGroup
        self.fallbackDelay = fallbackDelay
    }

    static var thisDeviceGroup: GFSettingsGroup {
        #if os(tvOS)
            .tv
        #else
            .ios
        #endif
    }

    private var groups: Set<GFSettingsGroup> {
        [.all, deviceGroup]
    }

    /// The cloud key of a Lume key on this device (nil: stays here).
    private func cloudKey(_ key: String) -> String? {
        guard let group = GFSettingsCatalog.group(for: key) else { return nil }
        return GFSettingsPlan.cloudKey(key, group: group == .tv ? deviceGroup : group)
    }

    /// The Lume key a cloud key stands for on this device: only the key this build itself writes it to (a value
    /// another build left under another group, or a setting this build keeps on the device, is not taken).
    private func localKey(_ cloud: String) -> String? {
        guard let key = GFSettingsPlan.localKey(fromCloudKey: cloud, groups: groups), cloudKey(key) == cloud else {
            return nil
        }
        return key
    }

    /// The app calls this once at launch when `GFCloud.isAvailable`; tests call it with a fake store.
    func start() {
        guard !started else { return }
        started = true
        snapshot = currentValues()
        store.synchronize()
        if GFSettingsPlan.cloudIsReady(cloudKeys: Array(store.dictionaryRepresentation.keys)) {
            runFirstSync()
        } else {
            Task { [weak self, fallbackDelay] in
                try? await Task.sleep(for: fallbackDelay)
                self?.runFirstSync()
            }
        }
        if let cloudStore = store as? NSUbiquitousKeyValueStore {
            observers.append(NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloudStore, queue: .main
            ) { [weak self] note in
                let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
                let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
                let initialDownload = reason == NSUbiquitousKeyValueStoreInitialSyncChange
                MainActor.assumeIsolated { self?.storeDidChange(keys: keys, initialDownload: initialDownload) }
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.defaultsDidChange() }
            })
        }
    }

    /// iCloud changed (another device, or iCloud's first download).
    func storeDidChange(keys: [String], initialDownload: Bool) {
        if !firstSyncDone,
           initialDownload || GFSettingsPlan.cloudIsReady(cloudKeys: Array(store.dictionaryRepresentation.keys)) {
            runFirstSync()
            return
        }
        apply(keys: keys)
    }

    /// Lume changed a setting here.
    func defaultsDidChange() {
        guard firstSyncDone, !applying else { return }
        let now = currentValues()
        for (key, value) in now where snapshot[key] != value {
            if let cloud = cloudKey(key) { store.set(value, forKey: cloud) }
        }
        for key in Set(snapshot.keys).subtracting(now.keys) {
            if let cloud = cloudKey(key) { store.set(nil, forKey: cloud) }
        }
        snapshot = now
    }

    private func runFirstSync() {
        guard !firstSyncDone else { return }
        firstSyncDone = true
        var local: [String: Any] = [:]
        for (key, value) in currentValues() {
            if let cloud = cloudKey(key) { local[cloud] = value }
        }
        let cloud = store.dictionaryRepresentation.filter { localKey($0.key) != nil }
        let plan = GFSettingsPlan.firstSync(local: local, cloud: cloud)
        apply(keys: Array(plan.adopt.keys))
        for (key, value) in plan.upload { store.set(value, forKey: key) }
        store.set(true, forKey: GFSettingsPlan.readyMarker)
        store.synchronize()
    }

    private func apply(keys: [String]) {
        applying = true
        defer { applying = false }
        for cloud in keys {
            guard let key = localKey(cloud) else { continue }
            defaults.set(store.object(forKey: cloud), forKey: key)
        }
        snapshot = currentValues()
    }

    private func currentValues() -> [String: NSObject] {
        var values: [String: NSObject] = [:]
        for key in GFSettingsCatalog.keys.keys {
            if let value = defaults.object(forKey: key) as? NSObject { values[key] = value }
        }
        return values
    }
}
