import Foundation

/// A guide refresh waits while video plays instead of stopping (Georgs, 18 Nov 2026: the iPhone's guide still 12 hours
/// old). Stopped, a whole import started over each time and never finished on a phone that is often playing; paused,
/// it goes on from the same batch once the video ends. Its saves still never run while video plays: they hitch the
/// player (the indexer pauses for the same reason). Asked between batches, from the refresh's own thread.
nonisolated final class GFGuidePause: @unchecked Sendable {
    static let shared = GFGuidePause()

    private let lock = NSLock()
    private var held = false

    init() {}

    var isHeld: Bool {
        lock.withLock { held }
    }

    /// Video started (true) or nothing plays any more (false).
    func hold(_ holds: Bool) {
        lock.withLock { held = holds }
    }

    /// Returns once nothing plays or `shouldStop` says stop (Apple's background time ran out): true when it waited.
    @discardableResult
    func waitWhileHeld(shouldStop: () -> Bool = { Task.isCancelled },
                       nap: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) -> Bool {
        var waited = false
        while isHeld, !shouldStop() {
            waited = true
            nap(0.5)
        }
        return waited
    }

    /// For the import loops: waits while video plays, then whether to stop.
    static func stopOrWait() -> Bool {
        shared.waitWhileHeld()
        return Task.isCancelled
    }
}
