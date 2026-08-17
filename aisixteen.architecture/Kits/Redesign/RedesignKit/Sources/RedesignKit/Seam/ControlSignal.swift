import Foundation

/// The kinds of conditioning map a ControlNet can take.
///
/// Each case names a SPECIFIC ControlNet, not a vague idea of "lines" or "shape". That matters:
/// the case is what tells the caller which conditioning image to produce, so a case that names the
/// wrong net is a case that quietly asks for the wrong picture and gets a poor result with nothing
/// to explain it.
public enum ControlKind: String, Sendable, Codable, CaseIterable, Hashable {
    /// `control_v11f1p_sd15_depth`. The geometry anchor, and the only kind produced today.
    case depth

    /// `control_v11p_sd15_mlsd` — straight line SEGMENTS from the M-LSD detector: walls, window
    /// frames, ceiling lines. Converted and available in the shared pack.
    ///
    /// ⚠️ NOT the same net as `.lineart`, which was what this case was originally (wrongly) called.
    /// Driving MLSD weights from a case named "lineart" would make the enum lie about which
    /// conditioning image is required.
    case mlsd

    /// `control_v11p_sd15_lineart` — artistic line DRAWINGS. A different net, not converted.
    /// Declared so the two can never be confused again, and because they compose.
    case lineart

    /// `control_v11p_sd15_normalbae` — surface normals: how light falls across a facade.
    /// Not converted.
    case normal

    /// `control_v11p_sd15_seg` — a semantic map. Not converted, and deliberately unlikely to be:
    /// the design handoff cut segmentation outright ("no region-picking UI anywhere"), and a net
    /// whose whole premise is per-region control is an invitation to reintroduce it.
    case segment

    /// Whether this app currently knows how to produce the conditioning image for this kind.
    /// A control it cannot draw is a control it must not request.
    public var isProducible: Bool { self == .depth }
}

/// Where a depth map came from. This is not trivia — it decides which badge string is honest, and
/// the four sources differ by more than an order of magnitude in quality.
public enum DepthProvenance: String, Sendable, Codable, CaseIterable, Hashable {
    /// A LiDAR scanner. Metric, reliable, iPhone/iPad Pro only.
    case lidar
    /// Dual-camera or TrueDepth parallax. Relative, noisier at distance, most devices.
    case dualCamera
    /// Disparity already embedded in an imported photo's auxiliary data — a Portrait-mode HEIC.
    /// Free depth on the import path, and genuinely camera-measured.
    case embedded
    /// Estimated from a flat photo by a monocular depth model. NO APPLE API DOES THIS — it needs
    /// a network (Depth Anything, MiDaS, Depth Pro), which lives in ../aisixteen.models and is
    /// mocked in this build.
    case estimated
    /// A gradient, for the Simulator and for tests. Never shipped as a result.
    case synthetic

    /// True where a camera actually measured the scene. The badge copy hinges on this.
    public var isMeasured: Bool {
        switch self {
        case .lidar, .dualCamera, .embedded: return true
        case .estimated, .synthetic: return false
        }
    }

    /// The one geometry claim this app is allowed to make, per the design handoff's scope
    /// decisions: depth conditioning means "walls, windows and proportions stay put", and
    /// nothing more. No dimension, no measurement, no metric — those were cut deliberately.
    public var badgeText: String {
        switch self {
        case .lidar, .dualCamera, .embedded: return "Depth read — geometry will hold"
        case .estimated: return "Depth estimated — geometry will hold"
        case .synthetic: return "Sample depth — for testing"
        }
    }
}

/// Produces the image a ControlNet actually consumes, from a full-resolution depth frame.
///
/// The contract is fixed by the converted pipeline: **512 × 512, three channels, 8-bit, and
/// inverse depth with near = bright** (the MiDaS convention every SD 1.5 depth ControlNet was
/// trained on). Getting the polarity backwards does not crash and does not look obviously wrong
/// in a thumbnail — it produces a redesign that quietly pushes the near wall away and pulls the
/// far one in. That is why this has an oracle test with hand-computed pixel values.
///
/// The app stores full-resolution float disparity as the truth and derives this at request time.
/// Storing only the 512 version would throw away everything a later, larger-shape model could use.
public enum ControlImageRenderer {

    /// The edge length every converted SD 1.5 model in this project expects. Core ML models are
    /// fixed-shape; this is not a preference.
    public static let edge = 512

