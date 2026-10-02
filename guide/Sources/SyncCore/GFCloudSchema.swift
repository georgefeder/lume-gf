/// The iCloud layout (CloudKit schema) of Lume's synced store plus our banner record, written from data because
/// Apple's own generator needs a signed-in iCloud account (spike, 30 Sep). Mapping from Apple's "Reading CloudKit
/// Records for Core Data": record type `CD_<Entity>`, field `CD_<attribute>`, String/UUID/URI as STRING, integers and
/// Bool as INT64, Double as DOUBLE, Date as TIMESTAMP, binary as BYTES; every string and binary attribute also gets
/// `CD_<attribute>_ckAsset`; `CD_entityName`; as in real exported layouts `CD_moveReceipt` (+ asset). Encrypted
/// attributes are `ENCRYPTED <type>` without indexes (not documented by Apple: spec section 2's caveat).
public nonisolated enum GFCloudSchema {
    enum AttributeType: String, Sendable {
        case string, uuid, uri, integer, bool, double, date, binary
    }

    struct Attribute: Equatable, Sendable {
        var name: String
        var type: AttributeType
        var encrypted = false
    }

    struct Entity: Equatable, Sendable {
        var name: String
        var attributes: [Attribute]
    }

    /// Lume's cloud store (`LumeApp.makeCloudContainer`), as SwiftData models it. An app test compares this with the
    /// real model (`NSManagedObjectModel.makeManagedObjectModel`), so a Lume release that changes it stops the build.
    static let lumeEntities: [Entity] = [
        Entity(name: "SyncedPlaylist", attributes: [
            .init(name: "id", type: .uuid), .init(name: "name", type: .string), .init(name: "serverURL", type: .string),
            .init(name: "username", type: .string, encrypted: true),
            .init(name: "password", type: .string, encrypted: true),
            .init(name: "macAddress", type: .string, encrypted: true), .init(name: "sourceTypeRaw", type: .string),
            .init(name: "epgURL", type: .string), .init(name: "syncEnabled", type: .bool),
            .init(name: "hiddenTabsRaw", type: .string), .init(name: "updatedAt", type: .date)
        ]),
        Entity(name: "UserContentState", attributes: [
            .init(name: "contentId", type: .string), .init(name: "kindRaw", type: .string),
            .init(name: "profileID", type: .uuid), .init(name: "watchProgress", type: .double),
            .init(name: "isWatched", type: .bool), .init(name: "lastWatchedDate", type: .date),
            .init(name: "isFavorite", type: .bool), .init(name: "addedToWatchlistDate", type: .date),
            .init(name: "favoriteOrder", type: .integer), .init(name: "isHidden", type: .bool),
            .init(name: "customOrder", type: .integer), .init(name: "recommendationVoteRaw", type: .integer),
            .init(name: "updatedAt", type: .date)
        ]),
        Entity(name: "UserProfile", attributes: [
            .init(name: "id", type: .uuid), .init(name: "name", type: .string), .init(name: "symbolName", type: .string),
            .init(name: "colorRaw", type: .string), .init(name: "createdAt", type: .date),
            .init(name: "sortOrder", type: .integer), .init(name: "updatedAt", type: .date),
            .init(name: "isChild", type: .bool)
        ]),
        Entity(name: "SyncedEPGSource", attributes: [
            .init(name: "id", type: .uuid), .init(name: "name", type: .string), .init(name: "url", type: .string),
            .init(name: "isEnabled", type: .bool), .init(name: "updatedAt", type: .date)
        ]),
        Entity(name: "SyncedParentalPIN", attributes: [
            .init(name: "id", type: .string), .init(name: "pinHash", type: .string), .init(name: "updatedAt", type: .date)
        ]),
        Entity(name: "SyncedCategoryRestriction", attributes: [
            .init(name: "categoryID", type: .string), .init(name: "isRestricted", type: .bool),
            .init(name: "updatedAt", type: .date)
        ]),
        Entity(name: "SyncedSportsFollow", attributes: [
            .init(name: "key", type: .string), .init(name: "kindRaw", type: .string), .init(name: "profileID", type: .uuid),
            .init(name: "sortOrder", type: .integer), .init(name: "updatedAt", type: .date)
        ])
    ]

    /// The banner's record (spec section 5), written by our code with plain field names.
    static let lastPlayedFields: [(name: String, type: String)] = [
        ("deviceID", "STRING"), ("deviceKind", "STRING"), ("kind", "STRING"), ("contentId", "STRING"),
        ("title", "STRING"), ("artworkURL", "STRING"), ("position", "DOUBLE"), ("duration", "DOUBLE"),
        ("playing", "INT64"), ("updatedAt", "TIMESTAMP QUERYABLE SORTABLE")
    ]

    /// Public for `gf-schema`, the only caller outside this module.
    public static func ckdb() -> String {
        ckdb(entities: lumeEntities, includeLastPlayed: true)
    }

    static func ckdb(entities: [Entity], includeLastPlayed: Bool = false) -> String {
        var lines = ["DEFINE SCHEMA", ""]
        for entity in entities {
            var fields = [
                "\"___createTime\" TIMESTAMP", "\"___createdBy\" REFERENCE", "\"___etag\" STRING",
                "\"___modTime\" TIMESTAMP", "\"___modifiedBy\" REFERENCE", "\"___recordID\" REFERENCE QUERYABLE",
                "CD_entityName STRING QUERYABLE", "CD_moveReceipt BYTES", "CD_moveReceipt_ckAsset ASSET"
            ]
            for attribute in entity.attributes {
                fields.append("CD_\(attribute.name) \(attribute.encrypted ? "ENCRYPTED " : "")\(cloudType(attribute.type))")
                if attribute.type == .string || attribute.type == .binary {
                    fields.append("CD_\(attribute.name)_ckAsset ASSET")
                }
            }
            lines += recordType("CD_\(entity.name)", fields: fields)
        }
        if includeLastPlayed {
            let fields = ["\"___createTime\" TIMESTAMP", "\"___createdBy\" REFERENCE", "\"___etag\" STRING",
                          "\"___modTime\" TIMESTAMP", "\"___modifiedBy\" REFERENCE",
                          "\"___recordID\" REFERENCE QUERYABLE"] + lastPlayedFields.map { "\($0.name) \($0.type)" }
            lines += recordType(GFCloudConfig.lastPlayedRecordType, fields: fields)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func recordType(_ name: String, fields: [String]) -> [String] {
        ["    RECORD TYPE \(name) ("] + fields.map { "        \($0)," } + [
            "        GRANT WRITE TO \"_creator\",", "        GRANT CREATE TO \"_icloud\",",
            "        GRANT READ TO \"_world\"", "    );", ""
        ]
    }

    private static func cloudType(_ type: AttributeType) -> String {
        switch type {
        case .string, .uuid, .uri: "STRING"
        case .integer, .bool: "INT64"
        case .double: "DOUBLE"
        case .date: "TIMESTAMP"
        case .binary: "BYTES"
        }
    }
}
