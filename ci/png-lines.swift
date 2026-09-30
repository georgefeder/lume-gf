// Prints a picture's brightness (luma, 0-255) along straight lines, one output line per line asked for, for
// guide-check.py. Lines are vertical or horizontal, in pixels from the top left, both ends included.
// Usage: swift png-lines.swift <png> x0,y0,x1,y1 [x0,y0,x1,y1 ...]
import CoreGraphics
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("png-lines: \(message)\n".utf8))
    exit(2)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else { fail("usage: png-lines.swift PNG x0,y0,x1,y1 ...") }
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else { fail("cannot read \(arguments[1])") }

let width = image.width
let height = image.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return false }
    // drawn this way the buffer's first row is the picture's top row
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return true
}
guard drawn else { fail("cannot draw \(arguments[1])") }

func luma(_ x: Int, _ y: Int) -> Int {
    let i = (min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)) * 4
    return Int((0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1]) + 0.114 * Double(pixels[i + 2])).rounded())
}

for spec in arguments.dropFirst(2) {
    let n = spec.split(separator: ",").compactMap { Int($0) }
    guard n.count == 4, n[0] == n[2] || n[1] == n[3] else { fail("not a vertical or horizontal line: \(spec)") }
    let values: [Int] = n[0] == n[2]
        ? stride(from: n[1], through: n[3], by: n[3] >= n[1] ? 1 : -1).map { luma(n[0], $0) }
        : stride(from: n[0], through: n[2], by: n[2] >= n[0] ? 1 : -1).map { luma($0, n[1]) }
    print(values.map(String.init).joined(separator: " "))
}
