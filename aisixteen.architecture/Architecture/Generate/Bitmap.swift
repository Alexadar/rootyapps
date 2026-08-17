import CoreGraphics
import Foundation
import ImageIO
import RedesignKit
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

/// The one place raw pixels become a picture.
///
/// `PreviewImage` (bytes + size) is the currency below this line, because `CGImage` is not
/// `Sendable` and forcing it across an actor boundary with `@unchecked Sendable` is how you get a
/// torn frame once a month on one device and never in a test. Conversion happens here, on the main
/// actor, exactly once per preview.
enum Bitmap {

    static func cgImage(from preview: PreviewImage) -> CGImage? {
        guard preview.isWellFormed else { return nil }
        let width = preview.size.width
        let height = preview.size.height
        guard let provider = CGDataProvider(data: preview.pixels as CFData) else { return nil }
        return CGImage(width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    static func image(from preview: PreviewImage) -> PlatformImage? {
        guard let cgImage = cgImage(from: preview) else { return nil }
        #if os(iOS)
        return UIImage(cgImage: cgImage)
        #else
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #endif
    }

    static func png(from preview: PreviewImage) -> Data? {
        guard let cgImage = cgImage(from: preview) else { return nil }
        return encode(cgImage, as: UTType.png.identifier, quality: 1)
    }

    static func jpeg(from cgImage: CGImage, quality: Double = 0.7) -> Data? {
        encode(cgImage, as: UTType.jpeg.identifier, quality: quality)
    }

    private static func encode(_ image: CGImage, as type: String, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Downscale for a thumbnail, through ImageIO rather than by drawing.
    ///
    /// A library grid that loads twelve 12-megapixel source photos to draw twelve 90-point tiles is
    /// how a device runs out of memory in a scroll view. `kCGImageSourceCreateThumbnailFromImageAlways`
    /// decodes at the target size instead of decoding and then shrinking.
    static func thumbnail(contentsOf url: URL, maxPixel: Int) -> PlatformImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        #if os(iOS)
        return UIImage(cgImage: thumbnail)
        #else
        return NSImage(cgImage: thumbnail,
                       size: NSSize(width: thumbnail.width, height: thumbnail.height))
        #endif
    }

    static func thumbnailData(from preview: PreviewImage, maxPixel: Int) -> Data? {
        guard let cgImage = cgImage(from: preview) else { return nil }
        guard let scaled = scale(cgImage, maxPixel: maxPixel) else { return nil }
        return jpeg(from: scaled, quality: 0.8)
    }

    static func scale(_ image: CGImage, maxPixel: Int) -> CGImage? {
        let longEdge = max(image.width, image.height)
        guard longEdge > maxPixel else { return image }
        let ratio = Double(maxPixel) / Double(longEdge)
        let width = Int(Double(image.width) * ratio)
        let height = Int(Double(image.height) * ratio)
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

extension Image {
    /// `Image` from whichever platform type this build uses.
    init(platform image: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: image)
        #else
        self.init(nsImage: image)
        #endif
    }
}
