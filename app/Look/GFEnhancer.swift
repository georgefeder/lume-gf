import CoreMedia
import CoreVideo
import Foundation
import OSLog
import QuartzCore
import VideoToolbox

/// Lume GF: Apple's low-latency super resolution on SD and 720p channels, full screen on Apple TV with Settings ▸
/// KSPlayer ▸ "Enhance SD & 720p" on (Georgs, 26 Oct 2026: SD and 720p "definitely whack"). KSPlayer hands it each
/// new frame just before showing it (`KSOptions.gfProcessFrame`, deps/KSPlayer/0002) and shows what it returns: the
/// frame upscaled by the factor `GFEnhancePlan` picks, or nil for a frame left as it is (1080p and up).
///
/// One shared upscaler: its model stays loaded from channel to channel (a load on every zap would slow it), and each
/// stream's hook (`hook()`) starts that stream's counts afresh. Every frame of a stream comes back at one size, since a
/// new size rebuilds KSPlayer's display layer: a frame the upscaler fails or is late with is scaled plainly to that
/// size, and a stream it cannot keep up with goes back to its own frames for good (one rebuild; plain scaling all the
/// way would look worse than none). How it went is in the diagnostic report ("Enhance: ...") every 30 seconds.
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
        /// The upscaler's session for this size, nil when frames of this size are passed through.
        var configuration: VTLowLatencySuperResolutionScalerConfiguration?
        /// The size frames come back at, and where they are made; nil when frames are passed through.
        var output: (width: Int, height: Int, pool: CVPixelBufferPool)?
    }

    static let shared = GFEnhancer()

    /// KSPlayer's hook for one stream (one options object): its frames are counted as a stream of their own.
    static func hook() -> (CVPixelBuffer) -> CVPixelBuffer? {
        let stream = UUID()
        return { shared.process($0, stream: stream) }
    }

    /// A frame the upscaler may take this long before plain scaling stands in for it (a 50 fps frame lasts 20 ms).
    private static let frameTimeout: DispatchTimeInterval = .milliseconds(40)
    /// An average this slow over `windowFrames` frames, or this many failures, gives the stream its own frames back:
    /// the picture would stutter otherwise. The first `warmUpFrames` after the model loads are not judged.
    private static let slowAverage: Double = 0.014, failureLimit = 5, windowFrames = 50, warmUpFrames = 10
    private static let reportEvery: CFTimeInterval = 30

    /// KSPlayer calls on the main thread, and from its decoding thread for a stream's first frame.
    private let lock = NSLock()
    private lazy var processor = VTFrameProcessor()
    private var plan: Plan?
    private var sessionStarted = false
    private var framesSinceStart = 0
    private var transfer: VTPixelTransferSession?
    /// Frames converted to a format the upscaler reads (KSPlayer's 8-bit 4:2:0 channels come as three planes).
    private var sourcePool: CVPixelBufferPool?
    private var frameNumber: Int64 = 0

    private var stream: UUID?
    /// The stream it could not keep up with: its frames go through as they are.
    private var gaveUp = false
    private var window = (frames: 0, seconds: 0.0, failures: 0)
    private var report = (frames: 0, seconds: 0.0, worst: 0.0, plain: 0, since: CACurrentMediaTime())

    private init() {}

    /// The frame to show for `buffer` of `stream`: upscaled, plainly scaled to the same size, or nil to show `buffer`.
    func process(_ buffer: CVPixelBuffer, stream: UUID) -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        if stream != self.stream { begin(stream) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        if plan?.width != width || plan?.height != height { configure(width: width, height: height) }
        guard !gaveUp, let plan, let configuration = plan.configuration, let output = plan.output else { return nil }
        let start = CACurrentMediaTime()
        var result = upscaled(buffer, with: configuration, into: output.pool)
        let upscaling = result != nil
        if result == nil {
            result = plainlyScaled(buffer, into: output.pool)
            report.plain += 1
        }
        guard let shown = result else { return nil }
        Self.carryAttachments(from: buffer, to: shown)
        note(seconds: CACurrentMediaTime() - start, upscaled: upscaling)
        return shown
    }

    // MARK: - Streams and frame sizes

    /// A new stream: its own counts, and another chance if the last one was given back its frames. The model and the
    /// size it was set up for stay.
    private func begin(_ stream: UUID) {
        self.stream = stream
        gaveUp = false
        window = (frames: 0, seconds: 0, failures: 0)
        report = (frames: 0, seconds: 0, worst: 0, plain: 0, since: CACurrentMediaTime())
    }

    private func configure(width: Int, height: Int) {
        if sessionStarted { processor.endSession() }
        sessionStarted = false
        sourcePool = nil
        window = (frames: 0, seconds: 0, failures: 0)
        plan = Plan(width: width, height: height)
        let size = "\(width)x\(height)"
        guard VTLowLatencySuperResolutionScalerConfiguration.isSupported else {
            return Self.log("\(size) left as it is: this device has no low-latency super resolution")
        }
        let factors = VTLowLatencySuperResolutionScalerConfiguration.supportedScaleFactors(frameWidth: width,
                                                                                           frameHeight: height)
        guard let factor = GFEnhancePlan.scale(width: width, height: height, supported: factors) else {
            if height < GFEnhancePlan.fullHDLines {
                let listed = factors.map { "\($0)" }.joined(separator: ", ")
                Self.log("\(size) left as it is: no supported factor fits 4K (\(listed))")
            }
            return
        }
        let target = GFEnhancePlan.scaled(width: width, height: height, by: factor)
        let configuration = VTLowLatencySuperResolutionScalerConfiguration(frameWidth: width, frameHeight: height,
                                                                           scaleFactor: factor)
        guard let pool = Self.pool(configuration.destinationPixelBufferAttributes, width: target.width,
                                   height: target.height)
        else { return Self.log("\(size) left as it is: no buffers for \(target.width)x\(target.height)") }
        // the model loads here, on the first frame of this size (Apple: it can take longer than a frame)
        let loading = CACurrentMediaTime()
        do {
            try processor.startSession(configuration: configuration)
        } catch {
            return Self.log("\(size) left as it is: the upscaler did not start (\(error))")
        }
        sessionStarted = true
        framesSinceStart = 0
        plan?.configuration = configuration
        plan?.output = (width: target.width, height: target.height, pool: pool)
        sourcePool = Self.pool(configuration.sourcePixelBufferAttributes, width: width, height: height,
                               format: configuration.supportedPixelFormats.first)
        Self.log("\(size) to \(target.width)x\(target.height) (\(factor)x), ready in "
            + Self.milliseconds(CACurrentMediaTime() - loading))
    }

    private static func pool(_ attributes: [String: Any], width: Int, height: Int, format: OSType? = nil)
        -> CVPixelBufferPool? {
        var settings = attributes
        settings[kCVPixelBufferWidthKey as String] = width
        settings[kCVPixelBufferHeightKey as String] = height
        if let format { settings[kCVPixelBufferPixelFormatTypeKey as String] = format }
        if settings[kCVPixelBufferIOSurfacePropertiesKey as String] == nil {
            settings[kCVPixelBufferIOSurfacePropertiesKey as String] = [String: Any]()
        }
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, settings as CFDictionary, &pool)
        return pool
    }

    private static func buffer(from pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        return buffer
    }

    // MARK: - Per frame

    /// Holds what the upscaler's completion handler reports, read once it has signalled.
    private final class Outcome: @unchecked Sendable {
        var error: (any Error)?
    }

    private func upscaled(_ buffer: CVPixelBuffer, with configuration: VTLowLatencySuperResolutionScalerConfiguration,
                          into pool: CVPixelBufferPool) -> CVPixelBuffer? {
        let readable = configuration.supportedPixelFormats.contains(CVPixelBufferGetPixelFormatType(buffer))
        guard let source = readable ? buffer : converted(buffer), let destination = Self.buffer(from: pool) else {
            return nil
        }
        frameNumber += 1
        let time = CMTime(value: frameNumber, timescale: 600)
        guard let sourceFrame = VTFrameProcessorFrame(buffer: source, presentationTimeStamp: time),
              let destinationFrame = VTFrameProcessorFrame(buffer: destination, presentationTimeStamp: time)
        else { return nil }
        let parameters = VTLowLatencySuperResolutionScalerParameters(sourceFrame: sourceFrame,
                                                                    destinationFrame: destinationFrame)
        let done = DispatchSemaphore(value: 0), outcome = Outcome()
        processor.process(parameters: parameters) { _, error in
            outcome.error = error
            done.signal()
        }
        // a late frame is dropped from the upscaler (it may still write into `destination`, which nothing shows: the
        // frame holds on to it, so the pool cannot hand it out again meanwhile)
        guard done.wait(timeout: .now() + Self.frameTimeout) == .success, outcome.error == nil else { return nil }
        return destination
    }

    /// `buffer` in a format the upscaler reads, at its own size.
    private func converted(_ buffer: CVPixelBuffer) -> CVPixelBuffer? {
        guard let target = Self.buffer(from: sourcePool), pixelTransfer(buffer, to: target) else { return nil }
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

    private func note(seconds: Double, upscaled: Bool) {
        report.frames += 1
        report.seconds += seconds
        report.worst = max(report.worst, seconds)
        framesSinceStart += 1
        if framesSinceStart > Self.warmUpFrames {
            if upscaled {
                window.frames += 1
                window.seconds += seconds
            } else {
                window.failures += 1
            }
        }
        if window.frames + window.failures >= Self.windowFrames {
            let average = window.frames > 0 ? window.seconds / Double(window.frames) : 0
            if average > Self.slowAverage || window.failures >= Self.failureLimit {
                gaveUp = true
                Self.log("this channel goes back to its own frames: \(Self.milliseconds(average)) a frame on "
                    + "average, \(window.failures) failed of the last \(window.frames + window.failures)")
            }
            window = (frames: 0, seconds: 0, failures: 0)
        }
        let now = CACurrentMediaTime()
        guard now - report.since >= Self.reportEvery, report.frames > 0, let plan, let output = plan.output else {
            return
        }
        Self.log("\(plan.width)x\(plan.height) to \(output.width)x\(output.height): \(report.frames) frames, "
            + "\(Self.milliseconds(report.seconds / Double(report.frames))) average, "
            + "\(Self.milliseconds(report.worst)) worst, \(report.plain) scaled plainly")
        report = (frames: 0, seconds: 0, worst: 0, plain: 0, since: now)
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
