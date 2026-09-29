import Foundation
@testable import Lume
import Testing

struct GuideParseCheckedTests {
    let t0 = Date(timeIntervalSince1970: 1_790_640_000)

    @Test func `a complete file is read to the end`() throws {
        let file = try writeGuideFile(hourly("c1", from: t0, count: 3))
        var got = 0
        let result = XMLTVParser.parseChecked(fileURL: file) { got += $0.count }
        #expect(result.completed && result.count == 3 && got == 3)
    }

    @Test func `a cut-off file is reported as incomplete`() throws {
        let file = try writeGuideFile(hourly("c1", from: t0, count: 5), cut: true)
        var got = 0
        let result = XMLTVParser.parseChecked(fileURL: file) { got += $0.count }
        #expect(!result.completed)
        #expect(got >= 1 && got < 5)
    }

    @Test func `asking to stop ends after the current batch`() throws {
        let file = try writeGuideFile(hourly("c1", from: t0, count: 5))
        var got = 0
        let result = XMLTVParser.parseChecked(fileURL: file, batchSize: 2, shouldStop: { true }) { got += $0.count }
        #expect(!result.completed && got == 2)
    }
}
