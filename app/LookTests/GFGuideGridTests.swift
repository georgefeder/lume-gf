import Foundation
@testable import Lume
import Testing

/// The guide grid re-renders when the glass layout changes: its Equatable gate compares the pad, the bottom room and
/// the guide's height.
@MainActor
struct GFGuideGridTests {
    let timeline = EPGTimeline.live(now: Date(timeIntervalSince1970: 1_790_640_709), pointsPerMinute: 3, hoursBehind: 1)

    func grid(pad: CGFloat, bottom: CGFloat, guide: CGFloat = 722) -> EPGGrid {
        EPGGrid(rows: [], timeline: timeline, metrics: .current, now: timeline.start, sync: EPGScrollSync(),
                dataVersion: 0, nowTarget: 0, scrollRequest: nil, virtualFocus: nil, contentPad: pad,
                bottomRoom: bottom, guideHeight: guide, onPlay: { _, _ in }, onShowDetails: { _, _ in })
    }

    @Test func `a new bottom room, pad or guide height re-renders the grid`() {
        #expect(grid(pad: 136, bottom: 119) == grid(pad: 136, bottom: 119))
        #expect(grid(pad: 136, bottom: 119) != grid(pad: 136, bottom: 60))
        #expect(grid(pad: 136, bottom: 119) != grid(pad: 0, bottom: 119))
        #expect(grid(pad: 136, bottom: 119) != grid(pad: 136, bottom: 119, guide: 620))
    }
}
