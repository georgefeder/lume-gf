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
/// stream's hook (`hook()`) starts that stream's counts afresh. The model loads, and runs once on blank frames, on a
/// queue of its own (Apple: a load can take longer than a frame, and the main thread shows frames too); meanwhile
/// frames are scaled plainly to the size the upscaler will make. Every frame of a stream comes back at that one size,
/// since a new size rebuilds KSPlayer's display layer: a frame the upscaler is busy, late or failed with is scaled
/// plainly, and a stream it cannot keep up with goes back to its own frames for good (one rebuild; plain scaling all
/// the way would look no better than none). How it went is in the diagnostic report ("Enhance: ...") every 30 seconds.
///
/// Only an Apple TV device build has it: the simulators' SDKs lack the upscaler, so they (and the iPhone, which never
/// switches it on) get a stand-in that leaves every frame as it is. ci/device-typecheck.sh compiles the real one
/// against the Apple TV SDK on every test run, since no other CI build does.
#if os(tvOS) && !targetEnvironment(simulator)
@available(tvOS 26.0, *)
nonisolated final class GFEnhancer: @unchecked Sendable {
    /// One frame size and what is done with it.
    private nonisolated struct Plan {
        var width: Int, height: Int
        /// When frames of this size began.
        let since = CACurrentMediaTime()
        /// The size frames come back at, and where they are made; nil when frames of this size are passed through.
        var output: (width: Int, height: Int, pool: CVPixelBufferPool)?
        /// The format the upscaler reads; frames in another are converted into `sourcePool` first.
        var sourceFormat: OSType = 0
        var sourcePool: CVPixelBufferPool?
        /// The upscaler with this size's model loaded; until then frames are scaled plainly.
        var processor: VTFrameProcessor?
        /// The model or the frames for it could not be made: frames are passed through, until the next stream tries
        /// again.
        var failed = false
    }

    /// The frame size and factor a model is loaded for.
    private nonisolated struct Model: Equatable {
        let width: Int, height: Int
        let factor: Float
    }

    /// What became of a frame: upscaled; scaled plainly as the upscaler was late or failed (missed), was still on an
    /// earlier late frame (busy), or as the model loads.
    private nonisolated enum Frame { case upscaled, missed, busy, loading }

    /// The upscaler's answer for one frame, read once it has signalled.
    private nonisolated final class Request: @unchecked Sendable {
        let done = DispatchSemaphore(value: 0)
        let sent = CACurrentMediaTime()
        var error: (any Error)?
    }

    /// How a model's run on blank frames went: its time, why it failed, or still running after 2 seconds.
    private nonisolated enum FirstRun {
        case ran(Double), failed(String), late(Request)
    }

    static let shared = GFEnhancer()

    /// KSPlayer's hook for one stream (one options object): its frames are counted as a stream of their own, and the
    /// newest stream's are the ones upscaled (an older player still drawing, as a zap overlaps, gets its own frames).
    static func hook() -> (CVPixelBuffer) -> CVPixelBuffer? {
        let stream = shared.newStream()
        return { shared.process($0, stream: stream) }
    }

    /// A frame the upscaler may take this long before plain scaling stands in for it (a 50 fps frame lasts 20 ms);
    /// it is left to finish, and a request it has not answered in `abandonAfter` gives the stream its own frames back.
    private static let frameTimeout = 40, abandonAfter: CFTimeInterval = 1
    /// A newer stream that has drawn nothing for this long hands the counts back to an older one still drawing.
    private static let ownerGone: CFTimeInterval = 2
    /// The stream gets its own frames back after `streakLimit` requests in a row missed (or frames made neither way),
    /// or two windows of `windowFrames` requests in a row slower than `slowAverage` or with `missLimit` missed: the
    /// picture would stutter otherwise. The first `warmUpFrames` requests after the model loads are not judged, and a
    /// model not ready in `loadLimit` seconds gives the stream its own frames back too.
    private static let streakLimit = 4, windowFrames = 50, missLimit = 5, warmUpFrames = 10
    private static let slowAverage: Double = 0.014, loadLimit: CFTimeInterval = 10
    private static let reportEvery: CFTimeInterval = 30

    /// KSPlayer calls on the main thread, and from its decoding thread for a stream's first frame.
    private let lock = NSLock()
    /// Loads models, away from the threads showing frames.
    private let loader = DispatchQueue(label: "lv.georgefeder.lume.enhance", qos: .userInitiated)
    /// The model loaded and the upscaler running it; only `loader` touches it (frame threads use `plan.processor`).
    private var loaded: (model: Model, processor: VTFrameProcessor)?
    private var plan: Plan?
    /// Counts frame sizes, so a load another size overtook leaves the newer plan alone.
    private var generation = 0
    private var framesSinceReady = 0
    /// A request the upscaler was late with and may still be working on: it gets one at a time.
    private var pending: Request?
    private var transfer: VTPixelTransferSession?
    private var frameNumber: Int64 = 0

    /// The stream the counts are for (the newest drawing), the number the last hook was given, and when the stream
    /// last drew.
    private var stream = 0, streams = 0
    private var streamSeen: CFTimeInterval = 0
    /// The stream it could not keep up with: its frames go through as they are.
    private var gaveUp = false
    /// Shown again when a frame can be made neither way: a frame of another size would rebuild the display layer.
    private var lastShown: CVPixelBuffer?
    /// Why the last request was missed, for the give-up line.
    private var lastMiss: String?
    private var streak = (missed: 0, lost: 0)
    private var window = (frames: 0, seconds: 0.0, missed: 0, bad: 0)
    private var report = (upscaled: 0, seconds: 0.0, worst: 0.0, plain: 0, since: CACurrentMediaTime())

    private init() {}

    private func newStream() -> Int {
        lock.withLock {
            streams += 1
            return streams
        }
    }

    /// The frame to show for `buffer` of `stream`: upscaled, plainly scaled to the same size, or nil to show `buffer`.
    func process(_ buffer: CVPixelBuffer, stream: Int) -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        // an older player still drawing (as a zap overlaps) gets its own frames, unless the newer one stopped drawing
        if stream < self.stream, CACurrentMediaTime() - streamSeen < Self.ownerGone { return nil }
        if stream != self.stream { begin(stream) }
        streamSeen = CACurrentMediaTime()
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        if plan?.width != width || plan?.height != height {
            configure(width: width, height: height, format: CVPixelBufferGetPixelFormatType(buffer))
        }
        guard !gaveUp, let plan, !plan.failed, let output = plan.output else { return nil }
        let start = CACurrentMediaTime()
        var frame = Frame.loading
        var shown: CVPixelBuffer?
        if let processor = plan.processor {
            (shown, frame) = upscaled(buffer, by: processor, plan: plan, into: output.pool)
        } else if start - plan.since > Self.loadLimit {
            giveUp("the model was not ready in \(Int(Self.loadLimit)) s")
            return nil
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

    /// A new stream: its own counts, and another chance if the last one was given back its frames or the model or
    /// its frames could not be made. The model and the size it was set up for stay.
    private func begin(_ stream: Int) {
        self.stream = stream
        gaveUp = false
        lastShown = nil
        lastMiss = nil
        streak = (missed: 0, lost: 0)
        window = (frames: 0, seconds: 0, missed: 0, bad: 0)
        report = (upscaled: 0, seconds: 0, worst: 0, plain: 0, since: CACurrentMediaTime())
        if plan?.failed == true { plan = nil }
    }

    /// A new frame size: its plan, and its model loaded on `loader` (unless it is loaded already).
    private func configure(width: Int, height: Int, format: OSType) {
        generation += 1
        plan = Plan(width: width, height: height)
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
            return Self.log("\(size) left as it is: no supported factor makes whole pixels within 4K (\(listed))")
        }
        let target = GFEnhancePlan.scaled(width: width, height: height, by: factor)
        let configuration = VTLowLatencySuperResolutionScalerConfiguration(frameWidth: width, frameHeight: height,
                                                                           scaleFactor: factor)
        let reads = configuration.supportedPixelFormats
        let writes = Self.formats(in: configuration.destinationPixelBufferAttributes) ?? reads
        guard let sourceFormat = GFEnhancePlan.format(for: format, from: reads),
              let outputFormat = GFEnhancePlan.format(for: format, from: writes)
        else {
            return Self.log("\(size) left as it is: \(GFEnhancePlan.name(of: format)) frames, and the upscaler "
                + "takes 8-bit 4:2:0 only (reads \(Self.names(reads)), writes \(Self.names(writes)))")
        }
        let made = "\(target.width)x\(target.height)"
        guard let pool = Self.pool(configuration.destinationPixelBufferAttributes, width: target.width,
                                   height: target.height, format: outputFormat),
              let sourcePool = Self.pool(configuration.sourcePixelBufferAttributes, width: width, height: height,
                                         format: sourceFormat)
        else {
            plan?.failed = true
            return Self.log("\(size) left as it is: no frames for \(made)")
        }
        plan?.output = (width: target.width, height: target.height, pool: pool)
        plan?.sourceFormat = sourceFormat
        plan?.sourcePool = sourcePool
        let description = "\(size) to \(made) (\(factor)x, \(GFEnhancePlan.name(of: sourceFormat)) to "
            + "\(GFEnhancePlan.name(of: outputFormat)))"
        let model = Model(width: width, height: height, factor: factor), ticket = generation
        loader.async { [self] in load(configuration, model: model, ticket: ticket, description: description) }
    }

    /// On `loader`: loads `model` into an upscaler of its own (unless it is loaded already), runs it once, and hands it
    /// to the plan of `ticket`, if no other frame size came meanwhile.
    private func load(_ configuration: VTLowLatencySuperResolutionScalerConfiguration, model: Model, ticket: Int,
                      description: String) {
        let pools: (source: CVPixelBufferPool, output: CVPixelBufferPool)? = lock.withLock {
            guard ticket == generation, let source = plan?.sourcePool, let output = plan?.output?.pool else {
                return nil
            }
            return (source: source, output: output)
        }
        guard let pools else { return }
        func fail(_ reason: String) {
            lock.withLock {
                if ticket == generation { plan?.failed = true }
            }
            Self.log("\(description): \(reason)")
        }
        var how = "already loaded"
        // a newly loaded upscaler's run on blank frames, if it is still on it
        var late: Request?
        let fresh = loaded?.model != model
        if fresh {
            // no plan holds the old upscaler any more (a new size replaced it); this finishes what it was still on
            loaded?.processor.endSession()
            loaded = nil
            let processor = VTFrameProcessor(), start = CACurrentMediaTime()
            do {
                try processor.startSession(configuration: configuration)
            } catch {
                return fail("the upscaler did not start (\(error))")
            }
            let loading = Self.milliseconds(CACurrentMediaTime() - start)
            switch Self.warmUp(processor, pools: pools) {
            case let .ran(seconds):
                how = "ready in \(loading), first run \(Self.milliseconds(seconds))"
            case let .failed(reason):
                processor.endSession()
                return fail("the upscaler's first run failed (\(reason))")
            case let .late(request):
                how = "ready in \(loading), first run over 2 s"
                late = request
            }
            loaded = (model: model, processor: processor)
        }
        guard let processor = loaded?.processor else { return }
        lock.withLock {
            guard ticket == generation else { return }
            plan?.processor = processor
            framesSinceReady = 0
            // a request left from the old upscaler is over with it; a first run still going is the new one's
            if fresh { pending = late }
        }
        Self.log("\(description), \(how)")
    }

    /// One run on blank frames before any real one (a model's first run is its slowest).
    private static func warmUp(_ processor: VTFrameProcessor,
                               pools: (source: CVPixelBufferPool, output: CVPixelBufferPool)) -> FirstRun {
        guard let source = buffer(from: pools.source), let destination = buffer(from: pools.output) else {
            return .failed("no blank frames")
        }
        guard let sourceFrame = VTFrameProcessorFrame(buffer: source, presentationTimeStamp: .zero),
              let destinationFrame = VTFrameProcessorFrame(buffer: destination, presentationTimeStamp: .zero)
        else { return .failed("it did not take the frames") }
        let parameters = VTLowLatencySuperResolutionScalerParameters(sourceFrame: sourceFrame,
                                                                    destinationFrame: destinationFrame)
        let request = Request()
        processor.process(parameters: parameters) { _, error in
            request.error = error
            request.done.signal()
        }
        guard request.done.wait(timeout: .now() + .seconds(2)) == .success else { return .late(request) }
        if let error = request.error { return .failed("\(error)") }
        return .ran(CACurrentMediaTime() - request.sent)
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

    /// `buffer` upscaled by `processor` into a frame from `pool`, or nil with why not.
    private func upscaled(_ buffer: CVPixelBuffer, by processor: VTFrameProcessor, plan: Plan,
                          into pool: CVPixelBufferPool) -> (CVPixelBuffer?, Frame) {
        // one request at a time: while the upscaler is still on a frame it was late with, frames are scaled plainly
        if let pending {
            if pending.done.wait(timeout: .now()) == .success {
                self.pending = nil
            } else if CACurrentMediaTime() - pending.sent < Self.abandonAfter {
                return (nil, .busy)
            } else {
                // its first run is behind it (on blank frames), so this is no slow start: it has stopped answering
                self.pending = nil
                giveUp("the upscaler gave no answer in \(Int(Self.abandonAfter)) s")
                return missed("no answer")
            }
        }
        // the upscaler gets the decoder's own frame when it is in the right format and in shared memory
        let readable = CVPixelBufferGetPixelFormatType(buffer) == plan.sourceFormat
            && CVPixelBufferGetIOSurface(buffer) != nil
        guard let source = readable ? buffer : converted(buffer, into: plan.sourcePool) else {
            return missed("the frame could not be converted")
        }
        guard let destination = Self.buffer(from: pool) else { return missed("no frame to upscale into") }
        frameNumber += 1
        let time = CMTime(value: frameNumber, timescale: 600)
        guard let sourceFrame = VTFrameProcessorFrame(buffer: source, presentationTimeStamp: time),
              let destinationFrame = VTFrameProcessorFrame(buffer: destination, presentationTimeStamp: time)
        else { return missed("the upscaler did not take the frame") }
        let parameters = VTLowLatencySuperResolutionScalerParameters(sourceFrame: sourceFrame,
                                                                    destinationFrame: destinationFrame)
        let request = Request()
        processor.process(parameters: parameters) { _, error in
            request.error = error
            request.done.signal()
        }
        // a late frame is left to the upscaler, which holds on to its buffers (the pool cannot hand them out
        // meanwhile), and nothing new is asked of it until it is done
        guard request.done.wait(timeout: .now() + .milliseconds(Self.frameTimeout)) == .success else {
            pending = request
            return missed("over \(Self.frameTimeout) ms")
        }
        if let error = request.error { return missed("\(error)") }
        return (destination, .upscaled)
    }

    private func missed(_ reason: String) -> (CVPixelBuffer?, Frame) {
        lastMiss = reason
        return (nil, .missed)
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

    /// Gives the stream its own frames back when the upscaler cannot keep up, or frames cannot be made at all. Only
    /// requests are judged: frames scaled plainly while the model loads, or while the upscaler finishes a late frame,
    /// cost nothing to wait for.
    private func judge(_ frame: Frame, lost: Bool, seconds: Double) {
        streak.lost = lost ? streak.lost + 1 : 0
        if streak.lost >= Self.streakLimit {
            return giveUp("\(streak.lost) frames in a row could be made neither way")
        }
        guard frame == .upscaled || frame == .missed else { return }
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
            return giveUp("the upscaler missed \(streak.missed) frames in a row (\(lastMiss ?? "no reason given"))")
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
