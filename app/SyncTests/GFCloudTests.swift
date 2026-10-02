@testable import Lume
import Testing

struct GFCloudTests {
    @Test func `Lume's sync uses our container`() {
        #expect(LumeApp.cloudKitContainerIdentifier == "iCloud.lv.georgefeder.lume")
    }

    @Test func `nothing touches iCloud in tests`() {
        // unit tests are unsigned: CKContainer would raise, so iCloud stays off here (Review Focus 3)
        #expect(!LumeApp.isCloudKitEnvironment)
        #expect(!GFCloud.isAvailable)
    }
}
