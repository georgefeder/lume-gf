/// Settings through the iCloud key-value store (spec section 3): everywhere, per kind of device (all Apple TVs; iPhone
/// and iPad), or this device only. Keys `gf.settings.<group>.<key>`; `gf.settings.ready` says a device has done its
/// first sync (so iCloud's settings exist and a newcomer takes them instead of uploading its own).
nonisolated enum GFSettingsGroup: String, CaseIterable, Sendable {
    case all, tv, ios, device
}

nonisolated enum GFSettingsPlan {
    static let readyMarker = GFCloudConfig.settingsPrefix + "ready"

    struct FirstSync {
        var adopt: [String: Any]
        var upload: [String: Any]
    }

    static func cloudKey(_ key: String, group: GFSettingsGroup) -> String? {
        group == .device ? nil : GFCloudConfig.settingsPrefix + group.rawValue + "." + key
    }

    static func localKey(fromCloudKey cloudKey: String, groups: Set<GFSettingsGroup>) -> String? {
        guard cloudKey.hasPrefix(GFCloudConfig.settingsPrefix), cloudKey != readyMarker else { return nil }
        let rest = cloudKey.dropFirst(GFCloudConfig.settingsPrefix.count)
        guard let dot = rest.firstIndex(of: "."), let group = GFSettingsGroup(rawValue: String(rest[..<dot])),
              group != .device, groups.contains(group) else { return nil }
        let key = rest[rest.index(after: dot)...]
        return key.isEmpty ? nil : String(key)
    }

    /// `local`: this device's stored values (only what was ever set: a new install has none) under their cloud keys;
    /// `cloud`: what iCloud has. iCloud's values are taken; this device's own go up only where iCloud has none.
    static func firstSync(local: [String: Any], cloud: [String: Any]) -> FirstSync {
        FirstSync(adopt: cloud, upload: local.filter { cloud[$0.key] == nil })
    }

    static func cloudIsReady(cloudKeys: [String]) -> Bool {
        cloudKeys.contains(readyMarker)
    }
}
