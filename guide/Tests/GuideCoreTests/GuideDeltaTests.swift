import Foundation
@testable import GuideCore
import Testing

struct GuideDeltaTests {
    private func file(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "GuideDeltaTests-\(UUID().uuidString).xml")
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test func `a change file's builds and removals are read, escaped names undone`() throws {
        let url = try file("""
        <?xml version="1.0" encoding="UTF-8"?>
        <tv gf-delta-since="1794676320" gf-build="1794680850">
        <gf-removed channel="42161" start="20261114183000 +0000"/>
        <gf-removed channel="A&amp;B" start="20261115064500 +0000"/>
        <programme channel="42161" start="20261115170000 +0000" stop="20261115180000 +0000"><title>News</title></programme>
        </tv>
        """)
        defer { try? FileManager.default.removeItem(at: url) }
        let header = try #require(GuideDelta.header(ofFileAt: url))
        #expect(header.since == 1_794_676_320 && header.build == 1_794_680_850)
        #expect(header.removed == [.init(channel: "42161", start: "20261114183000 +0000"),
                                   .init(channel: "A&B", start: "20261115064500 +0000")])
    }

    @Test func `a full guide is not a change file`() throws {
        let url = try file("""
        <?xml version="1.0" encoding="UTF-8"?>
        <tv generator-info-name="x"><channel id="1"/><programme channel="1" start="20261115170000 +0000" \
        stop="20261115180000 +0000"><title>News</title></programme></tv>
        """)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(GuideDelta.header(ofFileAt: url) == nil)
    }

    @Test func `the build the device has is added to the guide's address, the rest untouched`() {
        let login = "https://dispatcharr.example.org/xmltv.php?username=u&password=p%2Bq"
        #expect(GuideDelta.url(login, since: 17) == login + "&gf_since=17")
        #expect(GuideDelta.url("https://example.org/epg.xml", since: 17) == "https://example.org/epg.xml?gf_since=17")
    }
}
