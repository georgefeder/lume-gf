import Foundation
import KSPlayer
@testable import Lume
import Testing

/// A live channel's stream check is short; films and series keep FFmpeg's own (GFLiveProbe).
@MainActor
struct GFLiveProbeTests {
    private func media(_ kind: PlayableMedia.Kind) -> PlayableMedia {
        PlayableMedia(id: "gf-probe-test", url: URL(string: "http://127.0.0.1:9/1.ts")!, title: "Test", subtitle: nil,
                      posterURL: nil, kind: kind, startTime: 0, contentRef: .live("gf-probe-test"))
    }

    @Test func `a live channel reads about a megabyte and a second, a film what FFmpeg reads by default`() {
        let live = KSPlayerOptionsFactory.make(for: media(.live))
        #expect(live.probesize == GFLiveProbe.size)
        #expect(live.maxAnalyzeDuration == GFLiveProbe.duration)
        let film = KSPlayerOptionsFactory.make(for: media(.vod))
        #expect(film.probesize == nil)
        #expect(film.maxAnalyzeDuration == nil)
    }

    @Test func `Low Latency stays off, even where it was switched on before`() {
        let key = PlayerSettings.KSPlayer.noBufferKey
        let before = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(before, forKey: key) }
        UserDefaults.standard.set(true, forKey: key)
        #expect(!KSPlayerOptions.load().noBuffer)
        #expect(!KSPlayerOptionsFactory.make(for: media(.live)).nobuffer)
    }
}
