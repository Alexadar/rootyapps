import SwiftUI
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

extension Image {
    /// One spelling for both platforms, so no view carries an `#if`.
    init(cgImage image: CGImage, label: Text? = nil) {
        #if canImport(UIKit)
        self.init(uiImage: UIImage(cgImage: image))
        #else
        self.init(nsImage: NSImage(cgImage: image,
                                   size: NSSize(width: image.width, height: image.height)))
        #endif
        _ = label
    }
}

/// Decoding and encoding, in one place.
///
/// Everything the app writes is HEIC where the platform supports it, falling back to JPEG. Both are
/// only ever used for the **enhanced copy** — the original is copied byte for byte at import and is
/// never re-encoded, which is the difference between "we kept your photo" and "we kept a photo that
/// looks like yours".
enum ImageCoder {

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        // `shouldCacheImmediately` keeps the decode off the first draw, where it would show up as a
        // stutter the moment a photo is picked.
        let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }

    /// The orientation a photo was shot at, so a portrait picture does not arrive on its side.
    static func orientation(of data: Data) -> CGImagePropertyOrientation {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let raw = properties[kCGImagePropertyOrientation] as? UInt32,
              let orientation = CGImagePropertyOrientation(rawValue: raw)
        else { return .up }
        return orientation
    }

    static func encode(_ image: CGImage, as type: UTType = .heic, quality: Double = 0.92) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)
        else {
            // Not every platform build can write HEIC; JPEG always can, and a photo the user cannot
            // save is worse than a slightly larger file.
            return type == .jpeg ? nil : encode(image, as: .jpeg, quality: quality)
        }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return type == .jpeg ? nil : encode(image, as: .jpeg, quality: quality)
        }
        return data as Data
    }

    /// Applies the EXIF orientation into the pixels once, at import.
    ///
    /// Every later stage — masking, compositing, the split handle — works in pixel coordinates, and
    /// a photo that is still carrying an orientation flag makes every one of those a special case.
    static func normalisingOrientation(_ image: CGImage,
                                       _ orientation: CGImagePropertyOrientation) -> CGImage {
        guard orientation != .up else { return image }

        let swapsAxes = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
        let width = swapsAxes ? image.height : image.width
        let height = swapsAxes ? image.width : image.height

        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }

        context.concatenate(transform(for: orientation,
                                      width: Double(image.width),
                                      height: Double(image.height)))
        let drawRect = swapsAxes
            ? CGRect(x: 0, y: 0, width: Double(image.height), height: Double(image.width))
            : CGRect(x: 0, y: 0, width: Double(image.width), height: Double(image.height))
        context.draw(image, in: drawRect)
        return context.makeImage() ?? image
    }

    private static func transform(for orientation: CGImagePropertyOrientation,
                                  width: Double,
                                  height: Double) -> CGAffineTransform {
        switch orientation {
        case .up:      return .identity
        case .upMirrored:
            return CGAffineTransform(translationX: width, y: 0).scaledBy(x: -1, y: 1)
        case .down:
            return CGAffineTransform(translationX: width, y: height).rotated(by: .pi)
        case .downMirrored:
            return CGAffineTransform(translationX: 0, y: height).scaledBy(x: 1, y: -1)
        case .left:
            return CGAffineTransform(translationX: 0, y: width)
                .rotated(by: 3 * .pi / 2)
        case .leftMirrored:
            return CGAffineTransform(translationX: 0, y: width)
                .rotated(by: 3 * .pi / 2)
                .translatedBy(x: height, y: 0)
                .scaledBy(x: -1, y: 1)
        case .right:
            return CGAffineTransform(translationX: height, y: 0).rotated(by: .pi / 2)
        case .rightMirrored:
            return CGAffineTransform(translationX: height, y: 0)
                .rotated(by: .pi / 2)
                .translatedBy(x: width, y: 0)
                .scaledBy(x: -1, y: 1)
        }
    }
}
