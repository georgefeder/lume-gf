import SwiftUI
#if os(iOS)
    import AVFoundation
    import MediaPlayer
    import UIKit
#endif

extension View {
    /// Lume GF: the player's level swipes (Georgs, 3 Nov), iPhone and iPad: up and down on the left half sets the
    /// screen's brightness, on the right half the volume, with a glass pill at the top showing the level. The volume
    /// is the system's, as the side buttons set it (their presses show in the pill too); the brightness goes back to
    /// what it was when the player closes or the app leaves the screen. Off where `enabled` is false (casting).
    @ViewBuilder func gfLevelSwipes(enabled: Bool = true) -> some View {
        #if os(iOS)
            modifier(GFLevelSwipes(enabled: enabled))
        #else
            self
        #endif
    }
}

#if os(iOS)
    /// What the pill shows, and the levels behind it.
    @MainActor
    @Observable
    final class GFLevelModel {
        private(set) var shown: GFPlayerSwipe.Kind?
        private(set) var level = 0.0
        @ObservationIgnored private var hideTask: Task<Void, Never>?
        @ObservationIgnored weak var host: GFLevelHostView?
        /// The brightness before the first swipe here, put back on leaving.
        @ObservationIgnored private var originalBrightness: CGFloat?
        /// A swipe in progress sets the volume: its own changes are not news for the pill.
        @ObservationIgnored var isDraggingVolume = false
        @ObservationIgnored private var volumeObservation: NSKeyValueObservation?
        @ObservationIgnored private let edgeTap = UIImpactFeedbackGenerator(style: .soft)

        func current(_ kind: GFPlayerSwipe.Kind) -> Double {
            switch kind {
            case .brightness: Double(host?.screen?.brightness ?? 0.5)
            case .volume: Double(AVAudioSession.sharedInstance().outputVolume)
            }
        }

        func set(_ kind: GFPlayerSwipe.Kind, to next: Double) {
            // a soft tap on reaching none or all, as a slider's end stop
            if (next == 0 || next == 1), next != level || shown != kind { edgeTap.impactOccurred() }
            switch kind {
            case .brightness:
                guard let screen = host?.screen else { return }
                if originalBrightness == nil { originalBrightness = screen.brightness }
                screen.brightness = CGFloat(next)
            case .volume:
                host?.setVolume(Float(next))
            }
            show(kind, next)
        }

        func show(_ kind: GFPlayerSwipe.Kind, _ next: Double) {
            hideTask?.cancel()
            shown = kind
            level = next
        }

        /// The pill goes a moment after the finger lifts.
        func hideSoon() {
            hideTask?.cancel()
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                self?.shown = nil
            }
        }

        func restoreBrightness() {
            guard let originalBrightness else { return }
            host?.screen?.brightness = originalBrightness
            self.originalBrightness = nil
        }

        /// The side buttons' presses show in the pill: with the hidden volume view on screen iOS shows no volume
        /// indicator of its own.
        func watchVolume() {
            guard volumeObservation == nil else { return }
            // KVO can call from any thread: the change goes over to the main actor. Weak, or the observation would
            // keep the model alive for ever.
            volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) {
                @Sendable [weak self] _, change in
                guard let value = change.newValue else { return }
                Task { @MainActor [weak self] in self?.volumeChanged(to: Double(value)) }
            }
        }

        private func volumeChanged(to value: Double) {
            guard !isDraggingVolume else { return }
            show(.volume, value)
            hideSoon()
        }
    }

    private struct GFLevelSwipes: ViewModifier {
        let enabled: Bool
        @State private var model = GFLevelModel()
        @State private var size = CGSize.zero
        /// The drag's level, once it is known to be a level swipe; a drag that went sideways first stays sideways.
        @State private var active: GFPlayerSwipe.Kind?
        @State private var decided = false
        @State private var startLevel = 0.0
        @Environment(\.scenePhase) private var scenePhase
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func body(content: Content) -> some View {
            content
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                .background {
                    GFLevelHost(model: model)
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .overlay(alignment: .top) {
                    // the pill comes and goes softly; the bar inside it follows the finger with no animation
                    pill.animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.25),
                                   value: model.shown)
                }
                .simultaneousGesture(drag, including: enabled ? .all : .subviews)
                .onAppear {
                    model.watchVolume()
                    #if GF_DEMO
                        if GFDemo.moves.contains("level") { model.show(.volume, 0.62) }
                    #endif
                }
                .onDisappear { model.restoreBrightness() }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { model.restoreBrightness() }
                }
        }

        private var drag: some Gesture {
            DragGesture(minimumDistance: GFPlayerSwipe.threshold, coordinateSpace: .local)
                .onChanged { value in
                    if !decided {
                        decided = true
                        guard GFPlayerSwipe.isVertical(value.translation),
                              let kind = GFPlayerSwipe.kind(start: value.startLocation, size: size) else { return }
                        active = kind
                        startLevel = model.current(kind)
                        model.isDraggingVolume = kind == .volume
                    }
                    guard let active else { return }
                    model.set(active, to: GFPlayerSwipe.level(from: startLevel, dy: value.translation.height,
                                                              height: size.height))
                }
                .onEnded { _ in
                    if active != nil { model.hideSoon() }
                    active = nil
                    decided = false
                    model.isDraggingVolume = false
                }
        }

        /// Below the top row of buttons, centred on the screen (the Duo's outer screen: beside its side column).
        @ViewBuilder private var pill: some View {
            if let kind = model.shown {
                GFLevelPill(kind: kind, level: model.level)
                    .padding(.top, 68)
                    .gfControlsBesideSideColumn()
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
                    .allowsHitTesting(false)
            }
        }
    }

    /// The pill: the level's icon, a bar and the percentage, on glass.
    struct GFLevelPill: View {
        let kind: GFPlayerSwipe.Kind
        let level: Double

        private let barWidth: CGFloat = 96

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: GFPlayerSwipe.symbol(kind, level: level))
                    .contentTransition(.symbolEffect(.replace))
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
                Capsule()
                    .fill(.white.opacity(0.25))
                    .frame(width: barWidth, height: 5)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.white)
                            .frame(width: barWidth * min(1, max(0, level)), height: 5)
                    }
                Text(verbatim: "\(GFPlayerSwipe.percent(level))%")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 42, alignment: .trailing)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffectCompat(.regular, in: Capsule())
            // the icon swaps smoothly between brightness and volume; the bar follows the finger with no lag
            .animation(.smooth(duration: 0.25), value: kind)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(kind == .brightness ? "Brightness" : "Volume")
            .accessibilityValue("\(GFPlayerSwipe.percent(level)) percent")
        }
    }

    /// Holds the hidden system volume view (it sets the volume, and keeps iOS's own volume indicator away while the
    /// player is open) and finds the screen the player is on (the Duo has two).
    private struct GFLevelHost: UIViewRepresentable {
        let model: GFLevelModel

        func makeUIView(context _: Context) -> GFLevelHostView {
            let view = GFLevelHostView()
            model.host = view
            return view
        }

        func updateUIView(_ view: GFLevelHostView, context _: Context) {
            model.host = view
        }
    }

    final class GFLevelHostView: UIView {
        private let volumeView = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            // on screen but invisible: a hidden one would let iOS show its own indicator over the pill
            volumeView.alpha = 0.001
            addSubview(volumeView)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("not from a storyboard")
        }

        var screen: UIScreen? {
            window?.windowScene?.screen
        }

        /// The system volume, through the volume view's own slider (apps have no other way to set it).
        func setVolume(_ value: Float) {
            volumeView.subviews.lazy.compactMap { $0 as? UISlider }.first?.value = value
        }
    }
#endif
