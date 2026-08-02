import Foundation

/// Acoustic interference: speaker-boundary cancellation (SBIR) and two-source comb filtering.
/// Pure, stateless, exact geometry. MODEL CAVEAT: ideal point sources / perfect reflection; real
/// boundaries (finite size, frequency-dependent absorption) soften the notch depths.
public enum Comb {
    public static let speedOfSound = 343.0   // m/s at ~20 °C

    // MARK: Speaker-boundary interference (SBIR)

    /// Boundary cancellation frequencies (Hz) for a source `d` m from a reflecting boundary
    /// (reflected path 2d longer): fₖ = (2k−1)·c/(4d), k = 1…count.
    public static func boundaryNotches(distanceM d: Double, speed c: Double = speedOfSound, count: Int = 4) -> [Double] {
        guard d > 0, count > 0 else { return [] }
        return (1...count).map { Double(2 * $0 - 1) * c / (4 * d) }
    }

    /// First boundary reinforcement (Hz): c/(2d).
    public static func boundaryFirstPeak(distanceM d: Double, speed c: Double = speedOfSound) -> Double {
        guard d > 0 else { return 0 }
        return c / (2 * d)
    }

    /// Largest source-to-boundary distance (m) that keeps the first notch above `targetHz`: c/(4·f).
    public static func distanceForFirstNotchAbove(targetHz f: Double, speed c: Double = speedOfSound) -> Double {
        guard f > 0 else { return 0 }
        return c / (4 * f)
    }

    /// Notch depth (dB, ≤0) when a reflection of gain `reflGainDB` (≤0 dB) sums out of phase:
    /// 20·log₁₀|1 − r|, r = 10^(g/20). Full reflection (0 dB) → −∞.
    public static func nullDepthDB(reflectionGainDB g: Double) -> Double {
        let r = pow(10, g / 20)
        return 20 * log10(abs(1 - r))
    }

    /// Reinforcement gain (dB, ≥0) when the reflection sums in phase: 20·log₁₀(1 + r).
    public static func peakGainDB(reflectionGainDB g: Double) -> Double {
        20 * log10(1 + pow(10, g / 20))
    }

    // MARK: Two coherent sources (comb)

    /// Path-length difference (m) → inter-arrival delay (ms): 1000·Δ/c.
    public static func delayMs(pathDiffM d: Double, speed c: Double = speedOfSound) -> Double { 1000 * d / c }

    /// Delay (ms) → path-length difference (m): c·ms/1000.
    public static func pathFromDelay(ms: Double, speed c: Double = speedOfSound) -> Double { c * ms / 1000 }

    /// Comb notch spacing (Hz) between successive nulls for a path difference Δ: c/Δ = 1/τ.
    public static func combSpacing(pathDiffM d: Double, speed c: Double = speedOfSound) -> Double {
        guard d > 0 else { return 0 }
        return c / d
    }

    /// First comb null (Hz): c/(2Δ).
    public static func combFirstNull(pathDiffM d: Double, speed c: Double = speedOfSound) -> Double {
        guard d > 0 else { return 0 }
        return c / (2 * d)
    }

    /// Comb null frequencies (Hz): (2k−1)·c/(2Δ), k = 1…count.
    public static func combNulls(pathDiffM d: Double, speed c: Double = speedOfSound, count: Int = 4) -> [Double] {
        guard d > 0, count > 0 else { return [] }
        return (1...count).map { Double(2 * $0 - 1) * c / (2 * d) }
    }
}
