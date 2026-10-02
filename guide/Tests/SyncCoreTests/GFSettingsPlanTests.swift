@testable import SyncCore
import Testing

struct GFSettingsPlanTests {
    @Test func `cloud keys carry the group, device-only settings have none`() {
        #expect(GFSettingsPlan.cloudKey("home.sectionOrder.v1", group: .tv) == "gf.settings.tv.home.sectionOrder.v1")
        #expect(GFSettingsPlan.cloudKey("lume.audioLanguages", group: .all) == "gf.settings.all.lume.audioLanguages")
        #expect(GFSettingsPlan.cloudKey("debug.enabled", group: .device) == nil)
    }

    @Test func `a cloud key comes back only for this device's groups`() {
        let mine: Set<GFSettingsGroup> = [.all, .tv]
        #expect(GFSettingsPlan.localKey(fromCloudKey: "gf.settings.tv.player.engine", groups: mine) == "player.engine")
        #expect(GFSettingsPlan.localKey(fromCloudKey: "gf.settings.all.x.y", groups: mine) == "x.y")
        #expect(GFSettingsPlan.localKey(fromCloudKey: "gf.settings.ios.player.engine", groups: mine) == nil)
        #expect(GFSettingsPlan.localKey(fromCloudKey: "something.else", groups: mine) == nil)
        #expect(GFSettingsPlan.localKey(fromCloudKey: GFSettingsPlan.readyMarker, groups: mine) == nil)
    }

    @Test func `the first device decides: iCloud's values are taken, the rest uploaded`() {
        let plan = GFSettingsPlan.firstSync(
            local: ["gf.settings.tv.a": 1, "gf.settings.tv.b": "local"],
            cloud: ["gf.settings.tv.b": "cloud", "gf.settings.tv.c": true]
        )
        #expect(plan.adopt["gf.settings.tv.b"] as? String == "cloud")
        #expect(plan.adopt["gf.settings.tv.c"] as? Bool == true)
        #expect(plan.upload["gf.settings.tv.a"] as? Int == 1)
        #expect(plan.upload["gf.settings.tv.b"] == nil)
        #expect(plan.adopt["gf.settings.tv.a"] == nil)
    }

    @Test func `a new install has nothing stored, so it uploads nothing`() {
        let plan = GFSettingsPlan.firstSync(local: [:], cloud: ["gf.settings.ios.a": 2])
        #expect(plan.upload.isEmpty)
        #expect(plan.adopt.count == 1)
    }

    @Test func `iCloud is ready once its marker is there`() {
        #expect(GFSettingsPlan.cloudIsReady(cloudKeys: ["gf.settings.ready", "gf.settings.all.x"]))
        #expect(!GFSettingsPlan.cloudIsReady(cloudKeys: ["gf.settings.all.x"]))
        #expect(!GFSettingsPlan.cloudIsReady(cloudKeys: []))
    }
}
