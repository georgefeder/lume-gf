#if os(iOS)
    import AVFoundation
    import MediaPlayer

    /// Lume GF: plays a channel picked on CarPlay or HomeView. Apple's player only, because CarPlay video is AirPlay video
    /// (developer.apple.com/documentation/carplay/video): the system shows this AVPlayer on the car's or HomeView's
    /// screen, and as sound only while the car is moving. Lume's own engines draw into the phone's views and can't
    /// reach that screen.
    @MainActor
    final class GFCarPlayPlayer {
        static let shared = GFCarPlayPlayer()

        /// Called when the channel's stream fails to open (an address Dispatcharr refuses, the provider line busy).
        var onFailure: ((GFCarPlayCatalog.Channel) -> Void)?

        private let player = AVPlayer()
        private(set) var channelID: String?
        private var statusObservation: NSKeyValueObservation?

        private init() {
            player.allowsExternalPlayback = true
            player.usesExternalPlaybackWhileExternalScreenIsActive = true
            player.automaticallyWaitsToMinimizeStalling = true
        }

        /// Starts `channel`; the same channel again only resumes it.
        func play(_ channel: GFCarPlayCatalog.Channel, programme: String?) {
            guard let url = channel.hlsURL else { onFailure?(channel); return }
            if channelID == channel.id, player.currentItem != nil {
                player.play()
                return
            }
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .moviePlayback, options: [])
            try? session.setActive(true)
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 4 // live: as the app's AVPlayer engine does
            statusObservation = item.observe(\.status) { [weak self] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor in
                    guard let self, self.channelID == channel.id else { return }
                    self.stop()
                    self.onFailure?(channel)
                }
            }
            player.replaceCurrentItem(with: item)
            player.play()
            channelID = channel.id
            GFCarPlayCatalog.markWatched(channelID: channel.id)
            publishNowPlaying(channel, programme: programme)
        }

        func stop() {
            statusObservation = nil
            player.pause()
            player.replaceCurrentItem(with: nil)
            guard channelID != nil else { return }
            channelID = nil
            // the app's own player owns Now Playing while it is up (NowPlayingService)
            if NowPlayingService.shared.currentMedia == nil { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
        }

        /// What the car's Now Playing and mini player show: the channel and the programme on now, marked live. Left to
        /// the app's own player while that is up.
        private func publishNowPlaying(_ channel: GFCarPlayCatalog.Channel, programme: String?) {
            guard NowPlayingService.shared.currentMedia == nil else { return }
            var info: [String: Any] = [
                MPMediaItemPropertyTitle: programme ?? channel.title,
                MPNowPlayingInfoPropertyIsLiveStream: true,
                MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
                MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            ]
            if programme != nil { info[MPMediaItemPropertyArtist] = channel.title }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
#endif
