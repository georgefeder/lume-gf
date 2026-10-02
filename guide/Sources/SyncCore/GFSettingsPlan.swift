// Part 4 (red): compiling stub, every answer wrong
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
        nil
    }

    static func localKey(fromCloudKey cloudKey: String, groups: Set<GFSettingsGroup>) -> String? {
        nil
    }

    static func firstSync(local: [String: Any], cloud: [String: Any]) -> FirstSync {
        FirstSync(adopt: [:], upload: local)
    }

    static func cloudIsReady(cloudKeys: [String]) -> Bool {
        false
    }
}
