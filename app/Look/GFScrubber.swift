import SwiftUI

#if !os(tvOS) // Apple TV has no slider: its bar is TVPlayerControlsOverlay's
/// Lume GF: the player's position bar, in place of the system slider (iPhone and iPad). The system slider's drag is
/// UIKit's, and the level swipes' drag over the whole player cancelled it a moment into a scrub, or, once they were
/// told to stand aside, as soon as the finger touched it: a seek landed at once and a replay opened one minute on, a
/// try (Georgs, 19 Nov: "as soon as I touch the scrubber and drag it, it just starts buffering"). This one is a
/// SwiftUI drag of its own, which runs beside the level swipes' instead of being cut off by them; the level swipes
/// see GFPlayerSliding and keep still. Same shape as Slider(value:in:onEditingChanged:); VoiceOver gets a slider.
struct GFScrubber: View {
    @Binding var value: TimeInterval
    let bounds: ClosedRange<TimeInterval>
    var onEditingChanged: (Bool) -> Void = { _ in }

    init(value: Binding<TimeInterval>, in bounds: ClosedRange<TimeInterval>,
         onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        _value = value
        self.bounds = bounds
        self.onEditingChanged = onEditingChanged
    }

    #if os(iOS)
        @State private var dragging = false
        /// The finger is down: back to false when it lifts or the touch is taken away (a call, Control Centre), as
        /// gesture state always is, so a scrub cut short still ends.
        @GestureState private var held = false

        var body: some View {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                // the knob's middle runs from end to end of the track, so it stays under the finger right to the ends
                let inset = Self.knob.width / 2
                let track = max(width - inset * 2, 1)
                let x = inset + track * fraction
                let knob = dragging ? Self.heldKnob : Self.knob
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.3))
                        .frame(height: dragging ? 6 : 4)
                    Capsule()
                        .fill(.white)
                        .frame(width: x, height: dragging ? 6 : 4)
                    // the system slider's knob: a white pill, and a clear glass lens, bigger, while held
                    Capsule()
                        .fill(.white.opacity(dragging ? 0.08 : 1))
                        .frame(width: knob.width, height: knob.height)
                        .glassEffectCompat(dragging ? .clear : .regular, in: Capsule())
                        .shadow(color: .black.opacity(dragging ? 0.15 : 0.25), radius: 4, y: 1)
                        .offset(x: x - knob.width / 2)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .updating($held) { _, held, _ in held = true }
                        .onChanged { drag in
                            if !dragging {
                                dragging = true
                                GFPlayerSliding.shared.active = true
                                onEditingChanged(true)
                            }
                            let share = min(max((drag.location.x - inset) / track, 0), 1)
                            value = bounds.lowerBound + share * (bounds.upperBound - bounds.lowerBound)
                        }
                        .onEnded { _ in finish() } // a tap too quick for the held state to be seen changing
                )
            }
            .frame(height: 30)
            .animation(.smooth(duration: 0.2), value: dragging)
            .onChange(of: held) { _, isHeld in
                if !isHeld { finish() }
            }
            .onDisappear {
                // gone mid-drag (a replay jump, the player closing): nothing more to report
                dragging = false
                GFPlayerSliding.shared.active = false
            }
            .accessibilityRepresentation {
                Slider(value: $value, in: bounds, onEditingChanged: onEditingChanged)
            }
        }

        private static let knob = CGSize(width: 38, height: 24)
        private static let heldKnob = CGSize(width: 58, height: 36)

        private var fraction: CGFloat {
            let span = bounds.upperBound - bounds.lowerBound
            guard span > 0, value.isFinite else { return 0 }
            return CGFloat(min(max((value - bounds.lowerBound) / span, 0), 1))
        }

        private func finish() {
            guard dragging else { return }
            dragging = false
            GFPlayerSliding.shared.active = false
            onEditingChanged(false)
        }
    #else
        var body: some View {
            Slider(value: $value, in: bounds, onEditingChanged: onEditingChanged)
        }
    #endif
}
#endif
