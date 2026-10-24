import AVFoundation
import CoreMedia
import CoreVideo
import KSPlayer
import OSLog
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

    private init() {}

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
}

/// What the reflection shows, kept out of the player's own state (a change redraws only the reflection, not the
/// player, whose open menus would flicker and drop taps): the player's frames live (`GFLiveMirror`) when they are
/// pixel buffers, as from hardware decoding and 8-bit software decoding (Georgs, 24 Oct: once a second "is like 2 fps",
/// Netflix's moves with the picture); otherwise (10-bit software decoding) a picture about once a second, cross-faded.
@MainActor
@Observable
final class GFReflection {
    private(set) var image: CGImage?
    /// Changes with every picture, for the cross-fade.
    private(set) var number = 0
    /// The player's frames are pixel buffers: the live mirror shows them.
    private(set) var isLive = false
    /// The frame the player shows now, for the live mirror.
    @ObservationIgnored var currentFrame: () -> PixelBufferProtocol? = { nil }

    func setLive(_ live: Bool) {
        guard live != isLive else { return }
        isLive = live
        if live { image = nil } // no stale picture shows when the live mirror ends
    }

    func show(_ next: CGImage?) {
        withAnimation(.easeInOut(duration: 0.8)) {
            image = next
            number += 1
        }
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

/// Counts the hinge's changes (iOS 27.1, builds with Xcode 27.1).
private struct GFHingeMoves: ViewModifier {
    @Binding var count: Int

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS) && GF_FOLD_API
            if #available(iOS 27.1, *) {
                content.onHingeChange { old, new in
                    count &+= 1
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

/// The panel under the split player's picture: black, with the picture mirrored and blurred into it from the fold and
/// fading out downwards, like a screen's reflection on a glossy table. Apple has no such material (Netflix draws its
/// own); this one follows the stream about once a second, each picture dissolving into the next.
struct GFVideoReflection: View {
    let reflection: GFReflection

    var body: some View {
        Color.black
            .overlay {
                if reflection.isLive {
                    #if canImport(UIKit)
                        // the live mirror under Apple's dark frosted material (a blur that also works on video), dimmed
                        // by a layer of black rather than a group opacity, which would render the video offscreen
                        ZStack {
                            GFLiveMirror(frame: reflection.currentFrame)
                            Rectangle().fill(.ultraThinMaterial)
                            Color.black.opacity(0.4)
                        }
                    #endif
                } else if let image = reflection.image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(x: 1, y: -1)
                        .blur(radius: 24, opaque: true)
                        .opacity(0.45)
                        .id(reflection.number)
                        .transition(.opacity)
                }
            }
            .overlay {
                LinearGradient(colors: [.black.opacity(0.1), .black], startPoint: .top, endPoint: .bottom)
            }
            .clipped()
            .contentShape(Rectangle()) // a tap here reaches the player: it brings the controls back
    }
}

#if canImport(UIKit)
    /// The player's frames, live and upside down: a display layer that gets each new frame as the player shows it (the
    /// same pixel buffer; nothing is copied or converted).
    struct GFLiveMirror: UIViewRepresentable {
        let frame: () -> PixelBufferProtocol?

        func makeUIView(context _: Context) -> GFMirrorView {
            GFMirrorView()
        }

        func updateUIView(_ view: GFMirrorView, context _: Context) {
            view.source = frame
        }
    }

    final class GFMirrorView: UIView {
        var source: () -> PixelBufferProtocol? = { nil }
        private let video = AVSampleBufferDisplayLayer()
        private var link: CADisplayLink?
        private var last: CVPixelBuffer?
        private var format: CMVideoFormatDescription?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            clipsToBounds = true
            video.videoGravity = .resizeAspectFill
            video.setAffineTransform(CGAffineTransform(scaleX: 1, y: -1))
            layer.addSublayer(video)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // at once: an implicit animation would trail the panel as the hinge moves
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            video.bounds = bounds
            video.position = CGPoint(x: bounds.midX, y: bounds.midY)
            CATransaction.commit()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            link?.invalidate()
            link = nil
            guard window != nil else {
                video.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
                last = nil
                return
            }
            let link = CADisplayLink(target: GFMirrorTick(self), selector: #selector(GFMirrorTick.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 60, preferred: nil)
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        /// A new frame on the player's screen goes on the mirror at once.
        fileprivate func showLatest() {
            let renderer = video.sampleBufferRenderer
            if renderer.status == .failed { // after a trip to the background: start again, the frame on screen too
                renderer.flush()
                last = nil
            }
            guard let buffer = source()?.cvPixelBuffer, buffer !== last else { return }
            last = buffer
            if format.map({ !CMVideoFormatDescriptionMatchesImageBuffer($0, imageBuffer: buffer) }) ?? true {
                format = nil
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                             formatDescriptionOut: &format)
            }
            guard let format else { return }
            var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
            var sample: CMSampleBuffer?
            guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                           formatDescription: format, sampleTiming: &timing,
                                                           sampleBufferOut: &sample) == noErr,
                let sample
            else { return }
            if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
               CFArrayGetCount(attachments) > 0 {
                let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
                let key = Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque()
                CFDictionarySetValue(first, key, Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
            }
            renderer.enqueue(sample)
        }
    }

    /// The display link's target, holding the mirror weakly (a display link keeps its target).
    private final class GFMirrorTick: NSObject {
        weak var view: GFMirrorView?

        init(_ view: GFMirrorView) {
            self.view = view
        }

        @objc func tick(_ link: CADisplayLink) {
            guard let view else { return link.invalidate() }
            view.showLatest()
        }
    }
#endif

extension KSPlayerEngineView {
    /// Keeps the reflection going while the player is split (only KSMEPlayer): its frames live when they are on the
    /// GPU; otherwise the frame on screen about once a second, shrunk off the main thread, only while the stream plays
    /// in the foreground. Nothing once the player is whole again.
    func gfFollowReflection() async {
        guard gfTabletop != nil else {
            gfReflection.currentFrame = { nil }
            gfReflection.setLive(false)
            gfReflection.show(nil)
            return
        }
        let coordinator = coordinator
        gfReflection.currentFrame = { (coordinator.playerLayer?.player as? KSMEPlayer)?.videoOutput?.pixelBuffer }
        while !Task.isCancelled {
            if gfDrawn, let player = coordinator.playerLayer?.player as? KSMEPlayer {
                if player.videoOutput?.pixelBuffer?.cvPixelBuffer != nil {
                    // the mirror follows every frame by itself, and keeps a paused one
                    gfReflection.setLive(true)
                } else if isPlaying, Self.gfInForeground, let frame = await player.thumbnailImageAtCurrentTime() {
                    let small = await Task.detached(priority: .utility) { GFReflection.shrunk(frame) }.value
                    guard !Task.isCancelled else { return }
                    gfReflection.show(small) // the new picture first, then off the live mirror: no stale one between
                    gfReflection.setLive(false)
                }
            }
            try? await Task.sleep(for: .seconds(1))
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
