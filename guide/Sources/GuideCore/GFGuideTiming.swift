import Foundation

/// One guide refresh's timings, for the server (Georgs, 16 Nov 2026: the iPhone's whole guide import kept starting
/// over and nobody could see where its time went). Sent like the channel-change report: one GET of `/gf-guide` on the
/// guide's own Dispatcharr host, read from the access log (selfhost-aio host-scripts/lume-guide-report.py). Numbers and
/// short words only: never an address, login or channel.
nonisolated struct GFGuideTiming: Equatable {
    /// "wake" (a push or background refresh, ~25 s) or "app" (open, or the overnight import).
    var kind: String
    /// What came back and what was done: "unchanged", "delta", "whole", "patch" (a
    /// whole guide taken in as changes in a short wake), "same", "later", "failed".
    var path = "failed"
    /// Milliseconds: the download, reading the stored guide, writing the changes.
    var download: Int?
    var readStored: Int?
    var apply: Int?
    /// Programmes read from the store; inserted, updated, deleted.
    var storedRows: Int?
    var inserted: Int?
    var updated: Int?
    var deleted: Int?
    /// Whether it finished; else why not: "stopped" (iOS, playback, a playlist sync), "incomplete", "error".
    var finished = false
    var why: String?

    static func ms(since start: Date, now: Date = Date()) -> Int {
        max(0, Int((now.timeIntervalSince(start) * 1000).rounded()))
    }

    func query(device: String, build: String) -> String {
        var items: [(String, String)] = [("d", device), ("b", build), ("k", kind), ("p", path),
                                         ("ok", finished ? "1" : "0")]
        let numbers: [(String, Int?)] = [("dl", download), ("rd", readStored), ("ap", apply), ("n", storedRows),
                                         ("i", inserted), ("u", updated), ("x", deleted)]
        for (key, value) in numbers {
            if let value { items.append((key, String(value))) }
        }
        if let why { items.append(("why", why)) }
        return items.map { "\($0.0)=\(Self.plain($0.1))" }.joined(separator: "&")
    }

    /// Letters, digits, dot and dash only (the values are ours, this only keeps them so).
    private static func plain(_ text: String) -> String {
        String(text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-" }
            .prefix(24).map(Character.init))
    }
}
