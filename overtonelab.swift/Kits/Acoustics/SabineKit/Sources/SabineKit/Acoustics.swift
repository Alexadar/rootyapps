import Foundation

/// Room acoustics: reverberation (Sabine/Eyring), Schroeder frequency, axial modes.
/// Pure, stateless. MODEL CAVEAT: real rooms diverge from these idealizations — ship as estimates.
public enum Acoustics {
    public static let speedOfSound = 343.0   // m/s at ~20 °C

    /// Sabine RT60 (s): 0.161·V / A, where A = total absorption (metric sabins, m²) = Σ Sᵢ·αᵢ.
    public static func sabineRT60(volumeM3 V: Double, absorptionSabins A: Double) -> Double { 0.161 * V / A }

    /// Eyring RT60 (s): 0.161·V / (−S·ln(1−ā)). Better for high average absorption.
    public static func eyringRT60(volumeM3 V: Double, surfaceM2 S: Double, avgAbsorption a: Double) -> Double {
        0.161 * V / (-S * log(1 - a))
    }

    /// Schroeder frequency (Hz): above it the room is statistically diffuse. 2000·√(RT60/V).
    public static func schroederHz(rt60: Double, volumeM3 V: Double) -> Double { 2000 * (rt60 / V).squareRoot() }

    /// Axial room mode (Hz) along a dimension L: n·c/(2L).
    public static func axialModeHz(lengthM L: Double, order n: Int, speed c: Double = speedOfSound) -> Double {
        Double(n) * c / (2 * L)
    }
}
