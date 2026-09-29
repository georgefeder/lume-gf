import Foundation
@testable import Lume
import Testing

/// Lume GF's zapping fix (docs/lume-gf/2026-09-29-live-tv-handover.md, finding 2; deps/KSPlayer): a channel change
/// closes the old channel's connection before the next one opens, so two TVs zapping on a two-connection account never
/// wait for each other.
@MainActor
struct GFZapTests {
    @Test(.timeLimit(.minutes(1)))
    func `a channel change closes the old stream before the next one opens`() async throws {
        let server = try GFTestStreamServer()
        defer { server.stop() }
        let probe = GFZapProbe(url: server.url("/a.ts"))
        defer { probe.stop() }
        #expect(await server.wait(for: .opened, path: "/a.ts", timeout: 15), "\(server.eventsDescription)")
        // the first channel is being read (FFmpeg is still analysing it)
        try await Task.sleep(for: .seconds(1))
        probe.switchTo(server.url("/b.ts"))
        #expect(await server.wait(for: .opened, path: "/b.ts", timeout: 15), "\(server.eventsDescription)")
        let events = server.events
        let oldClosed = try #require(events.first { $0.kind == .closed && $0.path == "/a.ts" },
                                     "the next channel opened while the old one was still connected: \(server.eventsDescription)")
        let nextOpened = try #require(events.first { $0.kind == .opened && $0.path == "/b.ts" })
        #expect(oldClosed.time <= nextOpened.time, "\(server.eventsDescription)")
        #expect(server.peakConnections == 1, "\(server.eventsDescription)")
    }

    @Test func `the test stream's tables carry a valid checksum`() {
        // CRC-32/MPEG-2 over a table including its own checksum is zero
        let table = GFTestTS.section(tableID: 0x00, id: 1, body: [0x00, 0x01, 0xF0, 0x00])
        #expect(GFTestTS.crc32(table) == 0)
        #expect(GFTestTS.chunk(counter: 0).count == 62 * 188)
    }
}
