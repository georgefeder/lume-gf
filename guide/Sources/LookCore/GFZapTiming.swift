import Foundation

/// One channel change's timings, from KSPlayer's channel-change log (gfZapLog, deps/KSPlayer 0001, 0003, 0004), for
/// the server's report (Georgs, 4 Nov 2026, through the Glasgow Pi Admin chat: measure first, then make live channels
/// start faster). Each step in whole milliseconds since the change began; a step that did not happen is left out.
nonisolated struct GFZapTiming: Equatable, Sendable {
    enum Step: String, CaseIterable, Sendable {
        /// The old channel's input closed (the new one waits at most 1.5 s for it).
        case close
        /// The new channel's input opened, its stream info read, its decoders made.
        case open, info, dec
        /// Its first picture on screen, playable, and the next different frame drawn after that.
        case pic, play, move
    }

    /// The new channel's stream, by its address's last part ("12345.ts"); never the address itself.
    let stream: String
    /// When the change began, in seconds on the media clock.
    let started: Double
    /// The player's Low Latency switch (KSPlayer's nobuffer) and Live Buffer seconds for this change: the server
    /// cannot see them (Glasgow Pi Admin, 4 Nov: with Low Latency on, the first picture stood still 1 to 5 s).
    var lowLatency: Bool?
    var liveBuffer: Int?
    private(set) var steps: [Step: Int] = [:]
    /// Moving, failed, or the stream shut down: the timings are complete.
    private(set) var isOver = false

    init(stream: String, started: Double, lowLatency: Bool? = nil, liveBuffer: Int? = nil) {
        self.stream = stream
        self.started = started
        self.lowLatency = lowLatency
        self.liveBuffer = liveBuffer
    }

    /// Takes one log line, logged at `time`. Returns whether the change is over now.
    mutating func note(_ line: String, at time: Double) -> Bool {
        guard !isOver else { return true }
        let ms = Int(((time - started) * 1000).rounded())
        guard ms >= 0 else { return false }
        if line == "picture moving" {
            guard steps[.play] != nil else { return false }
            steps[.move] = steps[.move] ?? ms
            isOver = true
            return true
        }
        guard let space = line.firstIndex(of: " ") else { return false }
        let name = String(line[..<space])
        let rest = String(line[line.index(after: space)...])
        guard name == stream else {
            // another stream closing after the change began: the old channel
            if rest == "input closed" { set(.close, ms) }
            return false
        }
        if rest.hasPrefix("input opened (") {
            set(.open, ms)
            if let code = Self.code(in: rest), code < 0 { isOver = true }
        } else if rest.hasPrefix("stream info (") {
            set(.info, ms)
            if let code = Self.code(in: rest), code != 0 { isOver = true }
        } else if rest.hasPrefix("decoders made") {
            set(.dec, ms)
        } else if rest == "first picture" {
            set(.pic, ms)
        } else if rest == "playable" {
            set(.play, ms)
        } else if rest.hasPrefix("stops waiting") {
            set(.close, ms)
        } else if rest.hasPrefix("shuts down") {
            isOver = true
        }
        return isOver
    }

    private mutating func set(_ step: Step, _ ms: Int) {
        if steps[step] == nil { steps[step] = ms }
    }

    /// The number in "input opened (-5)" or "stream info (0, state ...)".
    private static func code(in text: String) -> Int? {
        guard let open = text.firstIndex(of: "(") else { return nil }
        let digits = text[text.index(after: open)...].prefix { $0 == "-" || $0.isNumber }
        return Int(digits)
    }

    /// The channel's number: the digits of the stream's last part before its extension ("12345.ts": 12345), none
    /// when it has none ("index.m3u8").
    var channelNumber: String? {
        let name = stream.split(separator: ".").first.map(String.init) ?? stream
        let digits = name.filter(\.isNumber)
        return digits.isEmpty ? nil : String(digits)
    }

    /// The report's query: device, build, channel number, then each step that happened, in order. Nothing else ever:
    /// no address, login or channel name.
    func query(device: String, build: String) -> String {
        var items = ["d=\(device)", "b=\(build.filter { $0.isNumber || $0 == "." })"]
        if let channelNumber { items.append("ch=\(channelNumber)") }
        if let lowLatency { items.append("ll=\(lowLatency ? 1 : 0)") }
        if let liveBuffer { items.append("lb=\(liveBuffer)") }
        for step in Step.allCases {
            if let ms = steps[step] { items.append("\(step.rawValue)=\(ms)") }
        }
        return items.joined(separator: "&")
    }
}
