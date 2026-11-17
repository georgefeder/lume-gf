import Foundation

/// The live log's lines (GFLiveLog; Georgs, 17 Nov 2026: "why can't there be a probe in the app so u can debug live
/// here", always on, light on the battery): kept short and plain, and never anything that could carry an address or a
/// login, so a line that looks like one is dropped whole rather than cleaned.
nonisolated enum GFLiveLogLines {
    static let maxLength = 160
    /// Lines kept while nothing can be sent (no guide host yet, no network): the oldest go first.
    static let maxKept = 300
    /// Characters of lines per request, so a request stays far below any URL length limit.
    static let maxBatchCharacters = 1500

    /// The line as sent, or nil when it must not leave the device.
    static func clean(_ text: String) -> String? {
        let lowered = text.lowercased()
        for risky in ["://", "username", "password", "token", "@", "/live/", "/movie/", "/series/", "xmltv.php"]
            where lowered.contains(risky) { return nil }
        let printable = text.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }
        let line = String(String.UnicodeScalarView(printable)).trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        return String(line.prefix(maxLength))
    }

    /// The lines in requests of at most `maxBatchCharacters`, in order.
    static func batches(_ lines: [String]) -> [[String]] {
        var out: [[String]] = []
        var current: [String] = []
        var size = 0
        for line in lines {
            if size + line.count + 1 > maxBatchCharacters, !current.isEmpty {
                out.append(current)
                current = []
                size = 0
            }
            current.append(line)
            size += line.count + 1
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Whether to send now: the app on screen and a minute gone, or many lines waiting.
    static func shouldSend(waiting: Int, sinceLast: TimeInterval, appActive: Bool) -> Bool {
        guard waiting > 0, appActive else { return false }
        return sinceLast >= 60 || waiting >= 40
    }
}
