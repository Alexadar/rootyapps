import Foundation

/// Air-column resonance for wind instruments: open/closed pipes and end corrections.
/// Pure, stateless. MODEL CAVEAT: real bores (tone holes, taper, blowing) diverge — estimates only.
public enum Pipes {
    public static let speedOfSound = 343.0

    /// Open-open pipe resonance (Hz): all harmonics, f = n·c/(2L).
    public static func openPipeHz(lengthM L: Double, harmonic n: Int, speed c: Double = speedOfSound) -> Double {
        Double(n) * c / (2 * L)
    }
    /// Closed-open pipe resonance (Hz): odd harmonics only, f = (2n−1)·c/(4L).
    public static func closedPipeHz(lengthM L: Double, harmonic n: Int, speed c: Double = speedOfSound) -> Double {
        Double(2 * n - 1) * c / (4 * L)
    }
    /// End correction (m) added to physical length for an open end.
    /// Unflanged ≈ 0.6133·r (Levine–Schwinger); flanged ≈ 0.8216·r.
    public static func endCorrectionM(radiusM r: Double, flanged: Bool) -> Double {
        (flanged ? 0.8216 : 0.6133) * r
    }
}
