import Foundation
@testable import Lume
import SwiftData
import Testing

/// Tripwire: Lume GF's guide import writes exactly these fields. When a Lume release changes the guide's stored
/// fields, its parsed programme or its guide schema version, this fails and the build stops before the upload, so the
/// import is updated instead of silently leaving new guide data out.
struct GuideUpstreamShapeTests {
    @Test func `the stored guide fields are the ones our import writes`() {
        let names = Schema([EPGListing.self]).entities.first?.attributes.map(\.name).sorted()
        #expect(names == ["category", "channelId", "end", "id", "listingDescription", "start", "subtitle", "title"])
    }

    @Test func `a parsed programme has the fields our import reads`() {
        let p = ParsedProgramme(channelId: "c", title: "t", subtitle: nil, description: "", categories: [],
                                start: .now, end: .now)
        #expect(Mirror(reflecting: p).children.compactMap(\.label).sorted()
            == ["categories", "channelId", "description", "end", "start", "subtitle", "title"])
    }

    @Test func `the guide schema version is the one our import knows`() {
        #expect(SyncFrequency.epgCurrentSchemaVersion == 2)
    }
}
