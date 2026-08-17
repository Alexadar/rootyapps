import Foundation
import CoreGraphics
import RecipeKit

/// Turns a recipe into the picture on screen: `original + (mask × strength × pass)`.
///
/// ### The one line that matters
///
/// ```swift
/// case .original: return original
/// ```
///
/// When the composite says `.original`, this returns **the original `CGImage` it was handed** — the
/// same object, not a copy, not a composite at alpha zero. The product promise is that sliding the
/// dial to 0 gives back the original *bit for bit*, and a promise about bytes is kept by skipping
/// the pipeline, not by trusting a blend, a colour space and an encode to round the same way three
/// times in a row. `CompositorChecks` asserts identity, not merely equality.
enum PhotoCompositor {

    /// - Parameters:
    ///   - original: the decoded, orientation-normalised import.
    ///   - pass: what the enhancer returned. `nil` when no pass has completed.
    ///   - masks: coverage images, keyed by source. Sampled from the red channel; resized here if
    ///     they do not match the photo.
    static func render(original: CGImage,
                       pass: CGImage?,
                       composite: Composite,
                       masks: [MaskSource: CGImage]) -> CGImage {
        switch composite {
        case .original:
            return original

        case .blended(let layers):
            guard let pass, !layers.isEmpty else { return original }
            guard var canvas = RGBABuffer(original),
                  let enhanced = RGBABuffer(pass, width: canvas.width, height: canvas.height)
            else { return original }

            for layer in layers {
                let coverage = layer.mask.flatMap { ref -> Coverage? in
                    guard let image = masks[ref.source],
                          let buffer = RGBABuffer(image, width: canvas.width, height: canvas.height)
                    else { return nil }
                    return Coverage(buffer: buffer, inverted: ref.inverted)
                }

                // A masked scope with no mask yet paints **nothing**. Falling back to the whole
                // frame would silently turn "subject only" into "everything", which is the one
                // mistake a user would not forgive.
                if layer.mask != nil && coverage == nil { continue }

                canvas.blend(enhanced, fraction: layer.fraction, coverage: coverage)
            }

            return canvas.cgImage() ?? original
        }
    }
}

/// A mask, and which way round to read it.
struct Coverage {
    let buffer: RGBABuffer
    let inverted: Bool

    @inline(__always)
    func value(at index: Int) -> Double {
        let raw = Double(buffer.pixels[index]) / 255
        return inverted ? 1 - raw : raw
    }
}

/// An 8-bit RGBA buffer in device RGB, alpha skipped.
///
/// One fixed format at the door, so nothing downstream reasons about premultiplication or byte
/// order. Photos arrive in a dozen colour spaces and bit depths; normalising once is cheaper than
/// being careful everywhere.
struct RGBABuffer {

    static let bytesPerPixel = 4

    let width: Int
    let height: Int
    var pixels: [UInt8]

    init?(_ image: CGImage, width: Int? = nil, height: Int? = nil) {
        let w = width ?? image.width
        let h = height ?? image.height
        guard w > 0, h > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: w * h * Self.bytesPerPixel)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base,
                                          width: w,
                                          height: h,
                                          bitsPerComponent: 8,
                                          bytesPerRow: w * Self.bytesPerPixel,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

        self.width = w
        self.height = h
        self.pixels = buffer
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

    /// `self = mix(self, other, fraction × coverage)`.
    mutating func blend(_ other: RGBABuffer, fraction: Double, coverage: Coverage?) {
        guard fraction > 0, other.width == width, other.height == height else { return }
        let count = width * height

        pixels.withUnsafeMutableBufferPointer { destination in
            other.pixels.withUnsafeBufferPointer { source in
                for pixel in 0..<count {
                    let alpha = fraction * (coverage?.value(at: pixel * Self.bytesPerPixel) ?? 1)
                    guard alpha > 0 else { continue }

                    let i = pixel * Self.bytesPerPixel
                    for channel in 0..<3 {
                        let a = Double(destination[i + channel])
                        let b = Double(source[i + channel])
                        destination[i + channel] = UInt8(min(max((a + (b - a) * alpha).rounded(), 0), 255))
                    }
                }
            }
        }
    }
}
