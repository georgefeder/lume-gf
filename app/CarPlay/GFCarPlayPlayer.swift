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

        private let player = AVPlayer()
        private(set) var channelID: String?

        private init() {
            player.allowsExternalPlayback = true
            player.usesExternalPlaybackWhileExternalScreenIsActive = true
            player.automaticallyWaitsToMinimizeStalling = true
        }

        /// Starts `channel`, or does nothing when it has no address Apple's player can open (false).
        @discardableResult
        func play(_ channel: GFCarPlayCatalog.Channel, programme: String?) -> Bool {
            guard let url = GFCarPlayCatalog.hlsURL(forChannelID: channel.id) else { return false }
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .moviePlayback, options: [])
            try? session.setActive(true)
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 4 // live: as the app's AVPlayer engine does
            player.replaceCurrentItem(with: item)
            player.play()
            channelID = channel.id
            GFCarPlayCatalog.markWatched(channelID: channel.id)
            publishNowPlaying(channel, programme: programme)
            return true
        }

        func stop() {
            player.pause()
            player.replaceCurrentItem(with: nil)
            channelID = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }

        /// What the car's Now Playing and mini player show: the channel and the programme on now, marked live.
        private func publishNowPlaying(_ channel: GFCarPlayCatalog.Channel, programme: String?) {
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
