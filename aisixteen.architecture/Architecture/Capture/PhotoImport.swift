import Foundation
import ImageIO
import RedesignKit

/// Importing a photo the user already has.
///
/// The handoff is explicit that import takes THE SAME PATH as the camera — same Direction screen,
/// same everything — with one difference: depth. A Portrait-mode HEIC carries real, camera-measured
/// disparity in its auxiliary data and that is used as-is. A flat photo has none, and monocular
/// estimation is a model, so in this build it is mocked and the badge says so.
enum PhotoImport {

    static func shot(from url: URL, mode: DirectionMode) throws -> SourceShot {
        // Security-scoped access, because on the Mac this URL came out of an open panel and the
        // sandbox will not otherwise let the app read it.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let size = SampleAssets.pixelSize(of: data) else {
            throw CaptureError.failed
        }
        return shot(from: data, pixelSize: size, url: url, mode: mode)
    }

    static func shot(from data: Data, pixelSize: PixelSize, url: URL?, mode: DirectionMode) -> SourceShot {
        // Free depth, if the photo happens to carry it. Re-estimating a Portrait-mode shot that
        // already has a measured disparity map would be strictly worse.
        if let url, let embedded = DepthSource.embedded(in: url) {
            return SourceShot(mode: mode,
                              imageData: data,
                              pixelSize: pixelSize,
                              depthValues: embedded.values,
                              depthSize: embedded.size,
                              provenance: .embedded)
        }

        // ── WHERE THE DEPTH MODEL LANDS ───────────────────────────────────────────────────────
        // No Apple API estimates depth from a flat photo. That needs a network — Depth Anything V2,
        // MiDaS, Depth Pro — converted in ../aisixteen.models. Until it exists, this is synthetic
        // and the badge says "Sample depth", not "Depth estimated".
        let depthSize = PixelSize(width: 256, height: 256)
        return SourceShot(mode: mode,
                          imageData: data,
                          pixelSize: pixelSize,
                          depthValues: DepthSource.synthetic(size: depthSize),
                          depthSize: depthSize,
                          provenance: .synthetic)
    }
}
