import Foundation

/// Sound-pressure-level distance law & source summation. Pure, stateless.
public enum SPL {
    /// SPL (dB) at a new distance under the inverse-square law: L₂ = L₁ − 20·log₁₀(r₂/r₁).
    public static func atDistance(spl1 L: Double, from r1: Double, to r2: Double) -> Double {
        (r1 > 0 && r2 > 0) ? L - 20 * log10(r2 / r1) : L
    }

    /// Combined SPL of incoherent sources: 10·log₁₀(Σ 10^(Lᵢ/10)).
    public static func sumIncoherent(_ levels: [Double]) -> Double {
        levels.isEmpty ? 0 : 10 * log10(levels.reduce(0) { $0 + pow(10, $1 / 10) })
    }

    /// N equal coherent (in-phase) sources add as pressures: L + 20·log₁₀(N).
    public static func sumCoherent(level L: Double, count n: Int) -> Double {
        n > 0 ? L + 20 * log10(Double(n)) : L
    }
}
