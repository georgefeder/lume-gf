import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import KSPlayer
import Metal
import OSLog
import QuartzCore
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
    /// the reflection's length follows it (`GFTabletopLayout.reflectionStretch`). Read by the mirror each frame.
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
/// The mirror (`GFMirrorView`) reads what it shows every frame; only the picture's shape redraws the player.
@MainActor
@Observable
final class GFReflection {
    @ObservationIgnored private(set) var image: CGImage?
    /// Changes with every picture, for the dissolve.
    @ObservationIgnored private(set) var number = 0
    /// The player's frames are pixel buffers: the mirror shows them.
    @ObservationIgnored private(set) var isLive = false
    /// The frame the player shows now, for the mirror.
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

    /// The width a picture is shrunk to before it is kept: it is blurred into a glow anyway.
    nonisolated static let width = 320

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

/// Under the split player's crease: black, with the picture mirrored faintly into it, like a screen's reflection on a
/// glossy table (Apple has no such material; Netflix draws its own). It starts faint at the top of the bottom screen,
/// rises a little, then blurs and fades into black over a length that follows the hinge (Georgs, 24 Oct: "fades,
/// morphs at the middle", "stretches depending on the hinge", "faintly starts only at the top of the bottom screen").
struct GFVideoReflection: View {
    let reflection: GFReflection
    /// The picture above and this view, in the whole screen's coordinates.
    let picture: CGRect
    let area: CGRect

    var body: some View {
        Color.black
            .overlay {
                #if canImport(UIKit)
                    // the picture's place across this view, and its height
                    GFLiveMirror(reflection: reflection, picture: picture.offsetBy(dx: -area.minX, dy: -picture.minY))
                #endif
            }
            .clipped()
            .contentShape(Rectangle()) // a tap here reaches the player: it brings the controls back
    }
}

#if canImport(UIKit)
    struct GFLiveMirror: UIViewRepresentable {
        let reflection: GFReflection
        let picture: CGRect

        func makeUIView(context _: Context) -> GFMirrorView {
            GFMirrorView(reflection: reflection)
        }

        func updateUIView(_ view: GFMirrorView, context _: Context) {
            view.reflection = reflection
            view.picture = picture
        }
    }

    /// Draws the reflection with Core Image on the GPU at every new frame of the player's (the same pixel buffer;
    /// nothing is copied) and while the hinge moves, one pixel a point (a third of the screen's; it is blurred anyway).
    final class GFMirrorView: UIView {
        override class var layerClass: AnyClass {
            CAMetalLayer.self
        }

        var reflection: GFReflection {
            didSet { if reflection !== oldValue { stale = true } }
        }

        var picture: CGRect = .zero {
            didSet { if picture != oldValue { stale = true } }
        }

        /// One GPU queue and Core Image context for every player (making them takes a while).
        private static let gpu: (queue: any MTLCommandQueue, context: CIContext)? = {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
            return (queue, CIContext(mtlCommandQueue: queue, options: [.cacheIntermediates: false,
                                                                        .name: "GF reflection"]))
        }()

        private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        private static let linear = CGColorSpace(name: CGColorSpace.linearSRGB)
        /// How the reflection is drawn. Brightness, as it looks: `faint` at the top of the panel, rising to `peak`
        /// `crest` of the way down, then easing to black at its end (build 74 started at 0.7 and was "bonded" to the
        /// picture). Blur: from `sharpness` of `blurShare` of the picture's width at the top to all of it `blurReach`
        /// of the way down.
        private static let faint: CGFloat = 0.06, peak: CGFloat = 0.3, crest: CGFloat = 0.25
        private static let blurShare: CGFloat = 1.0 / 28, sharpness: CGFloat = 0.3, blurReach: CGFloat = 0.6
        /// How quickly the length follows the hinge: a critically damped spring this stiff trails a moving hinge by
        /// about 2 / `springRate` seconds (0.05 s; build 74 eased over 0.15 s and was "delayed" moving fast).
        private static let springRate: Double = 40
        private static let pixelsPerPoint: CGFloat = 1

