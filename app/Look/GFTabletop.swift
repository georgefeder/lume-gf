import CoreGraphics
import CoreVideo
import Foundation
import KSPlayer
import OSLog
import SwiftUI
import VideoToolbox
#if canImport(UIKit)
    import UIKit
#endif

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
    /// A pending "no fold any more", confirmed after `settle` (a turn can hide the fold for a moment).
    @ObservationIgnored private var closing: Task<Void, Never>?
    private static let settle: Duration = .milliseconds(600)
    /// How far the phone is open, in degrees (assumed 0 closed, 180 flat; Apple does not say), nil until iOS tells:
    /// the reflection's length follows it (`GFTabletopLayout.reflectionStretch`). Read by the glow each frame.
    @ObservationIgnored private(set) var hingeDegrees: Double?
    /// The last ten degrees logged, so the report shows the angles the phone stood at without a line per degree.
    @ObservationIgnored private var loggedTens: Int?

    private init() {
        #if GF_DEMO
            hingeDegrees = GFDemo.hinge
        #endif
    }

    /// The hinge moved: its angle counts while the phone is partly open (closed, the simulator says 0°). Test builds
    /// keep their `-GFDemoHinge`.
    private func forgetHinge() {
        #if GF_DEMO
            if GFDemo.hinge != nil { return }
        #endif
        hingeDegrees = nil
        loggedTens = nil
    }

    func hingeMoved(degrees: Double?, partlyOpen: Bool) {
        #if GF_DEMO
            if GFDemo.hinge != nil { return }
        #endif
        guard partlyOpen else { return }
        hingeDegrees = degrees
        let tens = degrees.map { Int(($0 / 10).rounded()) }
        guard tens != loggedTens else { return }
        loggedTens = tens
        Self.log("hinge at " + (degrees.map { "\(Int($0.rounded()))°" } ?? "no angle"))
    }

    /// What the player's fold reader sees now. A fold counts at once; its end only once it has stayed gone, so a
    /// moment without one while the phone turns cannot lock landscape again and turn it back.
    func foldChanged(partlyOpen: Bool) {
        closing?.cancel()
        closing = nil
        if partlyOpen {
            set(true)
        } else if isPartlyOpen {
            closing = Task { [weak self] in
                try? await Task.sleep(for: Self.settle)
                guard !Task.isCancelled else { return }
                self?.forgetHinge() // opened flat or closed: the angle it stood at is gone
                self?.set(false)
            }
        }
    }

    /// The player that read the fold is gone: nothing is split any more (another engine may open next).
    func readerGone() {
        closing?.cancel()
        closing = nil
        set(false)
    }

    private func set(_ open: Bool) {
        guard open != isPartlyOpen else { return }
        isPartlyOpen = open
        Self.log(open ? "partly open" : "open flat, closed or player gone")
        #if os(iOS)
            PlayerOrientationLock.gfFoldChanged()
        #endif
    }

    /// A line in Lume's diagnostic report ("Duo fold: ..."): what iOS reported and what the player did with it.
    static func log(_ text: String) {
        Logger.player.info("\("Duo fold: " + text, privacy: .public)")
        #if GF_DEMO
            GFDemo.logTabletop(text)
        #endif
    }

    static func text(_ rect: CGRect) -> String {
        "\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height))"
    }

    /// What the reader saw, for the diagnostic report.
    static func describe(folds: [CGRect], size: CGSize, split: GFTabletopFrames?) -> String {
        let regions = folds.map { "\(Int($0.width))x\(Int($0.height)) at \(Int($0.minX)),\(Int($0.minY))" }
        let shape = split.map { "split \(Int($0.video.height)) above, \(Int($0.panel.height)) below" } ?? "whole"
        let screen = "\(Int(size.width))x\(Int(size.height))"
        return "\(folds.count) fold region(s) [\(regions.joined(separator: "; "))] on \(screen): \(shape)"
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
nonisolated struct GFTabletopFrames: Equatable {
    var video: CGRect
    var panel: CGRect
    /// The home indicator's room at the bottom of the panel.
    var bottomInset: CGFloat

    /// The reflection: the panel, below the crease, which stays black (Georgs, 24 Oct, on build 74 drawn across the
    /// crease: on Netflix it "faintly starts only at the top of the bottom screen, already kind of after the crease").
    var reflection: CGRect {
        panel
    }
}

/// What the reflection shows, kept out of the player's own state (a change redraws only the reflection, not the
/// player, whose open menus would flicker and drop taps): the player's frames live when they are pixel buffers, as from
/// hardware decoding and 8-bit software decoding (Georgs, 24 Oct: once a second "is like 2 fps", Netflix's moves with
/// the picture); otherwise (10-bit software decoding) a picture about once a second, each dissolving into the next.
/// The glow (`GFGlow`) reads what it shows 30 times a second; only the picture's shape redraws the player.
@MainActor
@Observable
final class GFReflection {
    @ObservationIgnored private(set) var image: CGImage?
    /// Changes with every picture, for the dissolve.
    @ObservationIgnored private(set) var number = 0
    /// The player's frames are pixel buffers: the mirror shows them.
    @ObservationIgnored private(set) var isLive = false
    /// The frame the player shows now, for the glow.
    @ObservationIgnored var currentFrame: () -> PixelBufferProtocol? = { nil }
    /// The picture's shape (width over height as shown), nil until a frame tells: the picture stands on the fold with
    /// its reflection under it (`GFTabletopLayout.picture`).
    private(set) var videoAspect: CGFloat?

    func setLive(_ live: Bool) {
        guard live != isLive else { return }
        isLive = live
        if live { image = nil } // no stale picture shows when the live mirror ends
    }

    func show(_ next: CGImage?) {
        image = next
        number &+= 1
    }

    func setAspect(_ aspect: CGFloat?) {
        guard let aspect, aspect.isFinite, aspect > 0, abs(aspect - (videoAspect ?? 0)) > 0.005 else { return }
        videoAspect = aspect
    }

    /// The shape a frame shows at: its size with the stream's pixel shape (non-square pixels, as some SD channels).
    nonisolated static func aspect(of frame: PixelBufferProtocol) -> CGFloat? {
        let pixel = frame.aspectRatio
        guard frame.width > 0, frame.height > 0, pixel.width > 0, pixel.height > 0 else { return nil }
        return CGFloat(frame.width) * pixel.width / (CGFloat(frame.height) * pixel.height)
    }

    /// The width a picture is shrunk to for the glow: it is blurred into one anyway (Video.js: "Same shape as the
    /// video, just tiny. The blur hides the low resolution.").
    nonisolated static let width = 48

    nonisolated static func shrunk(_ image: CGImage) -> CGImage? {
        guard image.width > width else { return image }
        let height = max(1, image.height * width / image.width)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

extension View {
    /// Reads the fold across the player into `frames` (nil when there is none) and tells `GFTabletop` whether the
    /// phone is partly open.
    func gfReadsFold(into frames: Binding<GFTabletopFrames?>) -> some View {
        modifier(GFFoldReader(frames: frames))
    }

    /// Pins a layer of the player to one band of the split screen, across its whole width: the rows of `rect`
    /// (whole-screen coordinates), in the half by the screen's `edge`, with `bottomInset` kept clear for the home
    /// indicator. Unchanged when the player is not split.
    /// Nothing here may be as wide or as tall as the screen: the layers then grew the player, the fold was read on the
    /// bigger player, and round it went until the controls hung 84 points off the left (CI runs 40080430709 to
    /// 40085607543). So a band above the fold hangs from the top by its bottom row, one below stands on the bottom.
    func gfTabletopArea(_ rect: CGRect?, from edge: VerticalEdge, bottomInset: CGFloat = 0) -> some View {
        padding(.bottom, rect == nil ? 0 : bottomInset)
            .frame(height: rect?.height)
            #if GF_DEMO
                .background { GFDemoLanding(rect: rect) }
            #endif
            .frame(height: edge == .top ? rect?.maxY : nil, alignment: .bottom)
            .frame(maxWidth: rect == nil ? nil : .infinity, maxHeight: rect == nil ? nil : .infinity,
                   alignment: edge == .top ? .top : .bottom)
            .ignoresSafeArea(edges: rect == nil ? [] : .all)
    }
}

#if GF_DEMO
    /// Screenshot builds: where a layer meant for `rect` really landed on screen.
    private struct GFDemoLanding: View {
        let rect: CGRect?

        var body: some View {
            GeometryReader { proxy in
                let landed = proxy.frame(in: .global)
                Color.clear.onChange(of: landed, initial: true) { _, landed in
                    guard let rect else { return }
                    GFTabletop.log("layer for \(GFTabletop.text(rect)) landed at \(GFTabletop.text(landed))")
                }
            }
        }
    }
#endif

private struct GFFoldReader: ViewModifier {
    @Binding var frames: GFTabletopFrames?
    /// Bumped by every hinge change, so the fold is read again even when the screen's size stays the same.
    @State private var hingeMoves = 0

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    let _ = hingeMoves
                    let folds = GFTabletop.folds(proxy)
                    let split = GFTabletopLayout.split(size: proxy.size, folds: folds).map {
                        GFTabletopFrames(video: $0.video, panel: $0.panel, bottomInset: proxy.safeAreaInsets.bottom)
                    }
                    Color.clear
                        .onChange(of: split, initial: true) { _, value in
                            frames = value
                            GFTabletop.log(GFTabletop.describe(folds: folds, size: proxy.size, split: value))
                        }
                        .onChange(of: !folds.isEmpty, initial: true) { _, open in
                            GFTabletop.shared.foldChanged(partlyOpen: open)
                        }
                        .onDisappear { GFTabletop.shared.readerGone() }
                }
                .ignoresSafeArea()
            }
            .modifier(GFHingeMoves(count: $hingeMoves))
            #if os(iOS)
                // which way up the phone is held only reaches UIDevice while someone asks for it; the lock asks it
                // whether the phone stands upright (PlayerOrientationLock.gfHeld)
                .onAppear { UIDevice.current.beginGeneratingDeviceOrientationNotifications() }
                .onDisappear { UIDevice.current.endGeneratingDeviceOrientationNotifications() }
            #endif
    }
}

