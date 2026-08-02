import Foundation

/// Analog filter / crossover math (Butterworth & Linkwitz-Riley). Pure, stateless.
/// MODEL CAVEAT: ideal transfer functions; real components (tolerance, ESR, Q) diverge.
public enum Filters {
    /// Butterworth magnitude (linear) of order n at frequency ratio r = f/fc:  1/√(1 + r^{2n}).
    public static func butterworthMag(order n: Int, ratio r: Double) -> Double {
        1 / (1 + pow(r, Double(2 * n))).squareRoot()
    }
    /// Butterworth magnitude in dB.
    public static func butterworthDB(order n: Int, ratio r: Double) -> Double {
        20 * log10(butterworthMag(order: n, ratio: r))
    }
    /// Linkwitz-Riley crossover magnitude (dB) — two cascaded Butterworth sections (order 2n).
    /// LR is −6 dB at the crossover (each of two branches), summing flat.
    public static func linkwitzRileyDB(butterworthOrder n: Int, ratio r: Double) -> Double {
        2 * butterworthDB(order: n, ratio: r)
    }
}
