import Foundation
@testable import Lume
import SwiftData
import Testing

/// How soon a day-old guide shows what is on now (Georgs, 9 Oct: the iPhone's guide took a minute to come in). Runs on
/// its own after the parallel run (app-tests-alone.txt) so the times mean something; the times are printed for the log.
struct GuideNowFirstTimingTests {
    let now = Date(timeIntervalSince1970: 1_790_640_000)

    @Test func `a day-old guide shows what is on now well before the whole file is in`() throws {
        let container = try makeTestContainer()
        let channels = Set((0 ..< 2000).map { "ch\($0)" })
        let index = GuideStoredIndex(rows: [:])
        let applier = GuideListingApplier(container: container)
        let dayAgo = now.addingTimeInterval(-24 * 3600)
        func day(from start: Date) -> [GuideTestProgramme] { // 26 hourly programmes a channel, from 2 h before start
            channels.flatMap { hourly($0, from: start.addingTimeInterval(-2 * 3600), count: 26) }
        }
        let old = try writeGuideFile(day(from: dayAgo))
        _ = applier.apply(fileURL: old, claimableChannels: channels, index: index, now: dayAgo)
        #expect(GuideDiffPlanner.wantsNowFirst(stored: index.rows, channels: channels, now: now))

        let new = try writeGuideFile(day(from: now))
        let started = Date()
        var nowReady: TimeInterval = -1
        let result = applier.apply(fileURL: new, claimableChannels: channels, index: index, now: now,
                                   nowFirst: DateInterval(start: now, duration: GuideDiffPlanner.nowFirstSpan),
                                   onNowReady: { nowReady = Date().timeIntervalSince(started) })
        let total = Date().timeIntervalSince(started)
        print(String(format: "Lume GF guide timing: 52,000 programmes, on now after %.1f s, all in after %.1f s",
                     nowReady, total))
        #expect(result.completed && nowReady > 0 && nowReady < total)
        let at = now
        let onNow = try ModelContext(container).fetchCount(FetchDescriptor<EPGListing>(
            predicate: #Predicate { $0.start <= at && $0.end > at }
        ))
        #expect(onNow == 2000)
    }
}