/// Counts the hinge's changes and passes on its angle (iOS 27.1, builds with Xcode 27.1).
private struct GFHingeMoves: ViewModifier {
    @Binding var count: Int

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS) && GF_FOLD_API
            if #available(iOS 27.1, *) {
                content.onHingeChange { old, new in
                    count &+= 1
                    GFTabletop.shared.hingeMoved(degrees: new.hinge?.angle.degrees,
                                                 partlyOpen: new.hinge?.status == .partiallyOpen)
                    if old.hinge?.status != new.hinge?.status {
                        let status = new.hinge.map { hinge -> String in
                            let state = hinge.status == .partiallyOpen ? "partly open"
                                : hinge.status == .fullyOpen ? "fully open"
                                : hinge.status == .closed ? "closed" : "other"
                            return "\(state), \(Int(hinge.angle.degrees))°"
                        } ?? "none"
                        GFTabletop.log("hinge \(status)")
                    }
                }
            } else {
                content
            }
        #else
            content
        #endif
    }
}

/// Under the split player's crease: a glow of the picture's colours, the way Netflix draws one under its controls. No
/// Apple API draws it (Apple's iPhone Duo documentation, sessions and frameworks have nothing for it), so this is
/// Video.js's recreation of Netflix's, one for one with SwiftUI's own modifiers
/// (videojs.org/blog/iphone-duo-web-development: a tiny copy of each frame, `scale: 1 -1`, `filter: blur(24px)`,
/// `opacity: 0.35`, a mask fading to transparent 80% of the way from the fold). The crease above stays black, and the
/// glow's length follows the hinge by SwiftUI's spring (Georgs, 28 Oct, after builds 74 and 75's hand-made mirror:
/// "build it with documentation that has already proven to work ... something a bit more robust").
struct GFVideoReflection: View {
    let reflection: GFReflection
    /// The picture above and this view, in the whole screen's coordinates.
    let picture: CGRect
    let area: CGRect

