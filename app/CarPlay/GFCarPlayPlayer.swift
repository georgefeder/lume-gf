#if os(iOS)
    import AVFoundation
    import MediaPlayer
    import os

    /// Lume GF: plays a channel picked on CarPlay or HomeView. Apple's player only, because CarPlay video is AirPlay video
    /// (developer.apple.com/documentation/carplay/video): the system shows this AVPlayer on the car's or HomeView's
    /// screen, and as sound only while the car is moving. Lume's own engines draw into the phone's views and can't
    /// reach that screen.
    @MainActor
    final class GFCarPlayPlayer {
        static let shared = GFCarPlayPlayer()

        /// Called when the channel's stream fails to open (an address Dispatcharr refuses, the provider line busy), with
        /// a short line on why (the player's state and its last error) to show under the message.
        var onFailure: ((GFCarPlayCatalog.Channel, String) -> Void)?

        /// How long a channel may take to start before the car shows why it hasn't (it keeps trying meanwhile).
        private static let startTimeout: Duration = .seconds(15)

        /// Whether the car or HomeView takes video at all (CPSessionConfiguration), set by the scene; shown in the
        /// diagnosis line.
        var videoSupported: Bool?

        private let player = AVPlayer()
        /// The tapped row's completion: CarPlay spins on the row until it runs, so it runs once the channel plays (or
        /// fails, or the start check reports), not straight away (developer.apple.com/documentation/carplay/cplistitem/handler).
        private var started: (() -> Void)?
        private var playingObservation: NSKeyValueObservation?
        nonisolated private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "lume", category: "carplay")
        /// Why the player last stopped or failed to start (AVPlayer's rate change reason, the audio session's error):
        /// in the diagnosis line and the log.
        private var lastRateReason = ""
        private var audioError = ""
        private var rateObserver: NSObjectProtocol?
        private(set) var channelID: String?
        private var statusObservation: NSKeyValueObservation?
        private var startTask: Task<Void, Never>?
        /// Hands this player to the system, so CarPlay and HomeView know which player's video to show (and publishes
        /// Now Playing from it).
        private lazy var session: MPNowPlayingSession = {
            let session = MPNowPlayingSession(players: [player])
            session.automaticallyPublishesNowPlayingInfo = false // the channel and programme, set below
            return session
        }()

        private init() {
            player.allowsExternalPlayback = true
            player.usesExternalPlaybackWhileExternalScreenIsActive = true
            player.automaticallyWaitsToMinimizeStalling = true
            rateObserver = NotificationCenter.default.addObserver(
                forName: AVPlayer.rateDidChangeNotification, object: player, queue: .main
            ) { [weak self] note in
                let reason = (note.userInfo?[AVPlayer.rateDidChangeReasonKey] as? AVPlayer.RateDidChangeReason)
                let name = switch reason {
                case .setRateCalled: "set"
                case .setRateFailed: "set failed"
                case .audioSessionInterrupted: "interrupted"
                case .appBackgrounded: "backgrounded"
                default: reason?.rawValue ?? "?"
                }
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.lastRateReason = "rate \(self.player.rate) \(name)"
                    Self.log.notice("CarPlay player \(self.lastRateReason, privacy: .public)")
                }
            }
        }

        /// Starts `channel`; the same channel again only resumes it. `started` runs once it plays or can't.
        func play(_ channel: GFCarPlayCatalog.Channel, programme: String?, started: @escaping () -> Void) {
            guard let url = channel.hlsURL else { started(); onFailure?(channel, ""); return }
            if channelID == channel.id, player.currentItem != nil || startTask != nil {
                player.play()
                started()
                return
            }
            stop()
            channelID = channel.id
            self.started = started
            playingObservation = player.observe(\.timeControlStatus) { [weak self] player, _ in
                Self.log.notice("CarPlay player status \(player.timeControlStatus.rawValue, privacy: .public)")
                guard player.timeControlStatus == .playing else { return }
                Task { @MainActor in self?.finishStart() }
            }
            GFCarPlayCatalog.markWatched(channelID: channel.id)
            startTask = Task { [weak self] in
                // one Dispatcharr session per channel: AVPlayer opens the channel's address two or three times as it
                // starts, and each open of the 302 starts another HLS session (seen 21 Nov 2026)
                let resolved = await Self.resolveRedirect(url)
                guard let self, !Task.isCancelled, self.channelID == channel.id else { return }
                self.start(resolved, channel: channel, programme: programme)
                try? await Task.sleep(for: Self.startTimeout)
                guard !Task.isCancelled, self.channelID == channel.id,
                      self.player.timeControlStatus != .playing else { return }
                self.finishStart()
                self.onFailure?(channel, self.diagnosis())
            }
        }

        private func start(_ url: URL, channel: GFCarPlayCatalog.Channel, programme: String?) {
            let audio = AVAudioSession.sharedInstance()
            lastRateReason = ""
            audioError = ""
            do {
                try audio.setCategory(.playback, mode: .moviePlayback, options: [])
                try audio.setActive(true)
            } catch {
                audioError = "audio \((error as NSError).code)"
                Self.log.error("CarPlay player: audio session \(error.localizedDescription, privacy: .public)")
            }
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 4 // live: as the app's AVPlayer engine does
            statusObservation = item.observe(\.status) { [weak self] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor in
                    guard let self, self.channelID == channel.id else { return }
                    let why = self.diagnosis()
                    self.stop()
                    self.onFailure?(channel, why)
                }
            }
            player.replaceCurrentItem(with: item)
            session.becomeActiveIfPossible { _ in }
            player.play()
            publishNowPlaying(channel, programme: programme)
        }

        private func finishStart() {
            playingObservation = nil
            started?()
            started = nil
        }

        func stop() {
            finishStart()
            startTask?.cancel()
            startTask = nil
            statusObservation = nil
            player.pause()
            player.replaceCurrentItem(with: nil)
            guard channelID != nil else { return }
            channelID = nil
            session.nowPlayingInfoCenter.nowPlayingInfo = nil
        }

        /// Dispatcharr answers a channel's `.m3u8` with a 302 to its session's playlist (`/proxy/hls/<token>/`). Asked
        /// once here, so the player gets the session's own address; the channel's address as it is when there is no
        /// redirect or the request fails.
        private static func resolveRedirect(_ url: URL) async -> URL {
            let request = URLRequest(url: url, timeoutInterval: 10)
            let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
            defer { session.invalidateAndCancel() } // headers only: a 200 here would be the stream itself
            guard let (_, response) = try? await session.bytes(for: request),
                  let http = response as? HTTPURLResponse, (300 ..< 400).contains(http.statusCode),
                  let location = http.value(forHTTPHeaderField: "Location"),
                  let target = URL(string: location, relativeTo: url)?.absoluteURL else { return url }
            return target
        }


        /// One short line on where the player got stuck, shown in the car so a photo of it says what went wrong: item
        /// status, what the player waits for, segments loaded, the last error, whether AirPlay video took it.
        private func diagnosis() -> String {
            guard let item = player.currentItem else { return "no item" }
            let status = switch item.status {
            case .readyToPlay: "ready"
            case .failed: "failed"
            default: "unknown"
            }
            var parts = ["item \(status)"]
            if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                parts.append("waiting \(player.reasonForWaitingToPlay?.rawValue ?? "?")")
            } else if player.timeControlStatus == .paused {
                parts.append("paused")
            }
            if let access = item.accessLog()?.events.last {
                parts.append("segs \(access.numberOfMediaRequests), stalls \(access.numberOfStalls)")
            }
            if let error = item.error as NSError? {
                parts.append("err \(error.domain) \(error.code)")
            } else if let event = item.errorLog()?.events.last {
                parts.append("err \(event.errorDomain) \(event.errorStatusCode) \(event.errorComment ?? "")")
            }
            if !lastRateReason.isEmpty { parts.append(lastRateReason) }
            if !audioError.isEmpty { parts.append(audioError) }
            parts.append(player.isExternalPlaybackActive ? "airplay on" : "airplay off")
            if let videoSupported { parts.append(videoSupported ? "video ok" : "no video") }
            return parts.joined(separator: " · ")
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
            session.nowPlayingInfoCenter.nowPlayingInfo = info
        }
    }

    /// Stops at the first redirect, for GFCarPlayPlayer.resolveRedirect (a file-level class with the completion-handler
    /// form: Swift 6.3 crashed emitting the async form inside the player, run 44892380804).
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
            newRequest _: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) { completionHandler(nil) }
    }
#endif
