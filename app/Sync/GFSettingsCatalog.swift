// Part 4 (red): compiling stub that places no setting
enum GFSettingsCatalog {
    static let keys: [String: GFSettingsGroup] = [:]

    static func group(for key: String) -> GFSettingsGroup? {
        nil
    }

    static let everywhere: [String] = []
    static let perKind: [String] = []
    static let deviceOnly: [String] = []
}
