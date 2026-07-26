import Foundation

/// Decibel & reference-level conversions. Pure, stateless.
public enum Levels {
    /// Amplitude/voltage ratio → dB (20·log₁₀).
    public static func voltageDB(ratio r: Double) -> Double { r > 0 ? 20 * log10(r) : -.infinity }
    /// Power ratio → dB (10·log₁₀).
    public static func powerDB(ratio r: Double) -> Double { r > 0 ? 10 * log10(r) : -.infinity }
    public static func voltageRatio(db: Double) -> Double { pow(10, db / 20) }
    public static func powerRatio(db: Double) -> Double { pow(10, db / 10) }

    /// 0 dBu reference: √(0.001 W · 600 Ω) = 0.7746 V RMS.
    public static let dBuReferenceVolts = 0.7745966692

    public static func voltsToDBu(_ v: Double) -> Double { v > 0 ? 20 * log10(v / dBuReferenceVolts) : -.infinity }
    public static func dBuToVolts(_ db: Double) -> Double { dBuReferenceVolts * pow(10, db / 20) }
    /// 0 dBV reference = 1 V RMS.
    public static func voltsToDBV(_ v: Double) -> Double { v > 0 ? 20 * log10(v) : -.infinity }
    public static func dBVToVolts(_ db: Double) -> Double { pow(10, db / 20) }
}
