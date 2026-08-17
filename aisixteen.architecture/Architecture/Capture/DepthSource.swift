import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import RedesignKit

/// Reads depth from whatever the platform actually offers, and is honest about which it was.
///
/// **Real Apple frameworks do everything here except one case.** LiDAR, dual-camera parallax and
/// the disparity already embedded in a Portrait-mode HEIC are all camera-measured and all
/// available through AVFoundation and ImageIO. The one case no Apple API covers is a flat photo
/// with no auxiliary data — monocular estimation needs a neural network (Depth Anything, MiDaS,
/// Depth Pro), that network lives in `../aisixteen.models`, and in this build it is mocked.
enum DepthSource {

    /// Pull depth out of an image file's auxiliary data.
    ///
    /// A photo shot in Portrait mode carries a real disparity map alongside the pixels, and it is
    /// free — no model, no estimation, genuinely measured by the camera that took it. Most
    /// imported photos will not have it; the ones that do should not be re-estimated.
    static func embedded(in url: URL) -> (values: [Float], size: PixelSize)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        // Disparity first: it is what the ControlNet convention wants (large = near), so when both
        // are present there is nothing to invert.
        for auxiliaryType in [kCGImageAuxiliaryDataTypeDisparity, kCGImageAuxiliaryDataTypeDepth] {
            guard let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, auxiliaryType)
                    as? [AnyHashable: Any],
                  let depthData = try? AVDepthData(fromDictionaryRepresentation: info) else {
                continue
            }
            let converted = depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
            if let values = read(converted.depthDataMap) {
                return values
            }
        }
        return nil
    }

    /// Convert an `AVDepthData` from a live capture.
    static func values(from depthData: AVDepthData) -> (values: [Float], size: PixelSize)? {
        let converted = depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
        return read(converted.depthDataMap)
    }

    /// Whether the capture device measured this scene or inferred it.
    ///
    /// iOS only: these device types do not exist on macOS, where the app has no camera path at all
    /// and every photo arrives through import.
    #if os(iOS)
    static func provenance(for device: AVCaptureDevice?) -> DepthProvenance {
        guard let device else { return .estimated }
        switch device.deviceType {
        case .builtInLiDARDepthCamera:
            return .lidar
        case .builtInTrueDepthCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera:
            return .dualCamera
        default:
            return .estimated
        }
    }
    #endif

    /// Read a `DisparityFloat32` buffer into a flat row-major array.
    ///
    /// Row-by-row rather than one `memcpy`: a pixel buffer's `bytesPerRow` is padded to a hardware
    /// alignment and is very often wider than `width * 4`. Copying the whole block treats that
    /// padding as pixels and produces a depth map that shears diagonally — which looks like a
    /// plausible slanted wall rather than like a bug.
    private static func read(_ buffer: CVPixelBuffer) -> (values: [Float], size: PixelSize)? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0,
              let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        var values = [Float](repeating: 0, count: width * height)

        for row in 0..<height {
            let rowStart = base.advanced(by: row * bytesPerRow)
                .assumingMemoryBound(to: Float.self)
            for column in 0..<width {
                values[row * width + column] = rowStart[column]
            }
        }

        return (values, PixelSize(width: width, height: height))
    }

    /// A gradient, for the Simulator and for tests. Labelled `.synthetic` and never `.estimated` —
    /// putting "Depth estimated — geometry will hold" over a gradient would be a claim about a
    /// model that has not run.
    static func synthetic(size: PixelSize = PixelSize(width: 256, height: 256)) -> [Float] {
        var values = [Float](repeating: 0, count: size.pixelCount)
        for y in 0..<size.height {
            let nearness = Float(y) / Float(max(size.height - 1, 1))
            for x in 0..<size.width {
                let bow = 1 - abs(Float(x) / Float(max(size.width - 1, 1)) - 0.5) * 0.4
                values[y * size.width + x] = nearness * bow
            }
        }
        return values
    }
}

/// What a shutter press produces: the photo, its depth, and where both came from.
struct SourceShot: Equatable {
    let mode: DirectionMode
    let imageData: Data
    let pixelSize: PixelSize
    /// Row-major disparity, full resolution. The 512 × 512 ControlNet image is derived from this
    /// at request time — storing only the small one would throw away everything a later,
    /// larger-shape model could use.
    let depthValues: [Float]
    let depthSize: PixelSize
    let provenance: DepthProvenance

    /// Whether the geometry claim is earned. `.estimated` still gets a badge, just a different one.
    var hasDepth: Bool { !depthValues.isEmpty }
}

/// Interior or exterior, chosen at capture because it changes the coach copy AND the preset set.
enum DirectionMode: String, CaseIterable, Equatable, Sendable {
    case interior
    case exterior

    var title: String {
        switch self {
        case .interior: return "Interior"
        case .exterior: return "Exterior"
        }
    }
}