    var body: some View {
        Color.black
            .overlay(alignment: .topLeading) {
                GFGlow(reflection: reflection, size: picture.size)
                    .offset(x: picture.minX - area.minX)
                    .environment(\.layoutDirection, .leftToRight) // under the picture in every language
            }
            .clipped()
            .contentShape(Rectangle()) // a tap here reaches the player: it brings the controls back
    }
}

/// The glow, redrawn 30 times a second from the player's newest frame (or its still, dissolving into the next).
private struct GFGlow: View {
    let reflection: GFReflection
    /// The picture's size: the glow is as wide, and as long as the hinge makes it.
    let size: CGSize
    @State private var shrinker = GFFrameShrinker()

    /// Video.js's numbers for Netflix's glow: its blur, its strength, and where its fade from the fold ends.
    private static let blur: CGFloat = 24, strength: Double = 0.35, fadeEnd: CGFloat = 0.8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
            let live = reflection.isLive
            let image = live ? shrinker.image(for: reflection.currentFrame()?.cvPixelBuffer) : reflection.image
            let stretch = GFTabletopLayout.reflectionStretch(hingeDegrees: GFTabletop.shared.hingeDegrees)
            let still = live ? -1 : reflection.number
            ZStack {
                if let image {
                    // a still fades in over the last one, which stays whole until it is covered (both fading
                    // at once would dim the glow halfway through)
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .id(still)
                        .zIndex(Double(still))
                        .transition(AnyTransition.asymmetric(
                            insertion: .opacity,
                            removal: AnyTransition.opacity.animation(.linear(duration: 0.01).delay(0.8))
                        ))
                }
            }
            .animation(.easeInOut(duration: 0.8), value: still)
            .frame(width: size.width, height: size.height * stretch)
            .scaleEffect(x: 1, y: -1) // the mirror
            .blur(radius: Self.blur) // the glow
            .mask {
                LinearGradient(stops: [Gradient.Stop(color: .black, location: 0),
                                       Gradient.Stop(color: .clear, location: Self.fadeEnd)],
                               startPoint: .top, endPoint: .bottom) // fading away from the fold
            }
            .opacity(Self.strength)
            .animation(.spring(duration: 0.15, bounce: 0), value: stretch) // following the hinge
        }
        .allowsHitTesting(false)
    }
}

