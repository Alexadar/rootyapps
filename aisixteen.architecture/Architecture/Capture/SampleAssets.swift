import Foundation
import ImageIO
import RedesignKit

/// The two bundled sample photos.
///
/// They exist so the Simulator — which has no camera — can still reach every screen, and so the UI
/// suite has a capture path that does not depend on a device. They are a schematic room and a
/// schematic facade: enough geometry for a depth map and a wipe to have something to track, and
/// obviously not photographs.
///
/// ⚠️ They are SAMPLES. They must never appear in a store screenshot as a *result*, for the same
/// reason the `Mock` configuration must never be archived: showing a procedural picture as model
/// output is a lie about what the app does.
enum SampleAssets {

    static func photoData(for mode: DirectionMode) -> Data? {
        let name = mode == .interior ? "SampleInterior" : "SampleExterior"
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return try? Data(contentsOf: url)
    }

    static func photoURL(for mode: DirectionMode) -> URL? {
        let name = mode == .interior ? "SampleInterior" : "SampleExterior"
        return Bundle.main.url(forResource: name, withExtension: "png")
    }

    /// Read the real dimensions rather than assuming them — through ImageIO, which reads the
    /// header only and never decodes the pixels.
    static func pixelSize(of data: Data) -> PixelSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return PixelSize(width: width, height: height)
    }

    static func pixelSize(of url: URL) -> PixelSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return PixelSize(width: width, height: height)
    }
}
