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

    /// The picture kept for `id`. Kept on after: a refused replay's retry opens the same item in a fresh player again.
    func take(for id: String) -> CGImage? {
        held?.id == id ? held?.frame : nil
    }
}