        private var metalLayer: CAMetalLayer {
            // swiftlint:disable:next force_cast
            layer as! CAMetalLayer
        }

        private var link: CADisplayLink?
        private var lastBuffer: CVPixelBuffer?
        /// The last frame as Core Image reads it, made when first drawn (`image()`) and kept for redraws while the
        /// hinge moves, and the buffer it was made from.
        private var lastImage: CIImage?
        private var madeFrom: CVPixelBuffer?
        /// A frame could not be made readable: told once (the first on-device sign was a silently black reflection).
        private var toldUnreadable = false
        private var transfer: VTPixelTransferSession?
        private var pool: (buffers: CVPixelBufferPool, width: Int, height: Int)?
        private var still: (number: Int, image: CIImage)?
        private var fading: (from: CIImage, start: CFTimeInterval)?
        /// The still as last drawn (part way through a dissolve, perhaps): the next one dissolves from it.
        private var shownStill: CIImage?
        private var stretch: CGFloat?
        /// How fast `stretch` is moving, per second (the spring's).
        private var stretchSpeed: Double = 0
        private var lastTick: CFTimeInterval?
        /// Something changed that the next tick must draw.
        private var stale = true
        private var drewPicture = false
        private var inFlight = 0
        #if GF_DEMO
            /// What the screenshots' log last heard from this mirror, so each state is told once.
            private var told = ""
            private var ticks = 0

            private func tell(_ state: String) {
                guard state != told else { return }
                told = state
                GFTabletop.log("mirror: " + state)
            }
        #endif

