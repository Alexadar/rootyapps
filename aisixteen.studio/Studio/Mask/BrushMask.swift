import Foundation
import CoreGraphics

/// The painted mask, in photo pixel coordinates.
///
/// An 8-bit coverage buffer rather than a list of strokes: the compositor wants pixels, undo is
/// already handled by Revert throwing the whole pass away, and a stroke list would have to be
/// rasterised on every frame of a drag.
///
/// Coordinates are **photo pixels, not view points**. The view converts once, at the gesture, so
/// that a brush stroke means the same thing whether the photo is zoomed on a phone or filling a Mac
/// window.
struct BrushMask {

    let width: Int
    let height: Int
    private(set) var coverage: [UInt8]
    private(set) var isEmpty: Bool

    init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.coverage = [UInt8](repeating: 0, count: self.width * self.height)
        self.isEmpty = true
    }

    /// Paints (or erases) soft-edged dabs along a path.
    ///
    /// The points come from a drag, which samples far apart when the finger moves fast; the segment
    /// between consecutive points is filled in so a quick stroke is a line and not a row of dots.
    mutating func paint(_ points: [CGPoint], radius: Double, erasing: Bool) {
        guard !points.isEmpty, radius > 0 else { return }

        var previous: CGPoint?
        for point in points {
            if let previous {
                let distance = hypot(point.x - previous.x, point.y - previous.y)
                let stepCount = max(1, Int(distance / max(1, radius * 0.35)))
                for step in 1...stepCount {
                    let t = Double(step) / Double(stepCount)
                    dab(CGPoint(x: previous.x + (point.x - previous.x) * t,
                                y: previous.y + (point.y - previous.y) * t),
                        radius: radius, erasing: erasing)
                }
            } else {
                dab(point, radius: radius, erasing: erasing)
            }
            previous = point
        }

        isEmpty = !coverage.contains { $0 > 0 }
    }

    mutating func clear() {
        coverage = [UInt8](repeating: 0, count: width * height)
        isEmpty = true
    }

    /// A soft dab: full coverage in the middle, easing to nothing at the rim, so the composite does
    /// not show a hard circular edge where the brush stopped.
    private mutating func dab(_ centre: CGPoint, radius: Double, erasing: Bool) {
        let minX = max(0, Int(centre.x - radius))
        let maxX = min(width - 1, Int(centre.x + radius))
        let minY = max(0, Int(centre.y - radius))
        let maxY = min(height - 1, Int(centre.y + radius))
        guard minX <= maxX, minY <= maxY else { return }

        let feather = radius * 0.35
        let solid = radius - feather

        for y in minY...maxY {
            for x in minX...maxX {
                let distance = hypot(Double(x) - centre.x, Double(y) - centre.y)
                guard distance <= radius else { continue }
                let strength = distance <= solid ? 1 : 1 - (distance - solid) / max(feather, 1)
                let value = UInt8(min(max(strength * 255, 0), 255))
                let index = y * width + x

                if erasing {
                    coverage[index] = UInt8(max(0, Int(coverage[index]) - Int(value)))
                } else {
                    coverage[index] = max(coverage[index], value)
                }
            }
        }
    }

    /// The mask as the compositor reads it: grey, white where painted.
    func cgImage() -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) {
            let value = coverage[index]
            pixels[index * 4] = value
            pixels[index * 4 + 1] = value
            pixels[index * 4 + 2] = value
            pixels[index * 4 + 3] = 255
        }
        return pixels.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return nil }
            return context.makeImage()
        }
    }
}
