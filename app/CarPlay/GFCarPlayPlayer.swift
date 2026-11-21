#if os(iOS)
    import AVFoundation
    import MediaPlayer
    import os
    import UIKit

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
        private var commandTargets: [(MPRemoteCommand, Any)] = []
        private let videoLayer = AVPlayerLayer()
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
                await self.start(resolved, channel: channel, programme: programme)
                try? await Task.sleep(for: Self.startTimeout)
                guard !Task.isCancelled, self.channelID == channel.id,
                      self.player.timeControlStatus != .playing else { return }
                self.finishStart()
                self.onFailure?(channel, self.diagnosis())
            }
        }

        /// Order matters: HomeView lets only an app that can be the Now Playing app start sound (audiomxd, 21 Nov 2026:
        /// "Disallow session activation because it has PebbleInteraction predicted routes and it is NOT eligible to
        /// become the NowPlayingApp", canBeNowPlayingApp NO). So the Now Playing info and the play/pause commands are
        /// in place and the now-playing session is active before the audio session starts.
        private func start(_ url: URL, channel: GFCarPlayCatalog.Channel, programme: String?) async {
            lastRateReason = ""
            audioError = ""
            publishNowPlaying(channel, programme: programme)
            registerCommands()
            let active = await session.becomeActiveIfPossible()
            guard !Task.isCancelled, channelID == channel.id else { return }
            Self.log.notice("CarPlay player: now-playing session active \(active, privacy: .public)")
            if !active { audioError = "session inactive" }
            let audio = AVAudioSession.sharedInstance()
            do {
                // long-form video: the video routing context (AirPlay video to the HomeView/car screen); without it a
                // Now Playing app lands in System Music, and HomeView took the stream as audio only (21 Nov 2026:
                // "opted into system music due to now playing capability", Now Playing screen with no picture)
                try audio.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo, options: [])
                try audio.setActive(true)
            } catch {
                let code = (error as NSError).code
                let state = UIApplication.shared.applicationState.rawValue
                Self.log.error(
                    "CarPlay player: audio session \((error as NSError).domain, privacy: .public) \(code, privacy: .public), app state \(state, privacy: .public)"
                )
                audioError += (audioError.isEmpty ? "" : " ") + "audio \(Self.fourCC(code)) app \(state)"
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
            attachVideoLayer()
            player.play()
        }

        /// AirPlay sends video only for a player that has a video layer; without one the receiver gets the stream as
        /// sound (HomeView, 21 Nov 2026: AirPlay video active, but only an audio Now Playing card). So a 1-point,
        /// invisible layer on the phone's window carries the player while the car or HomeView shows the picture.
        private func attachVideoLayer() {
            videoLayer.player = player
            guard videoLayer.superlayer == nil,
                  let window = UIApplication.shared.connectedScenes
                      .compactMap({ $0 as? UIWindowScene })
                      .flatMap(\.windows).first(where: \.isKeyWindow) else { return }
            videoLayer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            videoLayer.opacity = 0.01
            window.layer.addSublayer(videoLayer)
        }

        /// Play, pause, toggle and stop for the car's and HomeView's controls, on the now-playing session's command
        /// centre and the app's shared one (the system counts an app with no command handlers as unable to be the Now
        /// Playing app). Removed again in stop(); Lume's own player adds and removes its own (NowPlayingService).
        private func registerCommands() {
            guard commandTargets.isEmpty else { return }
            for center in [session.remoteCommandCenter, MPRemoteCommandCenter.shared()] {
                let handlers: [(MPRemoteCommand, () -> Void)] = [
                    (center.playCommand, { [weak self] in self?.player.play() }),
                    (center.pauseCommand, { [weak self] in self?.player.pause() }),
                    (center.togglePlayPauseCommand, { [weak self] in
                        guard let player = self?.player else { return }
                        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
                    }),
                    (center.stopCommand, { [weak self] in self?.stop() }),
                ]
                for (command, action) in handlers {
                    command.isEnabled = true
                    let target = command.addTarget { _ in
                        MainActor.assumeIsolated { action() }
                        return .success
                    }
                    commandTargets.append((command, target))
                }
            }
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
            videoLayer.player = nil
            videoLayer.removeFromSuperlayer()
            guard channelID != nil else { return }
            channelID = nil
            session.nowPlayingInfoCenter.nowPlayingInfo = nil
            // the app's own player owns the shared Now Playing while it is up (NowPlayingService)
            if NowPlayingService.shared.currentMedia == nil { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
            for (command, target) in commandTargets { command.removeTarget(target) }
            commandTargets = []
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


        /// An OSStatus as its four letters when it is one ('!pla'), else the number.
        private static func fourCC(_ code: Int) -> String {
            let value = UInt32(truncatingIfNeeded: code)
            let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
            guard bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return String(code) }
            return "'" + String(decoding: bytes, as: UTF8.self) + "'"
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
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
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