        init(reflection: GFReflection) {
            self.reflection = reflection
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .black
            contentScaleFactor = Self.pixelsPerPoint
            metalLayer.device = Self.gpu?.queue.device
            metalLayer.pixelFormat = .bgra8Unorm
            metalLayer.colorspace = Self.sRGB
            metalLayer.framebufferOnly = false // Core Image may write the drawable from a compute pass
            metalLayer.isOpaque = true
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let size = CGSize(width: (bounds.width * Self.pixelsPerPoint).rounded(),
                              height: (bounds.height * Self.pixelsPerPoint).rounded())
            if metalLayer.drawableSize != size {
                metalLayer.drawableSize = size
                stale = true
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            link?.invalidate()
            link = nil
            lastTick = nil
            guard window != nil else {
                lastBuffer = nil
                lastImage = nil
                madeFrom = nil
                if let transfer { VTPixelTransferSessionInvalidate(transfer) }
                transfer = nil
                pool = nil
                still = nil
                fading = nil
                stretch = nil // back on screen, it takes the hinge's length at once
                stretchSpeed = 0
                return
            }
            contentScaleFactor = Self.pixelsPerPoint // a window sets its screen's
            stale = true
            let link = CADisplayLink(target: GFMirrorTick(self), selector: #selector(GFMirrorTick.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 60, preferred: nil)
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        /// Each screen refresh: draws when the picture, its still, the hinge or the size changed.
        fileprivate func tick(at now: CFTimeInterval) {
            let source = nextSource(at: now)
            if source.changed { stale = true }
            #if GF_DEMO
                ticks += 1
                if ticks % 120 == 1, ticks < 1500 { // every two seconds or so, for the first twenty
                    let frame = reflection.currentFrame()
                    let kind = frame == nil ? "none" : frame?.cvPixelBuffer == nil ? "no pixel buffer" : "pixel buffer"
                    let size = metalLayer.drawableSize
                    GFTabletop.log("mirror tick \(ticks): live \(reflection.isLive), frame \(kind), "
                        + "image \(lastImage != nil), stale \(stale), in flight \(inFlight), "
                        + "drawable \(Int(size.width))x\(Int(size.height)), window \(window != nil)")
                }
            #endif
            let target = GFTabletopLayout.reflectionStretch(hingeDegrees: GFTabletop.shared.hingeDegrees)
            let elapsed = lastTick.map { now - $0 } ?? 0
            lastTick = now
            var length = stretch.map { followed(from: $0, to: target, over: elapsed) } ?? target
            if abs(length - target) < 0.002, abs(stretchSpeed) < 0.02 {
                length = target
                stretchSpeed = 0
            }
            if length != stretch {
                stretch = length
                stale = true
            }
            #if GF_DEMO
                if Self.gpu == nil { tell("no Metal device") }
            #endif
            guard stale, inFlight < 2, let gpu = Self.gpu else { return }
            if !source.present, !drewPicture { // black already
                #if GF_DEMO
                    tell("nothing to show (live \(reflection.isLive), still \(reflection.image != nil))")
                #endif
                stale = false
                return
            }
            let size = metalLayer.drawableSize
            guard size.width >= 1, size.height >= 1, let drawable = metalLayer.nextDrawable(),
                  let commands = gpu.queue.makeCommandBuffer()
            else {
                #if GF_DEMO
                    tell("no drawable at \(Int(size.width))x\(Int(size.height))")
                #endif
                return
            }
            let area = CGRect(origin: .zero, size: size)
            let black = CIImage(color: .black).cropped(to: area)
            let shown = source.present ? image() : nil
            let drawn = shown.map { reflected($0, in: area, stretch: length).composited(over: black) } ?? black
            let destination = CIRenderDestination(mtlTexture: drawable.texture, commandBuffer: commands)
            destination.colorSpace = Self.sRGB
            destination.isDithered = true // the long fade to black would band in 8 bits
            do {
                _ = try gpu.context.startTask(toRender: drawn, to: destination)
                #if GF_DEMO
                    let place = GFTabletop.text(convert(bounds, to: nil))
                    let kind = reflection.isLive ? "live" : "still"
                    tell("drawing \(kind) frames, \(Int(size.width))x\(Int(size.height)) at \(place), "
                        + "picture \(GFTabletop.text(picture)), stretch \(String(format: "%.2f", length))")
                #endif
            } catch {
                #if GF_DEMO
                    tell("Core Image failed: \(error.localizedDescription)")
                #endif
            }
            commands.present(drawable)
            inFlight += 1
            commands.addCompletedHandler { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in self?.inFlight -= 1 }
            }
            commands.commit()
            stale = false
            drewPicture = shown != nil
        }

        /// `current` moved toward `target` for `elapsed` seconds by a critically damped spring (exact for any step, so a
        /// late frame neither overshoots nor jumps), its speed kept in `stretchSpeed`: hinge angles come at whatever
        /// rate the system allows (UIHinge.angle: "system policy"), and the spring carries the reflection between them.
        private func followed(from current: CGFloat, to target: CGFloat, over elapsed: Double) -> CGFloat {
            let rate = Self.springRate, t = min(elapsed, 0.25)
            let offset = Double(current - target), drift = stretchSpeed + rate * offset
            let decay = exp(-rate * t)
            stretchSpeed = (drift - rate * (offset + drift * t)) * decay
            return target + CGFloat((offset + drift * t) * decay)
        }

        /// Whether there is anything to mirror now (the player's frame, or its still dissolving from the last one) and
        /// whether it is new. Its picture is made only when drawn (`image()`).
        private func nextSource(at now: CFTimeInterval) -> (present: Bool, changed: Bool) {
            if reflection.isLive {
                still = nil
                fading = nil
                shownStill = nil
                let buffer = reflection.currentFrame()?.cvPixelBuffer
                guard buffer !== lastBuffer else { return (buffer != nil, false) }
                lastBuffer = buffer
                if buffer == nil {
                    lastImage = nil
                    madeFrom = nil
                }
                return (buffer != nil, true)
            }
            lastBuffer = nil
            lastImage = nil
            madeFrom = nil
            guard let image = reflection.image else {
                let changed = still != nil
                still = nil
                fading = nil
                shownStill = nil
                return (false, changed)
            }
            var changed = false
            if still?.number != reflection.number {
                fading = shownStill.map { (from: $0, start: now) }
                still = (number: reflection.number, image: CIImage(cgImage: image))
                changed = true
            }
            guard let still else { return (false, changed) }
            var shown = still.image
            if let fading {
                let progress = (now - fading.start) / 0.8
                if progress >= 1 {
                    self.fading = nil
                } else {
                    let dissolve = CIFilter.dissolveTransition()
                    dissolve.inputImage = fading.from
                    dissolve.targetImage = still.image
                    dissolve.time = Float(progress * progress * (3 - 2 * progress)) // eased in and out
                    shown = dissolve.outputImage ?? still.image
                }
                changed = true
            }
            shownStill = shown
            return (true, changed)
        }

        /// The picture to mirror: the still, or the player's newest frame as Core Image reads it (the last one that
        /// could be read, if this one cannot).
        private func image() -> CIImage? {
            guard reflection.isLive else { return shownStill }
            guard let buffer = lastBuffer else { return nil }
            if madeFrom !== buffer {
                madeFrom = buffer
                if let readable = readable(buffer) {
                    // HDR channels toned down to the drawable's range rather than clipped
                    lastImage = CIImage(cvPixelBuffer: readable, options: [.toneMapHDRtoSDR: true])
                } else if !toldUnreadable {
                    toldUnreadable = true
                    let format = Self.fourCC(CVPixelBufferGetPixelFormatType(buffer))
                    GFTabletop.log("mirror: could not read a \(format) frame")
                }
            }
            return lastImage
        }

        private static func fourCC(_ code: OSType) -> String {
            String((0 ..< 4).map { Character(UnicodeScalar(UInt8(truncatingIfNeeded: code >> (24 - 8 * $0)))) })
        }

        /// The formats Core Image reads as they are: KSPlayer's two-plane 4:2:0 (full-range and 10-bit channels, HDR
        /// among them, which keep their depth for the tone mapping) and BGRA.
        private static let readableFormats: Set<OSType> = [
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
            kCVPixelFormatType_32BGRA
        ]

        /// The player's frame in a form Core Image reads: as it is when it can, otherwise made small (it is blurred
        /// anyway) by VideoToolbox. KSPlayer has most channels (8-bit 4:2:0 at video range) decoded into three-plane
        /// buffers, which Core Image cannot read at all (CI run 40085607543: a pixel buffer every frame, never an
        /// image). A new buffer from a pool each time, so one the GPU is still reading is never written over.
        private func readable(_ buffer: CVPixelBuffer) -> CVPixelBuffer? {
            if Self.readableFormats.contains(CVPixelBufferGetPixelFormatType(buffer)) { return buffer }
            let sourceWidth = CVPixelBufferGetWidth(buffer), sourceHeight = CVPixelBufferGetHeight(buffer)
            guard sourceWidth > 0, sourceHeight > 0 else { return nil }
            let width = max(2, min(sourceWidth, 640) & ~1), height = max(2, sourceHeight * width / sourceWidth & ~1)
            if pool?.width != width || pool?.height != height {
                let attributes: [CFString: Any] = [
                    kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey: width,
                    kCVPixelBufferHeightKey: height,
                    kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
                    kCVPixelBufferMetalCompatibilityKey: true
                ]
                var made: CVPixelBufferPool?
                CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &made)
                pool = made.map { (buffers: $0, width: width, height: height) }
            }
            if transfer == nil {
                VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &transfer)
                if let transfer { // keep up with the picture rather than do it best
                    VTSessionSetProperty(transfer, key: kVTPixelTransferPropertyKey_RealTime, value: kCFBooleanTrue)
                }
            }
            var small: CVPixelBuffer?
            guard let pool, let transfer,
                  CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool.buffers, &small) == kCVReturnSuccess,
                  let small, VTPixelTransferSessionTransferImage(transfer, from: buffer, to: small) == noErr
            else { return nil }
            return small
        }

