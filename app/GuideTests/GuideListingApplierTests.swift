import Foundation
@testable import Lume
import SwiftData
import Testing

struct GuideListingApplierTests {
    let now = Date(timeIntervalSince1970: 1_790_640_000)

    func rows(_ container: ModelContainer) throws -> [EPGListing] {
        try ModelContext(container).fetch(FetchDescriptor<EPGListing>(sortBy: [SortDescriptor(\.start)]))
    }

    func apply(_ file: URL, _ container: ModelContainer, _ index: GuideStoredIndex, channels: Set<String> = ["c1"],
               shouldStop: @escaping () -> Bool = { false }) -> GuideListingApplier.Result {
        GuideListingApplier(container: container)
            .apply(fileURL: file, claimableChannels: channels, index: index, now: now, shouldStop: shouldStop)
    }

    @Test func `the same guide twice writes nothing the second time`() throws {
        let container = try makeTestContainer()
        let file = try writeGuideFile(hourly("c1", from: now, count: 4))
        let index = GuideStoredIndex(rows: GuideListingApplier(container: container).loadStored())
        let first = apply(file, container, index)
        let second = apply(file, container, index)
        #expect(first.inserted == 4 && first.completed)
        #expect(second.inserted == 0 && second.updated == 0 && second.deleted == 0 && second.completed)
        #expect(try rows(container).count == 4)
    }

    @Test func `a changed title is updated in place`() throws {
        let container = try makeTestContainer()
        let index = GuideStoredIndex(rows: [:])
        _ = apply(try writeGuideFile(hourly("c1", from: now, count: 2)), container, index)
        let result = apply(try writeGuideFile(hourly("c1", from: now, count: 2, title: "Changed")), container, index)
        #expect(result.updated == 2 && result.inserted == 0)
        #expect(try rows(container).map(\.title) == ["Changed 0", "Changed 1"])
    }

    @Test func `the hourly shift adds the new hour and keeps the past one`() throws {
        let container = try makeTestContainer()
        let index = GuideStoredIndex(rows: [:])
        _ = apply(try writeGuideFile(hourly("c1", from: now.addingTimeInterval(-3600), count: 3)), container, index)
        let result = apply(try writeGuideFile(hourly("c1", from: now, count: 3)), container, index)
        #expect(result.deleted == 0)
        #expect(try rows(container).count == 4)
    }

    @Test func `a programme gone from the covered span is removed`() throws {
        let container = try makeTestContainer()
        let index = GuideStoredIndex(rows: [:])
        let three = hourly("c1", from: now, count: 3)
        _ = apply(try writeGuideFile(three), container, index)
        let result = apply(try writeGuideFile([three[0], three[2]]), container, index)
        #expect(result.deleted == 1)
        #expect(try rows(container).map(\.title) == ["Show 0", "Show 2"])
    }

    @Test func `a cut-off file adds what it has and deletes nothing`() throws {
        let container = try makeTestContainer()
        let index = GuideStoredIndex(rows: [:])
        _ = apply(try writeGuideFile(hourly("c1", from: now, count: 3)), container, index)
        let result = apply(try writeGuideFile(hourly("c1", from: now.addingTimeInterval(7200), count: 4), cut: true),
                           container, index)
        #expect(!result.completed && result.deleted == 0)
        #expect(try rows(container).count >= 3)
    }

    @Test func `old programmes are cleared out`() throws {
        let container = try makeTestContainer()
        let index = GuideStoredIndex(rows: [:])
        let earlier = now.addingTimeInterval(-15 * 3600) // imported back when these were current
        _ = GuideListingApplier(container: container).apply(
            fileURL: try writeGuideFile(hourly("c1", from: earlier, count: 2)), claimableChannels: ["c1"],
            index: index, now: earlier)
        let result = apply(try writeGuideFile(hourly("c1", from: now, count: 1)), container, index)
        #expect(result.deleted == 2)
        #expect(try rows(container).count == 1)
    }

    @Test func `a full-size guide imports, a stopped import resumes, and a rerun writes nothing`() throws {
        let container = try makeTestContainer()
        let programmes = (0 ..< 3000).flatMap { hourly("ch\($0)", from: now, count: 5) } // 15,000
        let file = try writeGuideFile(programmes)
        let channels = Set((0 ..< 3000).map { "ch\($0)" })
        let index = GuideStoredIndex(rows: GuideListingApplier(container: container).loadStored())
        let stopped = apply(file, container, index, channels: channels, shouldStop: { true })
        #expect(!stopped.completed && stopped.inserted == 2000 && stopped.deleted == 0)
        let resumed = apply(file, container, index, channels: channels)
        #expect(resumed.completed && resumed.inserted == 13000)
        let again = apply(file, container, index, channels: channels)
        #expect(again.inserted == 0 && again.updated == 0 && again.deleted == 0)
        let fresh = GuideListingApplier(container: container).loadStored()
        #expect(fresh.count == 15000 && fresh == index.rows)
    }
}
