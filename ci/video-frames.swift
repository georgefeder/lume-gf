// Frames and brightness from a simulator recording (ci/screenshots.sh films the iPhone opening a channel): every
// 1/fps second a 200-point-wide PNG and its mean brightness (0-1) in luma.csv, so a flash shows as a dip.
// Runs on GitHub's Mac: swift video-frames.swift <video.mp4> <out dir> <fps>
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func luma(_ image: CGImage) -> Double {
    let width = 40, height = 80
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var sum = 0.0
    for index in stride(from: 0, to: pixels.count, by: 4) {
        sum += 0.299 * Double(pixels[index]) + 0.587 * Double(pixels[index + 1]) + 0.114 * Double(pixels[index + 2])
    }
    return sum / Double(width * height) / 255
}

let arguments = CommandLine.arguments
guard arguments.count == 4, let fps = Double(arguments[3]), fps > 0 else {
    FileHandle.standardError.write(Data("usage: video-frames.swift VIDEO OUT_DIR FPS\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let asset = AVURLAsset(url: URL(fileURLWithPath: arguments[1]))
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: 200, height: 1000)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
let seconds = CMTimeGetSeconds(asset.duration)
var csv = "frame,seconds,luma\n"
var frame = 0
var time = 0.0
while time < seconds {
    let image = try generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil)
    let file = out.appendingPathComponent(String(format: "%03d.png", frame))
    if let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) {
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
    csv += String(format: "%d,%.3f,%.4f\n", frame, time, luma(image))
    frame += 1
    time += 1 / fps
}
try csv.write(to: out.appendingPathComponent("luma.csv"), atomically: true, encoding: .utf8)
print("video-frames: \(frame) frames")
