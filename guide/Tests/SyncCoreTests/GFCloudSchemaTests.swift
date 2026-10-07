@testable import SyncCore
import Testing

struct GFCloudSchemaTests {
    private let sample = [GFCloudSchema.Entity(name: "SyncedPlaylist", attributes: [
        .init(name: "id", type: .uuid),
        .init(name: "password", type: .string, encrypted: true),
        .init(name: "syncEnabled", type: .bool),
        .init(name: "updatedAt", type: .date),
        .init(name: "epgURL", type: .string)
    ])]

    @Test func `Core Data's record type, entity name and move receipt come first`() {
        let text = GFCloudSchema.ckdb(entities: sample)
        #expect(text.hasPrefix("DEFINE SCHEMA\n"))
        #expect(text.contains("    RECORD TYPE CD_SyncedPlaylist (\n"))
        #expect(text.contains("        CD_entityName STRING QUERYABLE,\n"))
        #expect(text.contains("        CD_moveReceipt BYTES,\n"))
        #expect(text.contains("        CD_moveReceipt_ckAsset ASSET,\n"))
        #expect(text.contains("        \"___recordID\" REFERENCE QUERYABLE,\n"))
    }

    @Test func `attributes follow Apple's published mapping`() {
        let text = GFCloudSchema.ckdb(entities: sample)
        #expect(text.contains("        CD_id STRING,\n")) // UUID -> STRING
        #expect(text.contains("        CD_syncEnabled INT64,\n")) // Bool -> INT64
        #expect(text.contains("        CD_updatedAt TIMESTAMP,\n"))
        #expect(text.contains("        CD_epgURL STRING,\n"))
        #expect(text.contains("        CD_epgURL_ckAsset ASSET,\n")) // every string may move to an asset
        #expect(!text.contains("CD_syncEnabled_ckAsset"))
    }

    @Test func `encrypted attributes are encrypted fields without an index`() {
        let text = GFCloudSchema.ckdb(entities: sample)
        #expect(text.contains("        CD_password ENCRYPTED STRING,\n"))
        #expect(text.contains("        CD_password_ckAsset ASSET,\n"))
        #expect(!text.contains("CD_password ENCRYPTED STRING QUERYABLE"))
    }

    @Test func `the private database's default grants close each type`() {
        let text = GFCloudSchema.ckdb(entities: sample)
        #expect(text.contains("        GRANT WRITE TO \"_creator\",\n        GRANT CREATE TO \"_icloud\",\n        GRANT READ TO \"_world\"\n    );\n"))
    }

    @Test func `the full layout has Lume's eight types and the banner's record`() {
        let text = GFCloudSchema.ckdb()
        for name in ["CD_SyncedPlaylist", "CD_UserContentState", "CD_UserProfile", "CD_SyncedEPGSource",
                     "CD_SyncedParentalPIN", "CD_SyncedCategoryRestriction", "CD_SyncedSportsFollow",
                     "CD_SyncedRecordingServer"] {
            #expect(text.contains("    RECORD TYPE \(name) (\n"))
        }
        #expect(text.contains("    RECORD TYPE GFLastPlayed (\n"))
        #expect(text.contains("        contentId STRING,\n"))
        #expect(text.contains("        updatedAt TIMESTAMP QUERYABLE SORTABLE,\n"))
    }

    @Test func `the layout text is stable`() {
        #expect(GFCloudSchema.ckdb() == GFCloudSchema.ckdb())
        #expect(GFCloudSchema.lumeEntities.map(\.name) == ["SyncedPlaylist", "UserContentState", "UserProfile",
                                                           "SyncedEPGSource", "SyncedParentalPIN",
                                                           "SyncedCategoryRestriction", "SyncedSportsFollow",
                                                           "SyncedRecordingServer"])
    }
}
