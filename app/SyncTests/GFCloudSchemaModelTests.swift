import CoreData
@testable import Lume
import SwiftData
import Testing

struct GFCloudSchemaModelTests {
    @Test func `Lume's cloud models match the committed layout`() throws {
        // Review Focus 4: a Lume release that changes its synced models stops here, not in production
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: [
            SyncedPlaylist.self, UserContentState.self, UserProfile.self, SyncedEPGSource.self,
            SyncedParentalPIN.self, SyncedCategoryRestriction.self, SyncedSportsFollow.self,
            SyncedRecordingServer.self
        ]))
        let real = model.entities.map { entity in
            GFCloudSchema.Entity(name: entity.name ?? "", attributes: entity.attributesByName.values.map { attribute in
                GFCloudSchema.Attribute(name: attribute.name, type: Self.type(attribute.attributeType),
                                        encrypted: attribute.allowsCloudEncryption)
            }.sorted { $0.name < $1.name })
        }.sorted { $0.name < $1.name }
        let committed = GFCloudSchema.lumeEntities.map {
            GFCloudSchema.Entity(name: $0.name, attributes: $0.attributes.sorted { $0.name < $1.name })
        }.sorted { $0.name < $1.name }
        #expect(real == committed)
        #expect(model.entities.allSatisfy { $0.relationshipsByName.isEmpty })
    }

    private static func type(_ type: NSAttributeType) -> GFCloudSchema.AttributeType {
        switch type {
        case .stringAttributeType: .string
        case .UUIDAttributeType: .uuid
        case .URIAttributeType: .uri
        case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType: .integer
        case .booleanAttributeType: .bool
        case .doubleAttributeType, .floatAttributeType: .double
        case .dateAttributeType: .date
        default: .binary
        }
    }
}
