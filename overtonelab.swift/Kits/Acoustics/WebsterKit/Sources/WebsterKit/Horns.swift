import Foundation

/// Horn / waveguide / Helmholtz math (Webster horn equation family). Pure, stateless.
/// MODEL CAVEAT: 1-D Webster theory; cross-check real designs against Hornresp.
public enum Horns {
    public static let speedOfSound = 343.0

    /// Exponential-horn cutoff frequency (Hz): fc = c·m / (4π), m = flare constant (1/m).
    /// Below fc the horn does not load / radiate efficiently.
    public static func expHornCutoffHz(flareConstant m: Double, speed c: Double = speedOfSound) -> Double {
        c * m / (4 * .pi)
    }

    /// Exponential-horn area at distance x: A(x) = A0·e^{m·x}.
    public static func expHornArea(mouthOrThroatA0 A0: Double, flareConstant m: Double, x: Double) -> Double {
        A0 * exp(m * x)
    }

    /// Helmholtz resonator frequency (Hz): f = (c/2π)·√(A / (V·L_eff)).
    public static func helmholtzHz(neckAreaM2 A: Double, cavityVolumeM3 V: Double, neckLengthM L: Double,
                                   speed c: Double = speedOfSound) -> Double {
        (c / (2 * .pi)) * (A / (V * L)).squareRoot()
    }
}
