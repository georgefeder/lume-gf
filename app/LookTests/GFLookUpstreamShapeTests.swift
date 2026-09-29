import Foundation
@testable import Lume
import SwiftUI
import Testing

/// Tripwire: what Lume GF's look builds on. A Lume release that changes these makes this fail (or not compile), so
/// the build stops before the upload instead of shipping a half-working look.
@MainActor
struct GFLookUpstreamShapeTests {
    @Test func `Lume's badge pieces take a font size`() {
        _ = LiveBadge(fontSize: 11)
        _ = StatusCapsule(fontSize: 11, tint: .secondary) { Text(verbatim: "FHD") }
    }

    @Test func `the guide sizes the glass layout uses exist`() {
        let metrics = EPGMetrics.current
        #expect(metrics.channelColumnWidth > 0 && metrics.rowHeight > 0 && metrics.rowSpacing >= 0)
        #expect(metrics.headerHeight > 0)
    }

    @Test func `a guide row still carries the channel's raw name`() {
        let stream = LiveStream(id: "t-live-1", streamId: 1, name: "BBC One FHD")
        let timeline = EPGTimeline.live(now: .now, pointsPerMinute: 3, hoursBehind: 1)
        let rows = EPGGridBuilder.rows(streams: [stream], cellsByChannel: [:], timeline: timeline)
        #expect(rows.first?.name == "BBC One FHD")
    }
}
