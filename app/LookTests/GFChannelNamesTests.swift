import Foundation
@testable import Lume
import Testing

/// Lume GF's clean names in the app: the setting (default on) and the text-only helper. Serialized: tests here change
/// the shared setting.
@MainActor
@Suite(.serialized)
struct GFChannelNamesTests {
    let live = "🔴 LIVE 20:00 · Arsenal v Chelsea · Premier League · FHD"

    @Test func `clean names are on until switched off`() {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: GFChannelNames.settingKey)
        defer { defaults.set(saved, forKey: GFChannelNames.settingKey) }
        defaults.removeObject(forKey: GFChannelNames.settingKey)
        #expect(GFChannelNames.isEnabled)
        defaults.set(false, forKey: GFChannelNames.settingKey)
        #expect(!GFChannelNames.isEnabled)
    }

    @Test func `the title is the clean name, or the full name when switched off`() {
        #expect(GFChannelNames.title(for: live, enabled: true) == "Arsenal v Chelsea")
        #expect(GFChannelNames.title(for: live, enabled: false) == live)
        #expect(GFChannelNames.title(for: "BBC One FHD", enabled: true) == "BBC One")
    }

    @Test func `switched off, the label is exactly the server's name`() {
        #expect(GFChannelNames.label(for: "BBC One FHD", enabled: false) == .unchanged("BBC One FHD"))
    }

    @Test func `badges show only when there is something to say`() {
        #expect(GFChannelBadges.hasBadges(GFChannelNames.label(for: "BBC One FHD", enabled: true)))
        #expect(GFChannelBadges.hasBadges(GFChannelNames.label(for: live, enabled: true)))
        #expect(!GFChannelBadges.hasBadges(GFChannelNames.label(for: "Channel 4", enabled: true)))
    }
}
