import SwiftUI
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

extension PlatformImage {
    /// The underlying `CGImage`, however this platform spells it.
    var cgImageForRefinement: CGImage? {
        #if canImport(UIKit)
        return cgImage
        #else
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

/// Bridges the Kit's raw RGBA buffers to the platform's image types.
///
/// `GenerationKit` speaks bytes, not `UIImage`, so it can stay Foundation-only and so the real
/// pipeline — which produces buffers — needs no adapter. The cost of that decision is exactly this
/// file, and it is deliberately zero-copy: `CGDataProvider` wraps the `Data` rather than duplicating
/// twelve megabytes on every preview.
enum Bitmap {

    static let bytesPerPixel = 4

    /// Wraps an RGBA buffer as a `CGImage`. `nil` if the buffer is not the size it claims to be —
    /// which is a renderer bug, and better surfaced as a missing preview than as a garbled one.
    static func cgImage(rgba: Data, width: Int, height: Int) -> CGImage? {
        let expected = width * height * bytesPerPixel
        guard rgba.count == expected, width > 0, height > 0 else { return nil }
        guard let provider = CGDataProvider(data: rgba as CFData) else { return nil }
        return CGImage(width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: width * bytesPerPixel,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    static func platformImage(rgba: Data, width: Int, height: Int) -> PlatformImage? {
        guard let cg = cgImage(rgba: rgba, width: width, height: height) else { return nil }
        return platformImage(cg: cg, width: width, height: height)
    }

    static func platformImage(cg: CGImage, width: Int, height: Int) -> PlatformImage {
        #if canImport(UIKit)
        return UIImage(cgImage: cg)
        #else
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
        #endif
    }

    /// PNG, because a wallpaper is stored once and looked at forever — a JPEG's ringing around the
    /// high-contrast edges these images are full of would be permanent.
    static func pngData(cg: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func pngData(rgba: Data, width: Int, height: Int) -> Data? {
        guard let cg = cgImage(rgba: rgba, width: width, height: height) else { return nil }
        return pngData(cg: cg)
    }

    /// Reads a stored PNG back to a platform image.
    static func platformImage(pngData: Data) -> PlatformImage? {
        #if canImport(UIKit)
        return UIImage(data: pngData)
        #else
        return NSImage(data: pngData)
        #endif
    }
}


extension PlatformImage {
    /// The picture's size in **pixels**, not points.
    ///
    /// `NSImage.size` is in points and reflects whatever DPI the representation claims, so it is the
    /// wrong number for laying a pixel-space tile grid over an image. The CGImage is the truth.
    var wpPixelSize: CGSize {
        guard let cg = cgImageForRefinement else { return .zero }
        return CGSize(width: cg.width, height: cg.height)
    }
}
