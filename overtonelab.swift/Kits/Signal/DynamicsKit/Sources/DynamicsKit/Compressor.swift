import Foundation

/// Dynamic-range compressor math: the log-domain gain computer (with soft knee) and the
/// attack/release time constants. Pure, stateless. Follows Giannoulis, Massberg & Reiss,
/// "Digital Dynamic Range Compressor Design" (JAES 60(6), 2012).
/// MODEL CAVEAT: static curve + first-order envelope; a real compressor's program-dependent
/// detector, look-ahead and RMS/peak choice diverge.
public enum Compressor {
    /// Gain-computer output yG (dB) for input level `x` (dB). Soft-knee width `W` (dB); W=0 = hard knee.
    public static func computerOutputDB(inputDB x: Double, thresholdDB T: Double, ratio R: Double, kneeDB W: Double) -> Double {
        let d = x - T
        if W > 0, 2 * d > -W, 2 * d < W {                 // within the knee
            return x + (1 / R - 1) * pow(d + W / 2, 2) / (2 * W)
        } else if 2 * d >= W {                             // above threshold (handles W=0)
            return T + d / R
        } else {                                           // below threshold
            return x
        }
    }

    /// Gain reduction (dB, ≥0) applied by the computer, before makeup: x − yG.
    public static func gainReductionDB(inputDB x: Double, thresholdDB T: Double, ratio R: Double, kneeDB W: Double) -> Double {
        x - computerOutputDB(inputDB: x, thresholdDB: T, ratio: R, kneeDB: W)
    }

    /// Output level (dB) after makeup gain: yG + M.
    public static func outputLevelDB(inputDB x: Double, thresholdDB T: Double, ratio R: Double, kneeDB W: Double, makeupDB M: Double) -> Double {
        computerOutputDB(inputDB: x, thresholdDB: T, ratio: R, kneeDB: W) + M
    }

    /// Effective compression ratio at this input level (accounts for the knee): dx/dyG.
    public static func effectiveRatio(inputDB x: Double, thresholdDB T: Double, ratio R: Double, kneeDB W: Double) -> Double {
        let d = x - T
        let slope: Double
        if W > 0, 2 * d > -W, 2 * d < W {
            slope = 1 + (1 / R - 1) * (d + W / 2) / W
        } else if 2 * d >= W {
            slope = 1 / R
        } else {
            slope = 1
        }
        return slope > 0 ? 1 / slope : Double.infinity
    }

    // MARK: Time constants

    /// Time constant τ (ms) for a stated 10 %→90 % rise time `t` (ms): τ = t / ln 9.
    public static func timeConstantMs(riseTimeMs t: Double) -> Double { t / log(9) }

    /// First-order (one-pole) smoothing coefficient for a 10 %→90 % rise time `t` (ms) at `fs` Hz:
    /// α = exp(−1 / (fs·τ)), τ in seconds.
    public static func onePoleCoeff(riseTimeMs t: Double, fs: Double) -> Double {
        let tauS = (t / log(9)) / 1000
        return exp(-1 / (fs * tauS))
    }

    /// Fraction reached (0…1) `afterMs` into a step, for a 10 %→90 % rise time `rt` (ms):
    /// 1 − exp(−t/τ). Equals 63.2 % at one time constant.
    public static func percentReached(afterMs t: Double, riseTimeMs rt: Double) -> Double {
        1 - exp(-t / (rt / log(9)))
    }
}