    /// How a non-square source becomes a square control map.
    public enum Fit: String, Sendable, Codable {
        /// Centre-crop the long edge away. The default, and the only one that does not lie: a
        /// stretched depth map tells the model the room is a different shape than it is.
        case centerCrop
        /// Squash to square. Available for tests and for callers who have already cropped.
        case stretch
    }

    /// Depth frames arrive in two conventions and the difference is invisible until the output is
    /// subtly wrong.
    public enum Polarity: String, Sendable, Codable {
        /// Disparity: large value = near. What `AVDepthData` gives after conversion to
        /// `kCVPixelFormatType_DisparityFloat32`, and what the ControlNet wants. Pass through.
        case disparityNearIsLarge
        /// Metric depth: large value = far. What LiDAR gives in metres. Must be inverted.
        case depthNearIsSmall
    }

    /// Normalise, orient, resize and replicate to three channels.
    ///
    /// - Parameters:
    ///   - values: row-major, `size.pixelCount` elements. Non-finite entries (a LiDAR frame's
    ///     holes are `.infinity`) are treated as missing and take the far value.
    /// - Returns: `PreviewImage` of exactly 512 × 512 RGBA, R == G == B, alpha 255.
    public static func render(values: [Float],
                              size: PixelSize,
                              polarity: Polarity = .disparityNearIsLarge,
                              fit: Fit = .centerCrop) -> PreviewImage? {
        guard !size.isEmpty, values.count == size.pixelCount else { return nil }

        // Range over the FINITE samples only. A single infinite hole would otherwise flatten the
        // entire map to one value, which is a black frame and a redesign with no geometry at all.
        var minimum = Float.greatestFiniteMagnitude
        var maximum = -Float.greatestFiniteMagnitude
        var finiteCount = 0
        for value in values where value.isFinite {
            minimum = Swift.min(minimum, value)
            maximum = Swift.max(maximum, value)
            finiteCount += 1
        }
        guard finiteCount > 0 else { return nil }

        // A constant-depth frame — a wall shot flat on, or a synthetic fixture — has zero range.
        // Dividing by it produces NaN and then a garbage buffer, so it maps to mid grey: "no
        // usable relief", which is true and is what the model should be told.
        let range = maximum - minimum
        let isFlat = range <= .ulpOfOne

        let source = size
        let cropOrigin: (x: Int, y: Int)
        let cropSize: Int
        switch fit {
        case .centerCrop:
            cropSize = Swift.min(source.width, source.height)
            cropOrigin = ((source.width - cropSize) / 2, (source.height - cropSize) / 2)
        case .stretch:
            cropSize = 0                      // unused
            cropOrigin = (0, 0)
        }

        var pixels = [UInt8](repeating: 0, count: edge * edge * 4)

        for row in 0..<edge {
            for column in 0..<edge {
                // Nearest-neighbour. A depth map is piecewise-smooth with hard edges at object
                // boundaries, and those edges are the entire signal — bilinear smearing across
                // them invents a ramp where the model should see a step.
                let sourceX: Int
                let sourceY: Int
                switch fit {
                case .centerCrop:
                    sourceX = cropOrigin.x + column * cropSize / edge
                    sourceY = cropOrigin.y + row * cropSize / edge
                case .stretch:
                    sourceX = column * source.width / edge
                    sourceY = row * source.height / edge
                }
                let clampedX = Swift.min(Swift.max(sourceX, 0), source.width - 1)
                let clampedY = Swift.min(Swift.max(sourceY, 0), source.height - 1)
                let sample = values[clampedY * source.width + clampedX]

                let level: UInt8
                if isFlat {
                    level = 128
                } else if !sample.isFinite {
                    // A hole. Treat it as the far plane: black. Guessing "near" here would put a
                    // phantom object in front of the camera.
                    level = 0
                } else {
                    let normalised = (sample - minimum) / range          // 0 = min, 1 = max
                    let nearness: Float
                    switch polarity {
                    case .disparityNearIsLarge: nearness = normalised
                    case .depthNearIsSmall:     nearness = 1 - normalised
                    }
                    level = UInt8(Swift.min(Swift.max(nearness * 255, 0), 255).rounded())
                }

                let offset = (row * edge + column) * 4
                pixels[offset] = level
                pixels[offset + 1] = level
                pixels[offset + 2] = level
                pixels[offset + 3] = 255
            }
        }

        return PreviewImage(pixels: Data(pixels),
                            size: PixelSize(width: edge, height: edge))
    }
}
