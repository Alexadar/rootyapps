import Foundation

/// The output size of a generation, in **pixels**.
///
/// Deliberately not a ratio. A diffusion pipeline is handed a width and a height, not a fraction:
/// 9:19.5 tells it nothing, 1206 × 2622 tells it everything. Storing pixels also means a wallpaper
/// made on a Mac and synced to a phone still knows what it actually is.
///
/// **Latent-space constraint.** Stable-Diffusion-family models work in a latent grid downsampled by
/// 8, so both dimensions must be multiples of 8 or the VAE cannot decode them. Every initialiser
/// enforces that, which is why `AspectRatio(width:height:)` can change the numbers you passed in.
public struct AspectRatio: Hashable, Sendable, Codable {
    public let width: Int
    public let height: Int

    /// The multiple both dimensions are snapped to. 8 is the VAE downsampling factor.
    public static let latentGranularity = 8
    /// The largest edge any generation may have. Beyond this the memory cost stops being sane on a
    /// phone, and no display needs more.
    public static let maximumEdge = 5120
    /// Below this a "wallpaper" is not one.
    public static let minimumEdge = 256

    /// Snaps to the latent grid and clamps to the supported range. Never traps: an absurd request
    /// yields the nearest sane size rather than crashing a generation the user asked for.
    public init(width: Int, height: Int) {
        self.width = Self.snap(width)
        self.height = Self.snap(height)
    }

    private static func snap(_ value: Int) -> Int {
        let clamped = min(max(value, minimumEdge), maximumEdge)
        let rounded = Int((Double(clamped) / Double(latentGranularity)).rounded()) * latentGranularity
        return min(max(rounded, minimumEdge), maximumEdge)
    }

    // MARK: Presets

    /// iPhone portrait — the default case, and the only one the phone offers.
    public static let phone = AspectRatio(width: 1206, height: 2622)
    /// iPad, 4:3 landscape — the bundle's iPad default.
    public static let pad = AspectRatio(width: 2048, height: 1536)
    /// Desktop widescreen, 16:9.
    public static let wide = AspectRatio(width: 3840, height: 2160)

    /// The three the user can choose between on iPad and Mac, in the bundle's order.
    public static let offered: [AspectRatio] = [.pad, .phone, .wide]

    // MARK: Derived

    public var pixelCount: Int { width * height }
    public var ratio: Double { Double(width) / Double(height) }
    public var isPortrait: Bool { height > width }

    /// "2048 × 1536". Tabular numerals are the caller's business; the separator is a real
    /// multiplication sign, not the letter x.
    public var pixelDescription: String { "\(width) × \(height)" }

    /// The name the UI shows in the aspect chip and the Mac size picker.
    public var displayName: String {
        switch self {
        case .phone: return "Phone"
        case .pad:   return "iPad"
        case .wide:  return "Wide"
        default:     return pixelDescription
        }
    }

    /// The generation size for a physical display, snapped to the latent grid and clamped.
    ///
    /// Used by the Mac, where "this display" is the honest default — a 5K iMac and a 13" laptop
    /// want genuinely different pictures, not the same one scaled.
    public static func fittingDisplay(width: Int, height: Int) -> AspectRatio {
        let longest = max(width, height)
        guard longest > maximumEdge else { return AspectRatio(width: width, height: height) }
        let scale = Double(maximumEdge) / Double(longest)
        return AspectRatio(width: Int((Double(width) * scale).rounded()),
                           height: Int((Double(height) * scale).rounded()))
    }
}
