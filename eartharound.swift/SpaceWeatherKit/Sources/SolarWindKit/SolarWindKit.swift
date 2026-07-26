import Foundation

/// Solar-wind interpretation: IMF Bt/Bz geoeffectiveness, bulk speed & density,
/// dynamic pressure, the dawn–dusk interplanetary electric field, and coupling flags.
///
/// Convention (GSM): a southward IMF Bz (Bz < 0) reconnects with Earth's field and
/// is the primary storm driver. Pure and deterministic; oracle-tested against the
/// published formulas and worked values.
public enum SolarWind {

    /// One solar-wind sample. Missing components are allowed (feeds drop out).
    public struct Sample: Equatable, Sendable {
        public var bt: Double?      // IMF magnitude, nT
        public var bz: Double?      // GSM north–south component, nT (negative = southward)
        public var speed: Double?   // bulk speed, km/s
        public var density: Double? // proton density, cm⁻³
        public init(bt: Double? = nil, bz: Double? = nil, speed: Double? = nil, density: Double? = nil) {
            self.bt = bt; self.bz = bz; self.speed = speed; self.density = density
        }
    }

    /// Southward IMF is the geoeffective sign.
    public static func isSouthward(bz: Double) -> Bool { bz < 0 }

    /// Solar-wind dynamic pressure in nPa:  P = 1.6726e-6 · n · V²
    /// (n in cm⁻³, V in km/s; the constant is the proton mass in the mixed-unit form).
    public static func dynamicPressure(density n: Double, speed v: Double) -> Double {
        1.6726e-6 * n * v * v
    }

    /// Dawn–dusk interplanetary electric field Ey in mV/m:  Ey = −V · Bz · 1e-3.
    /// Southward Bz (< 0) yields a positive, geoeffective field.
    public static func electricField(speed v: Double, bz: Double) -> Double {
        -v * bz * 1e-3
    }

    /// The geoeffective (southward-only) part of Ey; 0 when the IMF is northward.
    public static func southwardField(speed v: Double, bz: Double) -> Double {
        max(0, electricField(speed: v, bz: bz))
    }

    // MARK: - Coupling flags & level

    public struct Coupling: Equatable, Sendable {
        public let southward: Bool        // Bz < 0
        public let strongSouthward: Bool  // Bz ≤ −10 nT
        public let fastStream: Bool       // V ≥ 500 km/s (high-speed stream)
        public let geoeffective: Bool     // southward IMF while the wind is elevated
    }

    /// Coupling flags from a sample. Absent components read as non-geoeffective.
    public static func coupling(_ s: Sample) -> Coupling {
        let bz = s.bz ?? 0
        let v = s.speed ?? 0
        let south = bz < 0
        let strong = bz <= -10
        let fast = v >= 500
        return Coupling(
            southward: south,
            strongSouthward: strong,
            fastStream: fast,
            geoeffective: south && (strong || fast || v >= 450)
        )
    }

    public enum Level: String, Sendable { case calm, elevated, storming }

    /// Plain-language geoeffectiveness level from Bz and speed.
    public static func level(bz: Double, speed v: Double) -> Level {
        if bz <= -10 && v >= 500 { return .storming }
        if bz < 0 && (v >= 450 || bz <= -5) { return .elevated }
        return .calm
    }

    public static func speedDescription(_ v: Double) -> String {
        switch v {
        case ..<350: return "Slow"
        case ..<500: return "Nominal"
        case ..<700: return "Fast stream"
        default: return "Very fast"
        }
    }
}
