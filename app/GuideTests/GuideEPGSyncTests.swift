import Foundation
@testable import Lume
import SwiftData
import Testing

/// Lume's own guide loader with our refresher: the stored guide must survive a failed download.
struct GuideEPGSyncTests {
    @Test func `a failed download keeps the stored guide`() async throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let now = Date()
        context.insert(LiveStream(id: "l-1", streamId: 1, name: "One", epgChannelId: "c1"))
        context.insert(EPGListing(id: GuideDiffPlanner.id(channelId: "c1", start: now), channelId: "c1", title: "Kept",
                                  listingDescription: "", start: now, end: now.addingTimeInterval(3600)))
        let missing = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).xml")
        context.insert(EPGSource(name: "Gone", url: missing.absoluteString))
        try context.save()
        _ = await EPGSyncManager(modelContainer: container).syncAllSources()
        let titles = try ModelContext(container).fetch(FetchDescriptor<EPGListing>()).map(\.title)
        #expect(titles == ["Kept"])
    }

    @Test func `two sources on the same channels both record a check`() async throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let hourStart = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 3600).rounded(.down) * 3600)
        context.insert(LiveStream(id: "l-1", streamId: 1, name: "One", epgChannelId: "c1"))
        let file = try writeGuideFile(hourly("c1", from: hourStart, count: 2))
        let first = EPGSource(name: "First", url: file.absoluteString)
        context.insert(first)
        try context.save()
        let second = EPGSource(name: "Second", url: file.absoluteString) // added later: its channels are all claimed
        context.insert(second)
        try context.save()
        _ = await EPGSyncManager(modelContainer: container).syncAllSources()
        let states = [first.id, second.id].map { GuideSourceStateStore.shared.state(for: $0) }
        #expect(states.allSatisfy { $0.lastCheck != nil })
        #expect(GuideClock.nextCheck(states: states, followServer: true, interval: 86400) > Date())
    }

    @Test func `a new guide file is applied on top of the stored one`() async throws {
        let container = try makeTestContainer()
        let context = ModelContext(container)
        let hourStart = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 3600).rounded(.down) * 3600)
        context.insert(LiveStream(id: "l-1", streamId: 1, name: "One", epgChannelId: "c1"))
        let file = try writeGuideFile(hourly("c1", from: hourStart, count: 3))
        context.insert(EPGSource(name: "Local", url: file.absoluteString))
        try context.save()
        let manager = EPGSyncManager(modelContainer: container)
        #expect(await manager.syncAllSources())
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<EPGListing>()) == 3)
        #expect(await manager.syncAllSources())
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<EPGListing>()) == 3)
    }
}
