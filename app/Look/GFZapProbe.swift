#if DEBUG
    import Foundation
    import KSPlayer

    /// Test support (Debug builds only, never in a TestFlight build; LumeTests does not link KSPlayer itself): drives
    /// KSPlayer's FFmpeg player the way Lume's channel change does — the layer gets the next channel's URL and replaces
    /// its player item (`KSMEPlayer.replace`).
    @MainActor
    final class GFZapProbe {
        private let layer: KSPlayerLayer

        init(url: URL) {
            KSOptions.firstPlayerType = KSMEPlayer.self
            layer = KSPlayerLayer(url: url, isAutoPlay: true, options: KSOptions())
        }

        func switchTo(_ url: URL) {
            layer.set(url: url, options: KSOptions())
        }

        func stop() {
            layer.stop()
        }
    }
#endif
