import Foundation

/// Whether Lume GF may use iCloud in this process: our switch is on and the binary is a signed build (not unit tests,
/// previews, UI tests or the screenshot demo, where `CKContainer` would raise). Every CloudKit and key-value store
/// call of ours checks this first.
enum GFCloud {
    static var isAvailable: Bool {
        GFCloudConfig.enabled && LumeApp.isCloudKitEnvironment
    }
}
