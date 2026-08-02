import Foundation

/// Stereo microphone-array geometry and the Stereo Recording Angle (SRA).
/// Pure, stateless. Polar response, inter-channel level difference (ΔL) and time difference (ΔT)
/// are EXACT first-order geometry. The SRA uses a summing-localization recombination model whose
/// two trading constants are CALIBRATED so the model reproduces the standard near-coincident
/// recording angles (ORTF 96°, NOS 81°, DIN 101°) to under 1°.
/// MODEL CAVEAT: SRA is a psychoacoustic estimate — perceived stereo width is program- and
/// listener-dependent; the exact geometry (ΔL, ΔT, polar) is the hard, testable core.
public enum Stereo {
    public static let speedOfSound = 343.0    // m/s at ~20 °C

    /// Level difference (dB) that fully lateralizes an image. Calibrated to the standard rigs.
    static let levelForFullImageDB = 13.5
    /// Arrival-time difference (ms) that fully lateralizes an image. Calibrated to the standard rigs.
    static let timeForFullImageMs = 0.93

    public enum Pattern: String, CaseIterable, Sendable {
        case omni, subcardioid, cardioid, supercardioid, hypercardioid, figure8
        /// First-order coefficient a in P(θ) = a + (1−a)·cos θ.
        public var coefficient: Double {
            switch self {
            case .omni: return 1.0
            case .subcardioid: return 0.75
            case .cardioid: return 0.5
            case .supercardioid: return 0.366
            case .hypercardioid: return 0.25
            case .figure8: return 0.0
            }
        }
        public var label: String {
            switch self {
            case .omni: return "Omni"
            case .subcardioid: return "Sub-cardioid"
            case .cardioid: return "Cardioid"
            case .supercardioid: return "Super-cardioid"
            case .hypercardioid: return "Hyper-cardioid"
            case .figure8: return "Figure-8"
            }
        }
    }

    /// First-order polar response at off-axis angle θ (degrees): a + (1−a)·cos θ.
    public static func polar(_ p: Pattern, degrees theta: Double) -> Double {
        p.coefficient + (1 - p.coefficient) * cos(theta * .pi / 180)
    }

    /// Inter-channel level difference (dB) for a source `sourceDeg` off-centre, capsules aimed at
    /// ±(micAngle/2): 20·log10(|P(α−φ)| / |P(α+φ)|). Positive = louder toward the source side.
    public static func levelDifferenceDB(sourceDeg alpha: Double, micAngleDeg mic: Double, pattern p: Pattern) -> Double {
        let phi = mic / 2
        return 20 * log10(abs(polar(p, degrees: alpha - phi)) / abs(polar(p, degrees: alpha + phi)))
    }

    /// Inter-channel time difference (µs) for a source `sourceDeg` off-centre, capsule spacing `spacingCm`:
    /// (d/c)·sin α.
    public static func timeDifferenceUs(sourceDeg alpha: Double, spacingCm spacing: Double, speed c: Double = speedOfSound) -> Double {
        (spacing / 100) * sin(alpha * .pi / 180) / c * 1e6
    }

    /// Stereo recording angle (total degrees): twice the source-angle edge at which the combined
    /// normalized level+time cue first reaches a full L/R image. Scans from centre outward, so it is
    /// robust for coincident and figure-8 arrays (where ΔL rises steeply).
    public static func recordingAngleDeg(micAngleDeg mic: Double, spacingCm spacing: Double,
                                         pattern p: Pattern, speed c: Double = speedOfSound) -> Double {
        var alpha = 0.05
        while alpha < 90 {
            // A null in the far capsule (|P|→0) means an infinite ILD: the image is pinned here.
            if abs(polar(p, degrees: alpha + mic / 2)) < 1e-9 { return 2 * alpha }
            let ld = levelDifferenceDB(sourceDeg: alpha, micAngleDeg: mic, pattern: p)
            let tdMs = timeDifferenceUs(sourceDeg: alpha, spacingCm: spacing, speed: c) / 1000
            if ld / levelForFullImageDB + tdMs / timeForFullImageMs >= 1 { return 2 * alpha }
            alpha += 0.05
        }
        return 180
    }

    /// A named standard technique (geometry only; the SRA is computed by the model).
    public struct Preset: Sendable, Equatable {
        public let name: String
        public let pattern: Pattern
        public let micAngleDeg: Double
        public let spacingCm: Double
    }
    public static let presets: [Preset] = [
        Preset(name: "ORTF",     pattern: .cardioid, micAngleDeg: 110, spacingCm: 17),
        Preset(name: "NOS",      pattern: .cardioid, micAngleDeg: 90,  spacingCm: 30),
        Preset(name: "DIN",      pattern: .cardioid, micAngleDeg: 90,  spacingCm: 20),
        Preset(name: "XY 90°",   pattern: .cardioid, micAngleDeg: 90,  spacingCm: 0),
        Preset(name: "Blumlein", pattern: .figure8,  micAngleDeg: 90,  spacingCm: 0),
    ]

    /// Closest standard technique to a given geometry (normalized angle+spacing+pattern distance).
    public static func nearestPreset(micAngleDeg mic: Double, spacingCm spacing: Double, pattern p: Pattern) -> Preset {
        var best = presets[0]
        var bestD = Double.greatestFiniteMagnitude
        for r in presets {
            let d = pow((mic - r.micAngleDeg) / 180, 2)
                  + pow((spacing - r.spacingCm) / 50, 2)
                  + pow(p.coefficient - r.pattern.coefficient, 2)
            if d < bestD { bestD = d; best = r }
        }
        return best
    }
}