/// The player's frames shrunk to `GFReflection.width` pixels across for the glow (it is blurred anyway) by
/// VideoToolbox, which reads every format KSPlayer decodes into (three-plane 4:2:0 and 10-bit among them) and gives HDR
/// the usual colours, on a queue of its own: the main thread shows the picture and runs the controls, and never waits
/// for it.
/// The glow shows the newest image made, a tick behind the picture at most.
nonisolated final class GFFrameShrinker: @unchecked Sendable {
    /// A frame handed to the queue.
    private struct Frame: @unchecked Sendable {
        let buffer: CVPixelBuffer
    }

    private let queue = DispatchQueue(label: "lv.georgefeder.lume.glow", qos: .userInitiated)
    /// Guards `latest`, `busy` and `generation`.
    private let lock = NSLock()
    private var latest: CGImage?
    /// A frame is being shrunk: the next waits for a later tick (one at a time).
    private var busy = false
    /// Bumped when the frames stop, so an image still being made then is not shown after.
    private var generation = 0
    /// The main thread's: the frame last handed over.
    private var handedOver: CVPixelBuffer?
    /// The queue's own.
    private var transfer: VTPixelTransferSession?
    private var pool: (buffers: CVPixelBufferPool, width: Int, height: Int)?
    private var told = (made: false, failed: false)

    deinit {
        if let transfer { VTPixelTransferSessionInvalidate(transfer) }
    }

    /// The glow's image for the player's frame now: the newest one made, with `frame` handed over to be made next when
    /// it is new. Nil without a frame.
    func image(for frame: CVPixelBuffer?) -> CGImage? {
        guard let frame else {
            handedOver = nil
            lock.withLock {
                latest = nil
                generation &+= 1
            }
            return nil
        }
        if frame !== handedOver, let ticket = claim() {
            handedOver = frame
            let handed = Frame(buffer: frame)
            queue.async { [self] in
                let image = makeImage(from: handed.buffer)
                lock.withLock {
                    if let image, ticket == generation { latest = image }
                    busy = false
                }
            }
        }
        return lock.withLock { latest }
    }

    /// The queue for the next frame, with the generation it belongs to, unless it is busy.
    private func claim() -> Int? {
        lock.withLock {
            guard !busy else { return nil }
            busy = true
            return generation
        }
    }

    /// On `queue`.
    private func makeImage(from frame: CVPixelBuffer) -> CGImage? {
        let sourceWidth = CVPixelBufferGetWidth(frame), sourceHeight = CVPixelBufferGetHeight(frame)
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }
        let width = GFReflection.width, height = max(2, sourceHeight * width / sourceWidth & ~1)
        if pool?.width != width || pool?.height != height {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any]()
            ]
            var made: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &made)
            pool = made.map { (buffers: $0, width: width, height: height) }
        }
        if transfer == nil {
            VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &transfer)
            if let transfer {
                // keep up with the picture rather than do it best, in the usual colours (an HDR channel's too)
                VTSessionSetProperty(transfer, key: kVTPixelTransferPropertyKey_RealTime, value: kCFBooleanTrue)
                VTSessionSetProperty(transfer, key: kVTPixelTransferPropertyKey_DestinationColorPrimaries,
                                     value: kCVImageBufferColorPrimaries_ITU_R_709_2)
                VTSessionSetProperty(transfer, key: kVTPixelTransferPropertyKey_DestinationTransferFunction,
                                     value: kCVImageBufferTransferFunction_ITU_R_709_2)
            }
        }
        var small: CVPixelBuffer?
        var status: OSStatus = kCVReturnError
        if let pool, let transfer,
           CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool.buffers, &small) == kCVReturnSuccess,
           let small {
            status = VTPixelTransferSessionTransferImage(transfer, from: frame, to: small)
        }
        var image: CGImage?
        if status == noErr, let small {
            VTCreateCGImageFromCVPixelBuffer(small, options: nil, imageOut: &image)
        }
        tell(image != nil, frame: frame, status: status)
        return image
    }

    /// The diagnostic report hears once that the glow works, and once if a frame could not be shrunk (the first sign
    /// of a broken one on the phone was a silently black reflection).
    private func tell(_ made: Bool, frame: CVPixelBuffer, status: OSStatus) {
        guard made ? !told.made : !told.failed else { return }
        if made { told.made = true } else { told.failed = true }
        let format = GFEnhancePlan.name(of: CVPixelBufferGetPixelFormatType(frame))
        let size = "\(CVPixelBufferGetWidth(frame))x\(CVPixelBufferGetHeight(frame))"
        let text = made ? "glow from \(format) frames, \(size)"
            : "glow could not shrink a \(format) frame, \(size) (\(status))"
        Task { @MainActor in GFTabletop.log(text) }
    }
}

