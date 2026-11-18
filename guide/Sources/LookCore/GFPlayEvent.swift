import Foundation

/// One moment of a live play for the server (Georgs through the Oracle Admin, 18 Nov 2026: "more analysis ... more
/// reliable, start faster"): the server records every live play once a second but cannot see the player, so the player
/// says when it stalls, why it opens a channel again, and how much it has buffered. Sent as a GET of `/gf-play` on the
/// channel's own Dispatcharr host and read from Traefik's access log, joined with the server's record by time and
/// channel number. The query carries fixed words and numbers only: no address, login or channel name.
nonisolated struct GFPlayEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The player opens the channel (each open, the same channel again too).
        case open
        /// The first picture, `ms` after the open.
        case picture(ms: Int)
        /// Playing again after buffering for `ms`.
        case stall(ms: Int)
        /// The player opens the stream again, or hands it to another engine.
        case reopen(Reopen)
        /// Seconds of video buffered ahead, some time after the first picture.
        case buffer(seconds: Double)
        /// The stream could not start (no picture, or the engine gave up).
        case failed
        /// The player closed the stream (the viewer left it, changed channel, or it opens again).
        case close
    }

    /// Why the player opened the stream again.
    enum Reopen: String, Sendable {
        /// The stream reported an error, or ended (a live stream's playlist gone).
        case error, ended
        /// Stuck buffering past the stall watchdog's limit.
        case stallWatchdog = "stall-watchdog"
        /// Picture and sound drifted apart for good.
        case clockDrift = "clock-drift"
        /// The viewer pressed Try Again.
        case retryButton = "retry-button"
        /// Another engine takes over (the first one could not start it).
        case engine
        /// The HLS address tried as MPEG-TS after it failed.
        case tsRetry = "ts-retry"
    }

    let kind: Kind
    /// The stream, by its address's last part ("12345.ts"); never the address itself.
    let stream: String
    /// When it happened, milliseconds since 1970.
    let at: Int64
    /// The player session (a few letters, new on each open), so events of one play group together.
    let session: String
    var lowLatency: Bool?
    var liveBuffer: Int?

    /// The channel's number: the digits of the stream's last part before its extension, none when it has none.
    var channelNumber: String? {
        let name = stream.split(separator: ".").first.map(String.init) ?? stream
        let digits = name.filter(\.isNumber)
        return digits.isEmpty ? nil : String(digits)
    }

    func query(device: String, build: String) -> String {
        var items: [String]
        switch kind {
        case .open: items = ["ev=open"]
        case let .picture(ms): items = ["ev=pic", "ms=\(ms)"]
        case let .stall(ms): items = ["ev=stall", "ms=\(ms)"]
        case let .reopen(why): items = ["ev=reopen", "why=\(why.rawValue)"]
        case let .buffer(seconds): items = ["ev=buf", "s=\(String(format: "%.1f", seconds))"]
        case .failed: items = ["ev=fail"]
        case .close: items = ["ev=close"]
        }
        if let channelNumber { items.append("ch=\(channelNumber)") }
        items += ["t=\(at)", "id=\(session.filter { $0.isLetter || $0.isNumber })", "d=\(device)",
                  "b=\(build.filter { $0.isNumber || $0 == "." })"]
        if let lowLatency { items.append("ll=\(lowLatency ? 1 : 0)") }
        if let liveBuffer { items.append("lb=\(liveBuffer)") }
        return items.joined(separator: "&")
    }
}
