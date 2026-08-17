import Foundation

/// Pixel dimensions. Not `CGSize`: this package is Foundation-only, and a count of pixels is an
/// integer quantity — a half-pixel image does not exist and should not be representable.
public struct PixelSize: Hashable, Sendable, Codable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var pixelCount: Int { width * height }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    /// Long edge in pixels — how the app decides thumbnail scale.
    public var longEdge: Int { max(width, height) }
}

/// 8-bit RGBA, row-major, no row padding. The one currency for pixels below the app target.
///
/// Why not `CGImage`: `CGImage` is not `Sendable` — it can be backed by a mutable
/// `CGDataProvider` — and forcing it across an actor boundary with `@unchecked Sendable` is the
/// kind of shortcut that produces a torn frame once a month on one device and never in a test.
/// Raw bytes plus a size cross freely, and the single conversion to a platform image happens on
/// the main actor in the app target. It is also what keeps this whole package Foundation-only,
/// which is what makes `swift test` finish in milliseconds.
public struct PreviewImage: Sendable, Equatable {
    public let pixels: Data
    public let size: PixelSize

    public init(pixels: Data, size: PixelSize) {
        self.pixels = pixels
        self.size = size
    }

    public var expectedByteCount: Int { size.pixelCount * 4 }

    /// Checked at the seam rather than trusted. A generator that returns a buffer of the wrong
    /// length is a bug that otherwise surfaces as a crash inside CoreGraphics, several layers
    /// away from the cause.
    public var isWellFormed: Bool {
        !size.isEmpty && pixels.count == expectedByteCount
    }
}
