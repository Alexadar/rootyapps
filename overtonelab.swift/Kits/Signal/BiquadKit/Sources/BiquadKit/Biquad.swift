import Foundation

/// Digital biquad (2nd-order IIR) coefficient design — Robert Bristow-Johnson's Audio EQ Cookbook.
/// Pure, stateless. Coefficients are a0-normalized (a0 = 1). MODEL CAVEAT: fixed-point/rounding in a
/// real DSP diverge from these ideal Float64 values.
public enum Biquad {
    /// The eight cookbook filter kinds.
    public enum Kind: String, CaseIterable, Sendable {
        case lowpass, highpass, bandpass, notch, allpass, peaking, lowShelf, highShelf
        public var label: String {
            switch self {
            case .lowpass: return "Low-pass";  case .highpass: return "High-pass"
            case .bandpass: return "Band-pass"; case .notch: return "Notch"
            case .allpass: return "All-pass";   case .peaking: return "Peaking EQ"
            case .lowShelf: return "Low shelf"; case .highShelf: return "High shelf"
            }
        }
        /// Whether the `gainDB` argument affects this kind (peaking + shelves only).
        public var usesGain: Bool { self == .peaking || self == .lowShelf || self == .highShelf }
    }

    /// a0-normalized transfer-function coefficients: H(z) = (b0 + b1 z⁻¹ + b2 z⁻²) / (1 + a1 z⁻¹ + a2 z⁻²).
    public struct Coeffs: Sendable, Equatable {
        public let b0, b1, b2, a1, a2: Double
    }

    /// Design a biquad. `fs`, `f0` in Hz; `q` dimensionless; `gainDB` used only for peaking/shelf.
    /// Uses the Q parameterization throughout (α = sin ω₀ / 2Q), including shelves.
    public static func design(_ kind: Kind, fs: Double, f0: Double, q: Double, gainDB: Double = 0) -> Coeffs {
        let w0 = 2 * Double.pi * f0 / fs
        let cw = cos(w0), sw = sin(w0)
        let alpha = sw / (2 * q)
        let A = pow(10, gainDB / 40)              // amplitude, for peaking/shelf
        let sqA = A.squareRoot()

        var b0 = 0.0, b1 = 0.0, b2 = 0.0, a0 = 1.0, a1 = 0.0, a2 = 0.0
        switch kind {
        case .lowpass:
            b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = (1 - cw) / 2
            a0 = 1 + alpha;    a1 = -2 * cw; a2 = 1 - alpha
        case .highpass:
            b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2
            a0 = 1 + alpha;    a1 = -2 * cw;   a2 = 1 - alpha
        case .bandpass:                            // constant 0 dB peak gain
            b0 = alpha;     b1 = 0;       b2 = -alpha
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        case .notch:
            b0 = 1;         b1 = -2 * cw; b2 = 1
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        case .allpass:
            b0 = 1 - alpha; b1 = -2 * cw; b2 = 1 + alpha
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        case .peaking:
            b0 = 1 + alpha * A; b1 = -2 * cw;     b2 = 1 - alpha * A
            a0 = 1 + alpha / A; a1 = -2 * cw;     a2 = 1 - alpha / A
        case .lowShelf:
            b0 =      A * ((A + 1) - (A - 1) * cw + 2 * sqA * alpha)
            b1 =  2 * A * ((A - 1) - (A + 1) * cw)
            b2 =      A * ((A + 1) - (A - 1) * cw - 2 * sqA * alpha)
            a0 =          (A + 1) + (A - 1) * cw + 2 * sqA * alpha
            a1 =     -2 * ((A - 1) + (A + 1) * cw)
            a2 =          (A + 1) + (A - 1) * cw - 2 * sqA * alpha
        case .highShelf:
            b0 =      A * ((A + 1) + (A - 1) * cw + 2 * sqA * alpha)
            b1 = -2 * A * ((A - 1) + (A + 1) * cw)
            b2 =      A * ((A + 1) + (A - 1) * cw - 2 * sqA * alpha)
            a0 =          (A + 1) - (A - 1) * cw + 2 * sqA * alpha
            a1 =      2 * ((A - 1) - (A + 1) * cw)
            a2 =          (A + 1) - (A - 1) * cw - 2 * sqA * alpha
        }
        return Coeffs(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    /// Magnitude response (dB) of the coefficients at frequency `f` (Hz), sample rate `fs`.
    /// |H(e^{jω})| with ω = 2π f/fs, evaluated from the a0-normalized coefficients.
    public static func magnitudeDB(_ c: Coeffs, hz f: Double, fs: Double) -> Double {
        let w = 2 * Double.pi * f / fs
        let cw = cos(w), c2w = cos(2 * w), sw = sin(w), s2w = sin(2 * w)
        let numRe = c.b0 + c.b1 * cw + c.b2 * c2w
        let numIm = -(c.b1 * sw + c.b2 * s2w)
        let denRe = 1 + c.a1 * cw + c.a2 * c2w
        let denIm = -(c.a1 * sw + c.a2 * s2w)
        let mag2 = (numRe * numRe + numIm * numIm) / (denRe * denRe + denIm * denIm)
        return 10 * log10(mag2)
    }
}
