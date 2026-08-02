import Foundation

/// String/luthier math: Mersenne's laws, string tension, and equal-temperament fret placement.
/// Pure, stateless. SI unless noted.
public enum Strings {

    /// Mersenne's law: fundamental frequency of a vibrating string.
    /// f = (1/2L)·√(T/μ)  — T tension (N), L length (m), μ linear density (kg/m).
    public static func frequencyHz(tensionN T: Double, lengthM L: Double, linearDensityKgPerM mu: Double) -> Double {
        (1 / (2 * L)) * (T / mu).squareRoot()
    }

    /// Tension required for a target pitch (inverse of Mersenne's law): T = μ·(2Lf)².
    public static func tensionN(frequencyHz f: Double, lengthM L: Double, linearDensityKgPerM mu: Double) -> Double {
        mu * pow(2 * L * f, 2)
    }

    /// D'Addario imperial tension (lb): T = UW·(2·L·f)² / 386.4, UW = unit weight (lb/in), L scale (in).
    public static func tensionLb(unitWeightLbPerIn uw: Double, scaleIn L: Double, frequencyHz f: Double) -> Double {
        uw * pow(2 * L * f, 2) / 386.4
    }

    /// Distance from the nut to fret n for equal temperament: d = L·(1 − 2^(−n/12)).
    public static func fretDistance(scale L: Double, fret n: Int) -> Double {
        L * (1 - pow(2, -Double(n) / 12))
    }
}
