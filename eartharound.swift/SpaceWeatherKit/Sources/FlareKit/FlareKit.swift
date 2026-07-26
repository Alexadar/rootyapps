import Foundation

/// Solar-flare classification from GOES X-ray flux and the NOAA R-scale (radio blackouts).
///
/// The GOES long-band (0.1–0.8 nm) peak flux in W/m² maps to the A/B/C/M/X letter
/// classes on a decade-log scale, with a linear sub-scale within each decade.
/// Pure and deterministic; oracle-tested against the published NOAA/GOES boundaries.
public enum Flare {

    /// A parsed flare class: letter (A/B/C/M/X), sub-scale magnitude, and its "M2.5" label.
    public struct Classification: Equatable, Sendable {
        public let letter: Character
        public let magnitude: Double
        public let label: String
    }

    // Decade floors, W/m² (0.1–0.8 nm band).
    static let floors: [(Character, Double)] = [
        ("X", 1e-4), ("M", 1e-5), ("C", 1e-6), ("B", 1e-7), ("A", 1e-8),
    ]

    /// Classify a peak X-ray flux (W/m²) into its flare class + sub-scale.
    public static func classify(fluxWm2 flux: Double) -> Classification {
        let (letter, floor) = floors.first { flux >= $0.1 } ?? ("A", 1e-8)
        let mag = flux / floor
        return Classification(letter: letter, magnitude: mag, label: format(letter: letter, magnitude: mag))
    }

    static func format(letter: Character, magnitude mag: Double) -> String {
        let num = mag >= 10 ? String(format: "%.0f", mag) : String(format: "%.1f", mag)
        return "\(letter)\(num)"
    }

    /// Parse a NOAA class string ("M1.4", "X20", "C9.9") back to peak flux in W/m².
    /// Returns nil if the string isn't a recognized flare class.
    public static func flux(forClass string: String) -> Double? {
        let s = string.trimmingCharacters(in: .whitespaces).uppercased()
        guard let letter = s.first, let floor = (floors.first { $0.0 == letter }?.1) else { return nil }
        let rest = s.dropFirst()
        let mag: Double
        if rest.isEmpty { mag = 1.0 } else {
            guard let m = Double(rest) else { return nil }  // reject "BANANA" etc.
            mag = m
        }
        return mag * floor
    }

    // MARK: - NOAA R-scale (radio blackouts)
    //
    // R1 Minor = M1 (1e-5), R2 Moderate = M5 (5e-5), R3 Strong = X1 (1e-4),
    // R4 Severe = X10 (1e-3), R5 Extreme = X20 (2e-3). Below M1 → R0.

    public static func rScale(fluxWm2 flux: Double) -> Int {
        switch flux {
        case 2e-3...: return 5
        case 1e-3...: return 4
        case 1e-4...: return 3
        case 5e-5...: return 2
        case 1e-5...: return 1
        default: return 0
        }
    }

    /// R-scale for an already-classified flare label ("X1.0").
    public static func rScale(forClass string: String) -> Int {
        guard let flux = flux(forClass: string) else { return 0 }
        return rScale(fluxWm2: flux)
    }

    public static func rLabel(_ r: Int) -> String {
        switch r {
        case 1: return "R1 Minor"
        case 2: return "R2 Moderate"
        case 3: return "R3 Strong"
        case 4: return "R4 Severe"
        case 5: return "R5 Extreme"
        default: return "Below R1"
        }
    }

    /// NOAA S-scale (solar radiation storm) label. The S level arrives already computed
    /// in NOAA's scales feed, so this is a label only — no flux classifier.
    public static func sLabel(_ s: Int) -> String {
        switch s {
        case 1: return "S1 Minor"
        case 2: return "S2 Moderate"
        case 3: return "S3 Strong"
        case 4: return "S4 Severe"
        case 5: return "S5 Extreme"
        default: return "Below S1"
        }
    }

    /// Plain-language dashboard line for a flare class.
    public static func meaning(forClass string: String) -> String {
        switch string.first {
        case "X": return "Major flare — radio blackouts, possible radiation storm."
        case "M": return "Medium flare — brief radio blackouts on the sunlit side."
        case "C": return "Common flare — few noticeable effects on Earth."
        default:  return "Minor background activity."
        }
    }
}
