import CoreGraphics

/// Lume GF: the picture on screen as a replay jumps, handed from the player that closes to the fresh one that opens
/// the new minute, which shows it under its spinner until its own picture moves (KSPlayerEngineView gfCatchupArrive).
@MainActor
final class GFCatchupHold {
    static let shared = GFCatchupHold()
    private var held: (id: String, frame: CGImage)?

    func keep(_ frame: CGImage?, for id: String) {
        held = frame.map { (id, $0) }
    }

    /// The picture kept for `id`, once: any other is dropped.
    func take(for id: String) -> CGImage? {
        defer { held = nil }
        return held?.id == id ? held?.frame : nil
    }
}
