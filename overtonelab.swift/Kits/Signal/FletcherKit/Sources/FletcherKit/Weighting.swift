import Foundation

/// Frequency-weighting curves (IEC 61672). A/C/Z weighting in dB. Pure, stateless.
public enum Weighting {
    /// A-weighting (dB) at frequency f (Hz). Normalised to 0 dB at 1 kHz.
    public static func aWeightingDB(_ f: Double) -> Double {
        let f2 = f * f
        let ra = pow(12194, 2) * pow(f, 4)
            / ((f2 + pow(20.6, 2)) * (f2 + pow(12194, 2))
               * ((f2 + pow(107.7, 2)) * (f2 + pow(737.9, 2))).squareRoot())
        return 20 * log10(ra) + 2.00
    }
    /// C-weighting (dB) at frequency f (Hz).
    public static func cWeightingDB(_ f: Double) -> Double {
        let f2 = f * f
        let rc = pow(12194, 2) * f2 / ((f2 + pow(20.6, 2)) * (f2 + pow(12194, 2)))
        return 20 * log10(rc) + 0.06
    }
    /// Z-weighting (flat).
    public static func zWeightingDB(_ f: Double) -> Double { 0 }
}
