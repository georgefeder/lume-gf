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

    static let lumeEntities: [Entity] = []

    public static func ckdb() -> String {
        ""
    }

    static func ckdb(entities _: [Entity], includeLastPlayed _: Bool = false) -> String {
        ""
    }
}
