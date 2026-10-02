import Foundation

// Part 4 (red): compiling stub that syncs nothing

@MainActor
protocol GFKeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    var dictionaryRepresentation: [String: Any] { get }
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: GFKeyValueStore {}

@MainActor
final class GFSettingsSync {
    static let shared = GFSettingsSync(store: NSUbiquitousKeyValueStore.default, defaults: .standard,
                                       deviceGroup: .ios, fallbackDelay: .seconds(20))

    init(store: GFKeyValueStore, defaults: UserDefaults, deviceGroup: GFSettingsGroup, fallbackDelay: Duration) {}

    func start() {}

    func storeDidChange(keys: [String], initialDownload: Bool) {}

    func defaultsDidChange() {}
}