extension KSPlayerEngineView {
    /// Where the picture goes while the player is split: standing on the fold (`GFTabletopLayout.picture`).
    var gfPicture: CGRect? {
        gfTabletop.map { GFTabletopLayout.picture(in: $0.video, aspect: gfReflection.videoAspect) }
    }

    /// Keeps the reflection going while the player is split (only KSMEPlayer): its frames live when they are on the
    /// GPU; otherwise the frame on screen about once a second, shrunk off the main thread, only while the stream plays
    /// in the foreground. Also the picture's shape, four times a second, so the picture stands on the fold from its
    /// first frame and takes a new channel's shape as it starts. Nothing once the player is whole again.
    func gfFollowReflection() async {
        guard gfTabletop != nil else {
            gfReflection.currentFrame = { nil }
            gfReflection.setLive(false)
            gfReflection.show(nil)
            return
        }
        let coordinator = coordinator
        gfReflection.currentFrame = { (coordinator.playerLayer?.player as? KSMEPlayer)?.videoOutput?.pixelBuffer }
        var quarters = 0
        while !Task.isCancelled {
            let player = coordinator.playerLayer?.player as? KSMEPlayer
            let frame = player?.videoOutput?.pixelBuffer
            gfReflection.setAspect(frame.flatMap(GFReflection.aspect(of:))) // known before the black cover lifts
            quarters &+= 1
            if gfDrawn, let player {
                if frame?.cvPixelBuffer != nil {
                    // the mirror follows every frame by itself, and keeps a paused one
                    gfReflection.setLive(true)
                } else if quarters % 4 == 1, isPlaying, Self.gfInForeground,
                          let frame = await player.thumbnailImageAtCurrentTime() {
                    let small = await Task.detached(priority: .utility) { GFReflection.shrunk(frame) }.value
                    guard !Task.isCancelled else { return }
                    gfReflection.show(small) // the new picture first, then off the live mirror: no stale one between
                    gfReflection.setLive(false)
                }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private static var gfInForeground: Bool {
        #if canImport(UIKit)
            UIApplication.shared.applicationState == .active
        #else
            true
        #endif
    }
}
