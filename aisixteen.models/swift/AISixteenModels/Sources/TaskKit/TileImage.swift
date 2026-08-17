import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// PNG in, PNG out, for the tiles a job leaves on disk.
///
/// ImageIO directly rather than `UIImage`/`NSImage`. Three reasons, and the third is the one that
/// matters: it is the same code on both platforms, it does not drag a UI framework into a package
/// that has no interface, and **it does not go through a platform image's colour handling**. A tile
/// read back through `UIImage` and re-drawn is not guaranteed to be the bytes that were written, and
/// a resumed picture that differs from an uninterrupted one by a channel is exactly the kind of
/// failure that reads as the model being unreliable.
enum TileImage {

    /// PNG, not JPEG. A tile is written once and composited into something kept forever; JPEG
    /// ringing around high-contrast edges would be baked into the wallpaper permanently, and the
    /// overlap blending would smear it across the seam.
    static func png(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func image(fromPNG data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

public enum JobStoreError: Error, Equatable {
    /// A finished tile could not be encoded or written. Worth surfacing rather than swallowing: it
    /// means the next resume will silently redo work that was already paid for.
    case tileNotWritten
}
