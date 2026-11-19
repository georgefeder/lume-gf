import SwiftUI

/// Lume GF: the live channel's line under the title (Georgs, 19 Nov: "when you are delayed from the live ... you have
/// a button to press to go back to the live"). At live, the red dot and LIVE as before. Paused or stalled, the channel
/// plays on from where it stopped: the dot goes grey, the line says how far behind, and a Go Live button opens the
/// channel afresh at live. Its own small view, so the clock's changes redraw only this line.
struct GFLiveBadge: View {
    var clock: PlaybackClock
    let onGoLive: () -> Void

    var body: some View {
        if let pausedAt = clock.gfPausedAt {
            // paused, the player sends no ticks: the line counts on by itself, once a second
            TimelineView(.periodic(from: pausedAt, by: 1)) { context in
                let total = clock.gfBehindLive + context.date.timeIntervalSince(pausedAt)
                line(behind: total < 5 ? 0 : total.rounded(.down))
            }
        } else {
            line(behind: clock.gfBehindLive)
        }
    }

    private func line(behind: TimeInterval) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(behind > 0 ? Color.white.opacity(0.5) : .red)
                .frame(width: 7, height: 7)
            if behind > 0 {
                Text(verbatim: "\(Self.timeString(behind)) behind live")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
                    .contentTransition(.numericText())
            } else {
                Text("LIVE")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 8)
            if behind > 0 {
                Button(action: onGoLive) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 7, height: 7)
                        Text("Go Live")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
                    .glassEffectCompat(.regularInteractive, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Go to live")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(minHeight: 32)
        .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
        .animation(.smooth(duration: 0.25), value: behind > 0)
    }

    /// 0:45, 12:05, 1:02:10.
    static func timeString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}