        /// `frame` upside down from the top of `area` (the top of the panel, below the crease) across the picture's
        /// width, `stretch` times the picture's height long, blurred more and dimmed further down, in pixels (Core
        /// Image's y runs upwards).
        private func reflected(_ frame: CIImage, in area: CGRect, stretch: CGFloat) -> CIImage {
            let scale = Self.pixelsPerPoint
            let across = CGRect(x: picture.minX * scale, y: 0, width: max(1, picture.width * scale), height: area.height)
            let length = max(1, picture.height * scale * stretch)
            let fold = area.maxY
            let extent = frame.extent
            let mirror = CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
                .concatenating(CGAffineTransform(scaleX: across.width / extent.width, y: -length / extent.height))
                .concatenating(CGAffineTransform(translationX: across.minX, y: fold))
            let blurMask = CIFilter.smoothLinearGradient()
            blurMask.point0 = CGPoint(x: 0, y: fold)
            blurMask.color0 = Self.grey(Self.sharpness)
            blurMask.point1 = CGPoint(x: 0, y: fold - length * Self.blurReach)
            blurMask.color1 = Self.grey(1)
            let mirrored = frame.transformed(by: mirror).clampedToExtent() // no dark rim from the blur
            let blur = CIFilter.maskedVariableBlur()
            blur.inputImage = mirrored
            blur.mask = blurMask.outputImage
            blur.radius = Float(across.width * Self.blurShare)
            // the brightness from the top of the panel down, stretched over the reflection's length
            let light = Self.brightness.transformed(by: CGAffineTransform(scaleX: 1, y: length / Self.steps)
                .concatenating(CGAffineTransform(translationX: 0, y: fold - length)))
            return (blur.outputImage ?? mirrored)
                .applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: light])
                .cropped(to: across)
        }

        /// A grey as Core Image works with it (it reads masks in linear light).
        private static func grey(_ level: CGFloat) -> CIColor {
            linear.flatMap { CIColor(red: level, green: level, blue: level, alpha: 1, colorSpace: $0) }
                ?? CIColor(red: level, green: level, blue: level)
        }

        /// The reflection's brightness as it looks, from the top of the panel (the top row) to its end, `steps` rows of
        /// grey a pixel wide, endless sideways and beyond its ends.
        private static let steps: CGFloat = 256
        private static let brightness: CIImage = {
            let smooth = { (t: CGFloat) in t * t * (3 - 2 * t) }
            let view = GFMirrorView.self
            let rows = (0 ..< Int(view.steps)).map { row -> UInt8 in
                let t = CGFloat(row) / (view.steps - 1)
                let level = t < view.crest
                    ? view.faint + (view.peak - view.faint) * smooth(t / view.crest)
                    : view.peak * (1 - smooth((t - view.crest) / (1 - view.crest)))
                return UInt8((level * 255).rounded())
            }
            guard let grey = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
                  let data = CGDataProvider(data: Data(rows) as CFData),
                  let image = CGImage(width: 1, height: rows.count, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 1,
                                      space: grey, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                      provider: data, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
            else { return CIImage(color: .black) }
            return CIImage(cgImage: image).clampedToExtent()
        }()
    }

    /// The display link's target, holding the mirror weakly (a display link keeps its target).
    private final class GFMirrorTick: NSObject {
        weak var view: GFMirrorView?

        init(_ view: GFMirrorView) {
            self.view = view
        }

        @objc func tick(_ link: CADisplayLink) {
            guard let view else { return link.invalidate() }
            view.tick(at: link.timestamp)
        }
    }
#endif

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
