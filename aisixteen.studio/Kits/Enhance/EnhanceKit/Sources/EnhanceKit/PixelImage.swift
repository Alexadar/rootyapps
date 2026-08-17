import Foundation
import CoreGraphics

/// An 8-bit RGBA buffer, and the two conversions to and from `CGImage`.
///
/// Everything here goes through one fixed format — device RGB, 8 bits per channel, alpha skipped —
/// so no code downstream has to reason about premultiplication or byte order. Photos arrive in a
/// dozen colour spaces and bit depths; normalising once at the door is cheaper than being careful
/// everywhere.
struct PixelImage {

    let width: Int
    let height: Int
    /// `width * height * 4`, RGBX.
    var pixels: [UInt8]

    static let bytesPerPixel = 4

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Decodes into the canonical format, optionally scaling. Returns `nil` for anything CoreGraphics
    /// cannot draw — a caller turns that into `EnhanceError.unsupportedImage` rather than trapping.
    init?(_ image: CGImage, scaledTo scale: Double = 1) {
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        var buffer = [UInt8](repeating: 0, count: width * height * Self.bytesPerPixel)

        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * Self.bytesPerPixel,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard drawn else { return nil }
        self.init(width: width, height: height, pixels: buffer)
    }

    func cgImage() -> CGImage? {
        var buffer = pixels
        return buffer.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * Self.bytesPerPixel,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return nil }
            return context.makeImage()
        }
    }

    @inline(__always)
    func index(x: Int, y: Int) -> Int {
        (min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)) * Self.bytesPerPixel
    }
}
