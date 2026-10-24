import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import KSPlayer
import Metal
import OSLog
import QuartzCore
import SwiftUI
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

    func hingeMoved(degrees: Double?) {
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

    /// The reflection: the panel and the fold above it, so it meets the picture with no black band between.
    var reflection: CGRect {
        CGRect(x: panel.minX, y: video.maxY, width: panel.width, height: panel.maxY - video.maxY)
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

    /// Pins a layer of the player to one part of the split screen: `rect` (whole-screen coordinates), with
    /// `bottomInset` kept clear for the home indicator. Unchanged when the player is not split.
    func gfTabletopArea(_ rect: CGRect?, bottomInset: CGFloat = 0) -> some View {
        // placed by padding: placed by offset, the controls came out shifted left with the close button off screen
        // (CI run 40080430709)
        padding(.bottom, rect == nil ? 0 : bottomInset)
            .frame(width: rect?.width, height: rect?.height)
            #if GF_DEMO
                .background { GFDemoLanding(rect: rect) }
            #endif
            .padding(.leading, rect?.minX ?? 0)
            .padding(.top, rect?.minY ?? 0)
            .frame(maxWidth: rect == nil ? nil : .infinity, maxHeight: rect == nil ? nil : .infinity,
                   alignment: .topLeading)
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
                    GFTabletop.shared.hingeMoved(degrees: new.hinge?.angle.degrees)
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

/// Under the split player's picture: black, with the picture mirrored into it from where the picture stands on the
/// fold, like a screen's reflection on a glossy table (Apple has no such material; Netflix draws its own). It meets the
/// picture bright and nearly sharp, then blurs and fades into black over a length that follows the hinge (Georgs,
/// 24 Oct: "fades, morphs at the middle", "stretches depending on the hinge").
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
        /// How the reflection is drawn. Brightness: `contact` where it meets the picture, falling to `body` within the
        /// first `contactShare` of its length, then to black at its end. Blur: from `sharpness` of `blurShare` of the
        /// picture's width where it meets the picture to all of it `blurReach` of the way down.
        private static let contact: CGFloat = 0.7, body: CGFloat = 0.45, contactShare: CGFloat = 0.15
        private static let blurShare: CGFloat = 1.0 / 28, sharpness: CGFloat = 0.1, blurReach: CGFloat = 0.6
        /// How quickly the length follows the hinge (seconds to get about two thirds of the way).
        private static let follow: Double = 0.15
        private static let pixelsPerPoint: CGFloat = 1

        private var metalLayer: CAMetalLayer {
            // swiftlint:disable:next force_cast
            layer as! CAMetalLayer
        }

        private var link: CADisplayLink?
        private var lastBuffer: CVPixelBuffer?
        private var still: (number: Int, image: CIImage)?
        private var fading: (from: CIImage, start: CFTimeInterval)?
        /// The still as last drawn (part way through a dissolve, perhaps): the next one dissolves from it.
        private var shownStill: CIImage?
        private var stretch: CGFloat?
        private var lastTick: CFTimeInterval?
        /// Something changed that the next tick must draw.
        private var stale = true
        private var drewPicture = false
        private var inFlight = 0
        #if GF_DEMO
            /// What the screenshots' log last heard from this mirror, so each state is told once.
            private var told = ""

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
                still = nil
                fading = nil
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
            let target = GFTabletopLayout.reflectionStretch(hingeDegrees: GFTabletop.shared.hingeDegrees)
            let elapsed = lastTick.map { now - $0 } ?? 0
            lastTick = now
            var length = stretch.map { $0 + (target - $0) * CGFloat(1 - exp(-elapsed / Self.follow)) } ?? target
            if abs(length - target) < 0.002 { length = target }
            if length != stretch {
                stretch = length
                stale = true
            }
            #if GF_DEMO
                if Self.gpu == nil { tell("no Metal device") }
            #endif
            guard stale, inFlight < 2, let gpu = Self.gpu else { return }
            if source.image == nil, !drewPicture { // black already
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
            let drawn = source.image.map { reflected($0, in: area, stretch: length).composited(over: black) } ?? black
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
            drewPicture = source.image != nil
        }

        /// What to mirror now: the player's frame, or its still (dissolving from the last one), and whether it is new.
        private func nextSource(at now: CFTimeInterval) -> (image: CIImage?, changed: Bool) {
            if reflection.isLive {
                still = nil
                fading = nil
                shownStill = nil
                let buffer = reflection.currentFrame()?.cvPixelBuffer
                let changed = buffer !== lastBuffer
                lastBuffer = buffer
                // HDR channels toned down to the drawable's range rather than clipped
                return (buffer.map { CIImage(cvPixelBuffer: $0, options: [.toneMapHDRtoSDR: true]) }, changed)
            }
            lastBuffer = nil
            guard let image = reflection.image else {
                let changed = still != nil
                still = nil
                fading = nil
                shownStill = nil
                return (nil, changed)
            }
            var changed = false
            if still?.number != reflection.number {
                fading = shownStill.map { (from: $0, start: now) }
                still = (number: reflection.number, image: CIImage(cgImage: image))
                changed = true
            }
            guard let still else { return (nil, changed) }
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
            return (shown, changed)
        }

        /// `frame` upside down from the top of `area` (the fold) across the picture's width, `stretch` times the
        /// picture's height long, blurred more and dimmed further down, in pixels (Core Image's y runs upwards).
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
            // the brightness from the fold down, stretched over the reflection's length
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

        /// The reflection's brightness as it looks, from where it meets the picture (the top row) to its end, `steps`
        /// rows of grey a pixel wide, endless sideways and beyond its ends.
        private static let steps: CGFloat = 256
        private static let brightness: CIImage = {
            let ease = { (t: CGFloat) in 1 - min(1, t) * min(1, t) * (3 - 2 * min(1, t)) }
            let view = GFMirrorView.self
            let rows = (0 ..< Int(view.steps)).map { row -> UInt8 in
                let t = CGFloat(row) / (view.steps - 1)
                let level = view.body * ease(t) + (view.contact - view.body) * ease(t / view.contactShare)
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
