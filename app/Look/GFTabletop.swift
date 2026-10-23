import KSPlayer
import SwiftUI

/// Lume GF: the iPhone Duo stood up half folded like a small laptop (`GFTabletopLayout`; Georgs, 23 Oct 2026: "like
/// Netflix"): the player's picture above the fold, its controls below over a dim reflection of the picture. iOS 27.1
/// reports the fold as a reserved region of kind `.division`, active only while the phone is partly open; the player's
/// landscape lock lets go meanwhile (`PlayerOrientationLock`), so the phone can stand in portrait with the fold across.
@MainActor
@Observable
final class GFTabletop {
    static let shared = GFTabletop()
    /// iOS reports an active fold: the phone is partly open (or the demo pretends it is).
    private(set) var isPartlyOpen = false

    private init() {}

    func foldChanged(partlyOpen: Bool) {
        guard partlyOpen != isPartlyOpen else { return }
        isPartlyOpen = partlyOpen
        #if os(iOS)
            PlayerOrientationLock.gfFoldChanged()
        #endif
    }

    /// Test builds' `-GFDemoFold 1`: a pretend fold across the middle (no simulator command folds an iPhone Duo).
    static var demoFold: Bool {
        #if GF_DEMO
            GFDemo.fold
        #else
            false
        #endif
    }

    /// The fold areas iOS reports for the view `proxy` measures (iOS 27.1 on), or the demo's pretend one.
    /// `GF_FOLD_API`: set by our builds made with Xcode 27.1 (the TestFlight archive, the screenshots); the simulator
    /// tests' older Xcode has no `reservedRegions`.
    static func folds(_ proxy: GeometryProxy) -> [CGRect] {
        if demoFold { return [GFTabletopLayout.demoFold(size: proxy.size)] }
        #if os(iOS) && GF_FOLD_API
            if #available(iOS 27.1, *) {
                return proxy.reservedRegions(kind: .division).map(\.frame)
            }
        #endif
        return []
    }
}

/// Where the split player's parts go, in the whole screen's coordinates.
struct GFTabletopFrames: Equatable {
    var video: CGRect
    var panel: CGRect
    /// The home indicator's room at the bottom of the panel.
    var bottomInset: CGFloat
}

/// One picture of the stream for the reflection, a new one about every second.
struct GFReflectionFrame: Equatable {
    let id = UUID()
    let image: CGImage

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

extension View {
    /// Reads the fold across the player into `frames` (nil when there is none) and tells `GFTabletop` whether the
    /// phone is partly open.
    func gfReadsFold(into frames: Binding<GFTabletopFrames?>) -> some View {
        background {
            GeometryReader { proxy in
                let folds = GFTabletop.folds(proxy)
                let split = GFTabletopLayout.split(size: proxy.size, folds: folds).map {
                    GFTabletopFrames(video: $0.video, panel: $0.panel, bottomInset: proxy.safeAreaInsets.bottom)
                }
                Color.clear
                    .onChange(of: split, initial: true) { _, value in frames.wrappedValue = value }
                    .onChange(of: !folds.isEmpty, initial: true) { _, open in
                        GFTabletop.shared.foldChanged(partlyOpen: open)
                    }
            }
            .ignoresSafeArea()
        }
    }

    /// Pins a layer of the player to one part of the split screen: `rect` (whole-screen coordinates) held at
    /// `alignment`, with `bottomInset` kept clear for the home indicator. Unchanged when the player is not split.
    func gfTabletopArea(_ rect: CGRect?, alignment: Alignment, bottomInset: CGFloat = 0) -> some View {
        padding(.bottom, rect == nil ? 0 : bottomInset)
            .frame(height: rect?.height)
            .frame(maxWidth: rect == nil ? nil : .infinity, maxHeight: rect == nil ? nil : .infinity,
                   alignment: alignment)
            .ignoresSafeArea(edges: rect == nil ? [] : .all)
    }
}

/// The panel under the split player's picture: black, with the picture mirrored and blurred into it from the fold and
/// fading out downwards, like a screen's reflection on a glossy table. Apple has no such material (Netflix draws its
/// own); this one follows the stream about once a second, each picture dissolving into the next.
struct GFVideoReflection: View {
    let frame: GFReflectionFrame?

    var body: some View {
        Color.black
            .overlay {
                if let frame {
                    Image(decorative: frame.image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(x: 1, y: -1)
                        .blur(radius: 36, opaque: true)
                        .opacity(0.45)
                        .id(frame.id)
                        .transition(.opacity)
                }
            }
            .overlay {
                LinearGradient(colors: [.black.opacity(0.1), .black], startPoint: .top, endPoint: .bottom)
            }
            .clipped()
            .allowsHitTesting(false)
    }
}

extension KSPlayerEngineView {
    /// Keeps the reflection's picture current while the player is split: the stream's current frame about once a
    /// second (only KSMEPlayer: its capture just converts the frame on screen), none once it is whole again.
    func gfFollowReflection() async {
        guard gfTabletop != nil else {
            gfReflection = nil
            return
        }
        while !Task.isCancelled {
            if gfDrawn, let player = coordinator.playerLayer?.player as? KSMEPlayer,
               let image = await player.thumbnailImageAtCurrentTime() {
                withAnimation(.easeInOut(duration: 0.8)) { gfReflection = GFReflectionFrame(image: image) }
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
