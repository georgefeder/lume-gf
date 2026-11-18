#if os(iOS)
    import CoreHaptics
    import Foundation

    /// Lume GF: the feel of the level swipes (Georgs, 18 Nov 2026: "a nice blurry haptic feedback ... choose something
    /// nice from the haptics lib, it just generic"). Core Haptics instead of the stock taps: each 5 % notch is a soft,
    /// low-sharpness bump with a short fading tail, so it blurs rather than clicks, and it turns a little crisper as the
    /// level climbs, so the hand feels where it is. The ends are a fuller, longer thud, a slider's end stop. Nothing
    /// on a device without haptics; the engine stops itself when idle.
    @MainActor
    final class GFLevelHaptics {
        private var engine: CHHapticEngine?
        private var running = false

        /// A swipe begins: start the engine now, so the first notch is on time.
        func prepare() {
            guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
            if engine == nil {
                guard let made = try? CHHapticEngine() else { return }
                made.playsHapticsOnly = true
                made.isAutoShutdownEnabled = true
                made.stoppedHandler = { [weak self] _ in Task { @MainActor in self?.running = false } }
                made.resetHandler = { [weak self] in Task { @MainActor in self?.running = false } }
                engine = made
            }
            guard !running, let engine else { return }
            running = (try? engine.start()) != nil
        }

        /// A notch crossed at `level` (0...1).
        func notch(at level: Double) {
            let level = min(1, max(0, level))
            play(intensity: 0.42, sharpness: Float(0.04 + 0.3 * level), tail: 0.07, tailIntensity: 0.22)
        }

        /// None or all reached.
        func end() {
            play(intensity: 0.85, sharpness: 0.22, tail: 0.16, tailIntensity: 0.4)
        }

        /// A transient bump and, under it, a short continuous rumble that fades out: the blur.
        private func play(intensity: Float, sharpness: Float, tail: TimeInterval, tailIntensity: Float) {
            prepare()
            guard running, let engine else { return }
            let bump = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: 0)
            let blur = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: tailIntensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: max(0, sharpness - 0.1)),
            ], relativeTime: 0, duration: tail)
            let fade = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                .init(relativeTime: 0, value: 1),
                .init(relativeTime: tail, value: 0),
            ], relativeTime: 0)
            guard let pattern = try? CHHapticPattern(events: [bump, blur], parameterCurves: [fade]),
                  let player = try? engine.makePlayer(with: pattern)
            else { return }
            try? player.start(atTime: CHHapticTimeImmediate)
        }
    }
#endif
