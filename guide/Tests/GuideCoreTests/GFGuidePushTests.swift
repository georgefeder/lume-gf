import Foundation
@testable import GuideCore
import Testing

struct GFGuidePushTests {
    private let guide = "https://dispatcharr.example.org/xmltv.php?username=u&password=p"
    private let token = "00ff10ab"

    @Test func `the token is told to the guide's own Dispatcharr host, never its login`() throws {
        let url = try #require(GFGuidePush.reportURL(guideURLs: ["https://other.example.org/epg.xml", guide],
                                                     device: "iphone", build: "61", token: token))
        #expect(url.absoluteString == "https://dispatcharr.example.org/gf-push?d=iphone&b=61&t=00ff10ab")
    }

    @Test func `a guide from another server is not told`() {
        #expect(GFGuidePush.reportURL(guideURLs: ["https://other.example.org/epg.xml"], device: "iphone",
                                      build: "61", token: token) == nil)
        #expect(GFGuidePush.reportURL(guideURLs: [], device: "iphone", build: "61", token: token) == nil)
    }

    @Test func `told again for a new token or build, or after a day`() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let last = GFGuidePush.Reported(token: token, build: "61", at: now.addingTimeInterval(-3600))
        #expect(GFGuidePush.shouldReport(token: token, build: "61", last: nil, now: now))
        #expect(GFGuidePush.shouldReport(token: token, build: "61", last: last, now: now) == false)
        #expect(GFGuidePush.shouldReport(token: "11", build: "61", last: last, now: now))
        #expect(GFGuidePush.shouldReport(token: token, build: "62", last: last, now: now))
        #expect(GFGuidePush.shouldReport(token: token, build: "61", last: last, now: now.addingTimeInterval(86400)))
    }

    @Test func `only pushes marked as the guide's are ours`() {
        #expect(GFGuidePush.isGuidePush(["aps": ["content-available": 1], "gf": "guide"]))
        // compared with false: swift-testing's #expect(!call(...)) did not evaluate the call (CI run 43540722084)
        let iCloud: [AnyHashable: Any] = ["aps": ["content-available": 1], "ck": ["cid": "x"]]
        #expect(GFGuidePush.isGuidePush(iCloud) == false)
    }

    @Test func `a token prints as lowercase hex`() {
        #expect(GFGuidePush.hex(Data([0x00, 0xFF, 0x10, 0xAB])) == "00ff10ab")
    }
}
