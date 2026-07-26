import Foundation

/// Passive (real-component) filter corner & resonance frequencies. Pure, stateless.
/// Complements the *idealized* Butterworth response with actual R/L/C values.
public enum Passive {
    /// RC low/high-pass corner (−3 dB): f = 1 / (2π·R·C).
    public static func rcCutoffHz(resistanceOhms r: Double, capacitanceFarads c: Double) -> Double {
        (r > 0 && c > 0) ? 1 / (2 * .pi * r * c) : 0
    }
    /// RL corner: f = R / (2π·L).
    public static func rlCutoffHz(resistanceOhms r: Double, inductanceHenries l: Double) -> Double {
        l > 0 ? r / (2 * .pi * l) : 0
    }
    /// LC resonance: f = 1 / (2π·√(L·C)).
    public static func lcResonanceHz(inductanceHenries l: Double, capacitanceFarads c: Double) -> Double {
        (l > 0 && c > 0) ? 1 / (2 * .pi * (l * c).squareRoot()) : 0
    }
}
