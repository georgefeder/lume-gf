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
        /// The brightness before the first swipe here, put back on leaving, and the screen it is on (kept from the
        /// swipe: when the player closes, its view may already be out of the window).
        @ObservationIgnored private var originalBrightness: CGFloat?
        @ObservationIgnored private weak var brightnessScreen: UIScreen?
        /// Over Control Centre or the app switcher: the player's brightness, put back on return unless the brightness
        /// was changed meanwhile.
        @ObservationIgnored private var away: (player: CGFloat, original: CGFloat)?
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
                // a swipe after the first stays on the first one's screen, whose brightness goes back on leaving
                guard let screen = originalBrightness == nil ? host?.screen : brightnessScreen else { return }
                if originalBrightness == nil {
                    originalBrightness = screen.brightness
                    brightnessScreen = screen
                }
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

        /// The player closes: the brightness it was before the first swipe.
        func restoreBrightness() {
            away = nil
            guard let originalBrightness, let screen = brightnessScreen else { return }
            screen.brightness = originalBrightness
            self.originalBrightness = nil
        }

        /// The app leaves the screen, or something covers it: the old brightness while away.
        func leave() {
            guard let originalBrightness, let screen = brightnessScreen else { return }
            away = (screen.brightness, originalBrightness)
            screen.brightness = originalBrightness
            self.originalBrightness = nil
        }

        /// Back: the player's brightness again, unless it was changed meanwhile (Control Centre's slider).
        func comeBack() {
            guard let away, let screen = brightnessScreen else { return }
            self.away = nil
            guard abs(screen.brightness - away.original) < 0.02 else { return }
            originalBrightness = away.original
            screen.brightness = away.player
        }

        /// The finger lifted, or the swipe was cut short (a call, Control Centre).
        func dragEnded() {
            isDraggingVolume = false
            hideSoon()
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
        /// The drag so far: nil until its first move, then the level it sets (none for one that went sideways first:
        /// it stays sideways) and that level when it began. Gesture state, so a swipe cut short starts afresh.
        @GestureState private var track: Track?
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
                    if phase == .active { model.comeBack() } else { model.leave() }
                }
                // the end of a level swipe, lifted or cut short (gesture state goes back to nil either way)
                .onChange(of: track) { old, new in
                    if new == nil, old?.kind != nil { model.dragEnded() }
                }
        }

        private struct Track: Equatable {
            var kind: GFPlayerSwipe.Kind?
            var start: Double
        }

        private var drag: some Gesture {
            DragGesture(minimumDistance: GFPlayerSwipe.threshold, coordinateSpace: .local)
                .updating($track) { value, track, _ in
                    if track == nil {
                        let kind = GFPlayerSwipe.isVertical(value.translation)
                            ? GFPlayerSwipe.kind(start: value.startLocation, size: size) : nil
                        track = Track(kind: kind, start: kind.map { model.current($0) } ?? 0)
                        model.isDraggingVolume = kind == .volume
                    }
                    guard let kind = track?.kind, let start = track?.start else { return }
                    model.set(kind, to: GFPlayerSwipe.level(from: start, dy: value.translation.height,
                                                            height: size.height))
                }
        }

        /// Below the top row of buttons, centred on the whole screen, as the play button is. The Duo's outer screen
        /// keeps a column down its side for the clock and the camera, and the player stops short of it: the pill is
        /// moved by the gap between the player's middle and the screen's, measured from the window as it is drawn. It
        /// once followed the shared side-column reading instead, and jumped as that changed: left as it came, centred
        /// while adjusting, left again as it faded (Georgs, 4 Nov). The pill is narrower than the screen left of the
        /// column, so it never reaches the camera at the column's top.
        @ViewBuilder private var pill: some View {
            if let kind = model.shown {
                GFLevelPill(kind: kind, level: model.level)
                    .padding(.top, 68)
                    .offset(x: model.host?.screenCentreShift() ?? 0)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
                    .allowsHitTesting(false)
            }
        }
    }

    /// The pill: the level's icon, a bar and the percentage, on glass.
    struct GFLevelPill: View {
        let kind: GFPlayerSwipe.Kind
        let level: Double
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: kind)
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

        /// How far the window's middle is to the right of the player's (this view sits in the player's middle): 0 on
        /// an iPhone, whose sides are kept clear alike; on the Duo's outer screen half its side column.
        func screenCentreShift() -> CGFloat {
            guard let window else { return 0 }
            let middle = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window).x
            return window.bounds.midX - middle
        }

        /// The system volume, through the volume view's own slider (apps have no other way to set it).
        func setVolume(_ value: Float) {
            volumeView.subviews.lazy.compactMap { $0 as? UISlider }.first?.value = value
        }
    }
#endif
