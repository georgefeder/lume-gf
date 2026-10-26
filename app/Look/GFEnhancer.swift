import CoreMedia
import CoreVideo
import Foundation
import OSLog
import QuartzCore
import VideoToolbox

/// Lume GF: Apple's low-latency super resolution on SD and 720p pictures, full screen on Apple TV with Settings ▸
/// KSPlayer ▸ "Enhance SD & 720p" on (Georgs, 26 Oct 2026: SD and 720p "definitely whack"). KSPlayer hands it each
/// new frame just before showing it (`KSOptions.gfProcessFrame`, deps/KSPlayer/0002) and shows what it returns: the
/// frame upscaled by the factor `GFEnhancePlan` picks, or nil for a frame left as it is (full HD and up).
///
/// One shared upscaler: its model stays loaded from channel to channel (a load on every zap would slow it), and each
/// stream's hook (`hook()`) starts that stream's counts afresh. The model loads on a queue of its own (Apple: a load can
/// take longer than a frame, and the main thread shows frames too), and meanwhile frames are scaled plainly to the size
/// the upscaler will make. Every frame of a stream comes back at that one size, since a new size rebuilds KSPlayer's
/// display layer: a frame the upscaler is busy, late or failed with is scaled plainly, and a stream it cannot keep up
/// with goes back to its own frames for good (one rebuild; plain scaling all the way would look no better than none).
/// How it went is in the diagnostic report ("Enhance: ...") every 30 seconds.
///
/// Only an Apple TV device build has it: the simulators' SDKs lack the upscaler, so they (and the iPhone, which never
/// switches it on) get a stand-in that leaves every frame as it is. ci/device-typecheck.sh compiles the real one against
/// the Apple TV SDK on every test run, since no other CI build does.
#if os(tvOS) && !targetEnvironment(simulator)
@available(tvOS 26.0, *)
nonisolated final class GFEnhancer: @unchecked Sendable {
    /// One frame size and what is done with it.
    private struct Plan {
        var width: Int, height: Int
        /// The size frames come back at, and where they are made; nil when frames of this size are passed through.
        var output: (width: Int, height: Int, pool: CVPixelBufferPool)?
        /// The format the upscaler reads; frames in another are converted into `sourcePool` first.
        var sourceFormat: OSType = 0
        var sourcePool: CVPixelBufferPool?
        /// The model for this size is loaded; until then frames are scaled plainly.
        var ready = false
        /// The model did not load: frames are passed through, until the next stream tries again.
        var failed = false
    }

    /// The frame size and factor a model is loaded for.
    private struct Model: Equatable {
        let width: Int, height: Int
        let factor: Float
    }

    /// What became of a frame: upscaled, scaled plainly as the upscaler was busy, late or failed (missed), or scaled
    /// plainly while the model loads.
    private enum Frame { case upscaled, missed, loading }

    /// The upscaler's answer for one frame, read once it has signalled.
    private final class Request: @unchecked Sendable {
        let done = DispatchSemaphore(value: 0)
        var error: (any Error)?
    }

    static let shared = GFEnhancer()

    /// KSPlayer's hook for one stream (one options object): its frames are counted as a stream of their own.
    static func hook() -> (CVPixelBuffer) -> CVPixelBuffer? {
        let stream = UUID()
        return { shared.process($0, stream: stream) }
    }

    /// A frame the upscaler may take this long before plain scaling stands in for it (a 50 fps frame lasts 20 ms).
    private static let frameTimeout: DispatchTimeInterval = .milliseconds(40)
    /// The stream gets its own frames back after `streakLimit` frames in a row missed (or made neither way), or two
    /// windows of `windowFrames` in a row slower than `slowAverage` or with `missLimit` missed: the picture would
    /// stutter otherwise. The first `warmUpFrames` after the model loads are not judged.
    private static let streakLimit = 4, windowFrames = 50, missLimit = 5, warmUpFrames = 10
    private static let slowAverage: Double = 0.014
    private static let reportEvery: CFTimeInterval = 30

    /// KSPlayer calls on the main thread, and from its decoding thread for a stream's first frame.
    private let lock = NSLock()
    private let processor = VTFrameProcessor()
    /// Loads and unloads the model, away from the threads showing frames.
    private let loader = DispatchQueue(label: "lv.georgefeder.lume.enhance", qos: .userInitiated)
    /// The model loaded in `processor`; only `loader` touches it.
    private var loaded: Model?
    private var plan: Plan?
    /// Counts frame sizes, so a load another size overtook leaves the newer plan alone.
    private var generation = 0
    private var framesSinceReady = 0
    /// A request the upscaler was late with and may still be working on: it gets one at a time.
    private var pending: Request?
    private var transfer: VTPixelTransferSession?
    private var frameNumber: Int64 = 0

    private var stream: UUID?
    /// The stream it could not keep up with: its frames go through as they are.
    private var gaveUp = false
    /// Shown again when a frame can be made neither way: a frame of another size would rebuild the display layer.
    private var lastShown: CVPixelBuffer?
    private var streak = (missed: 0, lost: 0)
    private var window = (frames: 0, seconds: 0.0, missed: 0, bad: 0)
    private var report = (upscaled: 0, seconds: 0.0, worst: 0.0, plain: 0, since: CACurrentMediaTime())

    private init() {}

    /// The frame to show for `buffer` of `stream`: upscaled, plainly scaled to the same size, or nil to show `buffer`.
    func process(_ buffer: CVPixelBuffer, stream: UUID) -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        if stream != self.stream { begin(stream) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        if plan?.width != width || plan?.height != height {
            configure(width: width, height: height, format: CVPixelBufferGetPixelFormatType(buffer))
        }
        guard !gaveUp, let plan, !plan.failed, let output = plan.output else { return nil }
        let start = CACurrentMediaTime()
        var frame = Frame.loading
        var shown: CVPixelBuffer?
        if plan.ready {
            shown = upscaled(buffer, plan: plan, into: output.pool)
            frame = shown == nil ? .missed : .upscaled
        }
        if shown == nil { shown = plainlyScaled(buffer, into: output.pool) }
        let lost = shown == nil
        if let shown {
            Self.carryAttachments(from: buffer, to: shown)
            lastShown = shown
        } else {
            shown = lastShown
        }
        note(frame, lost: lost, seconds: CACurrentMediaTime() - start)
        return gaveUp ? nil : shown
    }

    // MARK: - Streams, frame sizes and the model

    /// A new stream: its own counts, and another chance if the last one was given back its frames or the model did
    /// not load. The model and the size it was set up for stay.
    private func begin(_ stream: UUID) {
        self.stream = stream
        gaveUp = false
        lastShown = nil
        streak = (missed: 0, lost: 0)
        window = (frames: 0, seconds: 0, missed: 0, bad: 0)
        report = (upscaled: 0, seconds: 0, worst: 0, plain: 0, since: CACurrentMediaTime())
        if plan?.failed == true { plan = nil }
    }

    /// A new frame size: its plan, and its model loaded on `loader` (unless it is loaded already).
    private func configure(width: Int, height: Int, format: OSType) {
        generation += 1
        plan = Plan(width: width, height: height)
        pending = nil
        lastShown = nil
        streak = (missed: 0, lost: 0)
        window = (frames: 0, seconds: 0, missed: 0, bad: 0)
        let size = "\(width)x\(height)"
        guard GFEnhancePlan.isBelowFullHD(width: width, height: height) else { return }
        guard VTLowLatencySuperResolutionScalerConfiguration.isSupported else {
            return Self.log("\(size) left as it is: this device has no low-latency super resolution")
        }
        let factors = VTLowLatencySuperResolutionScalerConfiguration.supportedScaleFactors(frameWidth: width,
                                                                                           frameHeight: height)
        guard let factor = GFEnhancePlan.scale(width: width, height: height, supported: factors) else {
            let listed = factors.map { "\($0)" }.joined(separator: ", ")
            return Self.log("\(size) left as it is: no supported factor fits 4K (\(listed))")
        }
        let target = GFEnhancePlan.scaled(width: width, height: height, by: factor)
        let configuration = VTLowLatencySuperResolutionScalerConfiguration(frameWidth: width, frameHeight: height,
                                                                           scaleFactor: factor)
        let reads = configuration.supportedPixelFormats
        let writes = Self.formats(in: configuration.destinationPixelBufferAttributes) ?? reads
        guard let sourceFormat = GFEnhancePlan.format(for: format, from: reads),
              let outputFormat = GFEnhancePlan.format(for: format, from: writes)
        else {
            return Self.log("\(size) left as it is: no 8-bit format (reads \(Self.names(reads)), "
                + "writes \(Self.names(writes)))")
        }
        let made = "\(target.width)x\(target.height)"
        guard let pool = Self.pool(configuration.destinationPixelBufferAttributes, width: target.width,
                                   height: target.height, format: outputFormat),
              let sourcePool = Self.pool(configuration.sourcePixelBufferAttributes, width: width, height: height,
                                         format: sourceFormat)
        else { return Self.log("\(size) left as it is: no frames for \(made)") }
        plan?.output = (width: target.width, height: target.height, pool: pool)
        plan?.sourceFormat = sourceFormat
        plan?.sourcePool = sourcePool
        let description = "\(size) to \(made) (\(factor)x, \(GFEnhancePlan.name(of: sourceFormat)) to "
            + "\(GFEnhancePlan.name(of: outputFormat)))"
        let model = Model(width: width, height: height, factor: factor), ticket = generation
        loader.async { [self] in load(configuration, model: model, ticket: ticket, description: description) }
    }

    /// On `loader`: loads `model` (unless it is loaded already) and readies the plan of `ticket`, if no other frame
    /// size came meanwhile.
    private func load(_ configuration: VTLowLatencySuperResolutionScalerConfiguration, model: Model, ticket: Int,
                      description: String) {
        guard lock.withLock({ ticket == generation }) else { return }
        let start = CACurrentMediaTime()
        let loads = loaded != model
        if loads {
            if loaded != nil { processor.endSession() }
            loaded = nil
            do {
                try processor.startSession(configuration: configuration)
            } catch {
                lock.withLock {
                    if ticket == generation { plan?.failed = true }
                }
                return Self.log("\(description): the upscaler did not start (\(error))")
            }
            loaded = model
        }
        lock.withLock {
            guard ticket == generation else { return }
            plan?.ready = true
            framesSinceReady = 0
        }
        Self.log(loads ? "\(description), ready in \(Self.milliseconds(CACurrentMediaTime() - start))"
            : "\(description), already loaded")
    }

    // MARK: - Frames

    /// A pool of `width`×`height` frames in `format`, nil when it cannot make one (a pool can be made and still fail
    /// at its first frame: found out here, not on every frame).
    private static func pool(_ attributes: [String: Any], width: Int, height: Int, format: OSType)
        -> CVPixelBufferPool? {
        var settings = attributes
        settings[kCVPixelBufferWidthKey as String] = width
        settings[kCVPixelBufferHeightKey as String] = height
        settings[kCVPixelBufferPixelFormatTypeKey as String] = format
        if settings[kCVPixelBufferIOSurfacePropertiesKey as String] == nil {
            settings[kCVPixelBufferIOSurfacePropertiesKey as String] = [String: Any]()
        }
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, settings as CFDictionary, &pool)
        guard let pool, buffer(from: pool) != nil else { return nil }
        return pool
    }

    private static func buffer(from pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        return buffer
    }

    /// The pixel formats `attributes` ask for, if they name any.
    private static func formats(in attributes: [String: Any]) -> [OSType]? {
        switch attributes[kCVPixelBufferPixelFormatTypeKey as String] {
        case let format as NSNumber: [format.uint32Value]
        case let formats as [NSNumber]: formats.map(\.uint32Value)
        default: nil
        }
    }

    private static func names(_ formats: [OSType]) -> String {
        formats.map { GFEnhancePlan.name(of: $0) }.joined(separator: ", ")
    }

    /// `buffer` upscaled into a frame from `pool`, or nil when the upscaler is busy, late or failed.
    private func upscaled(_ buffer: CVPixelBuffer, plan: Plan, into pool: CVPixelBufferPool) -> CVPixelBuffer? {
        // one request at a time: while the upscaler is still on a frame it was late with, frames are scaled plainly
        if let pending {
            guard pending.done.wait(timeout: .now()) == .success else { return nil }
            self.pending = nil
        }
        let readable = CVPixelBufferGetPixelFormatType(buffer) == plan.sourceFormat
        guard let source = readable ? buffer : converted(buffer, into: plan.sourcePool),
              let destination = Self.buffer(from: pool)
        else { return nil }
        frameNumber += 1
        let time = CMTime(value: frameNumber, timescale: 600)
        guard let sourceFrame = VTFrameProcessorFrame(buffer: source, presentationTimeStamp: time),
              let destinationFrame = VTFrameProcessorFrame(buffer: destination, presentationTimeStamp: time)
        else { return nil }
        let parameters = VTLowLatencySuperResolutionScalerParameters(sourceFrame: sourceFrame,
                                                                    destinationFrame: destinationFrame)
        let request = Request()
        processor.process(parameters: parameters) { _, error in
            request.error = error
            request.done.signal()
        }
        // a late frame is left to the upscaler, which holds on to its buffers (the pool cannot hand them out
        // meanwhile), and nothing new is asked of it until it is done
        guard request.done.wait(timeout: .now() + Self.frameTimeout) == .success else {
            pending = request
            return nil
        }
        return request.error == nil ? destination : nil
    }

    /// `buffer` in the format the upscaler reads, at its own size.
    private func converted(_ buffer: CVPixelBuffer, into pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        guard let target = Self.buffer(from: pool), pixelTransfer(buffer, to: target) else { return nil }
        return target
    }

    private func plainlyScaled(_ buffer: CVPixelBuffer, into pool: CVPixelBufferPool) -> CVPixelBuffer? {
        guard let target = Self.buffer(from: pool), pixelTransfer(buffer, to: target) else { return nil }
        return target
    }

    private func pixelTransfer(_ buffer: CVPixelBuffer, to target: CVPixelBuffer) -> Bool {
        if transfer == nil {
            VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &transfer)
            if let transfer {
                VTSessionSetProperty(transfer, key: kVTPixelTransferPropertyKey_RealTime, value: kCFBooleanTrue)
            }
        }
        guard let transfer else { return false }
        return VTPixelTransferSessionTransferImage(transfer, from: buffer, to: target) == noErr
    }

    /// The same attachments on every frame shown, whichever way it was made (a difference rebuilds KSPlayer's display
    /// layer): the source's colour and pixel shape, not its clean aperture (in source pixels), and for an untagged
    /// source the colour its size implies, which the display layer would otherwise guess from the bigger frame (an SD
    /// picture's BT.601 taken for HD's BT.709).
    private static func carryAttachments(from source: CVPixelBuffer, to shown: CVPixelBuffer) {
        CVBufferRemoveAllAttachments(shown)
        CVBufferPropagateAttachments(source, shown)
        CVBufferRemoveAttachment(shown, kCVImageBufferCleanApertureKey)
        let height = CVPixelBufferGetHeight(source)
        if CVBufferCopyAttachment(source, kCVImageBufferYCbCrMatrixKey, nil) == nil {
            let matrix = height <= 576 ? kCVImageBufferYCbCrMatrix_ITU_R_601_4 : kCVImageBufferYCbCrMatrix_ITU_R_709_2
            CVBufferSetAttachment(shown, kCVImageBufferYCbCrMatrixKey, matrix, .shouldPropagate)
        }
        if CVBufferCopyAttachment(source, kCVImageBufferColorPrimariesKey, nil) == nil {
            let primaries = height <= 480 ? kCVImageBufferColorPrimaries_SMPTE_C
                : height <= 576 ? kCVImageBufferColorPrimaries_EBU_3213 : kCVImageBufferColorPrimaries_ITU_R_709_2
            CVBufferSetAttachment(shown, kCVImageBufferColorPrimariesKey, primaries, .shouldPropagate)
        }
    }

    // MARK: - How it is going

    private func note(_ frame: Frame, lost: Bool, seconds: Double) {
        if frame == .upscaled {
            report.upscaled += 1
            report.seconds += seconds
            report.worst = max(report.worst, seconds)
        } else {
            report.plain += 1
        }
        judge(frame, lost: lost, seconds: seconds)
        let now = CACurrentMediaTime()
        guard now - report.since >= Self.reportEvery, let plan, let output = plan.output else { return }
        let average = report.upscaled > 0 ? report.seconds / Double(report.upscaled) : 0
        Self.log("\(plan.width)x\(plan.height) to \(output.width)x\(output.height): \(report.upscaled) frames "
            + "upscaled, \(Self.milliseconds(average)) average, \(Self.milliseconds(report.worst)) worst, "
            + "\(report.plain) scaled plainly")
        report = (upscaled: 0, seconds: 0, worst: 0, plain: 0, since: now)
    }

    /// Gives the stream its own frames back when the upscaler cannot keep up, or frames cannot be made at all.
    private func judge(_ frame: Frame, lost: Bool, seconds: Double) {
        streak.lost = lost ? streak.lost + 1 : 0
        if streak.lost >= Self.streakLimit {
            return giveUp("\(streak.lost) frames in a row could be made neither way")
        }
        guard frame != .loading else { return }
        framesSinceReady += 1
        guard framesSinceReady > Self.warmUpFrames else { return }
        if frame == .upscaled {
            streak.missed = 0
            window.frames += 1
            window.seconds += seconds
        } else {
            streak.missed += 1
            window.missed += 1
        }
        if streak.missed >= Self.streakLimit {
            return giveUp("the upscaler missed \(streak.missed) frames in a row")
        }
        guard window.frames + window.missed >= Self.windowFrames else { return }
        let average = window.frames > 0 ? window.seconds / Double(window.frames) : 0
        let slow = average > Self.slowAverage || window.missed >= Self.missLimit
        let summary = "\(Self.milliseconds(average)) a frame on average, \(window.missed) missed of the last "
            + "\(window.frames + window.missed)"
        window = (frames: 0, seconds: 0, missed: 0, bad: slow ? window.bad + 1 : 0)
        if window.bad >= 2 { giveUp(summary + ", twice running") }
    }

    private func giveUp(_ reason: String) {
        gaveUp = true
        lastShown = nil
        Self.log("this channel goes back to its own frames: " + reason)
    }

    private static func milliseconds(_ seconds: Double) -> String {
        String(format: "%.1f ms", seconds * 1000)
    }

    private static func log(_ text: String) {
        Logger.player.info("\("Enhance: " + text, privacy: .public)")
    }
}
#else
nonisolated enum GFEnhancer {
    /// Every frame shown as it is.
    static func hook() -> (CVPixelBuffer) -> CVPixelBuffer? {
        { _ in nil }
    }
}
#endif
