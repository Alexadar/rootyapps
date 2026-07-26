import Foundation

/// Geomagnetic index math: the quantized Kp scale, the Bartels Kp↔ap conversion,
/// NOAA G-scale classification, and daily Ap averaging.
///
/// Pure and deterministic. Live Kp/ap numbers enter from NOAA SWPC / GFZ; every
/// interpretation the app shows comes from here and is oracle-tested against the
/// published definition (see GeomagKitTests).
public enum Geomag {

    // MARK: - The 28-step quantized Kp scale (Bartels)
    //
    // Kp is reported in thirds of an integer. The traditional "-/o/+" notation
    // labels each third: 0o,0+,1-,1o,1+,2-,…,9-,9o. Step i (0…27) has decimal
    // value i/3. There is no 9+ — the scale saturates at 9o.
    public static let symbols: [String] = [
        "0o", "0+", "1-", "1o", "1+", "2-", "2o", "2+", "3-", "3o",
        "3+", "4-", "4o", "4+", "5-", "5o", "5+", "6-", "6o", "6+",
        "7-", "7o", "7+", "8-", "8o", "8+", "9-", "9o",
    ]

    /// Bartels/GFZ Kp→ap lookup, one entry per Kp step (index 0…27).
    /// This is the canonical 28-value table; see GeomagKitTests for the citation.
    public static let apTable: [Int] = [
        0, 2, 3, 4, 5, 6, 7, 9, 12, 15,
        18, 22, 27, 32, 39, 48, 56, 67, 80, 94,
        111, 132, 154, 179, 207, 236, 300, 400,
    ]

    public static let stepCount = 28

    // MARK: - Quantized Kp value

    /// One quantized Kp reading: its step (0…27), decimal value, "-/o/+" symbol, and ap.
    public struct KpStep: Equatable, Sendable {
        public let step: Int
        public init(clampingStep step: Int) { self.step = min(max(step, 0), Geomag.stepCount - 1) }

        /// Decimal Kp, e.g. step 16 → 5.333 (5+).
        public var value: Double { Double(step) / 3.0 }
        public var symbol: String { Geomag.symbols[step] }
        /// Bartels-equivalent ap amplitude for this step.
        public var ap: Int { Geomag.apTable[step] }
        /// NOAA G-scale (0 = below storm level, 1…5).
        public var gScale: Int { Geomag.gScale(forKp: value) }
    }

    /// Snap a raw decimal Kp to its nearest quantized step (Kp is measured in thirds).
    public static func step(forKp kp: Double) -> KpStep {
        KpStep(clampingStep: Int((kp * 3.0).rounded()))
    }

    /// Bartels ap for a raw decimal Kp (via the nearest step).
    public static func ap(forKp kp: Double) -> Int { step(forKp: kp).ap }

    /// Inverse conversion: the Kp step whose tabulated ap is nearest to `ap`.
    public static func kpStep(forAp ap: Int) -> KpStep {
        var best = 0, bestErr = Int.max
        for (i, a) in apTable.enumerated() {
            let e = abs(a - ap)
            if e < bestErr { bestErr = e; best = i }
        }
        return KpStep(clampingStep: best)
    }

    // MARK: - NOAA G-scale
    //
    // Geomagnetic storm scale: G1=Kp5, G2=Kp6, G3=Kp7, G4=Kp8, G5=Kp9.
    // Below Kp5 there is no storm (G0). A Kp reading of 5.0…5.99 is G1, etc.

    public static func gScale(forKp kp: Double) -> Int {
        guard kp >= 5.0 else { return 0 }
        return min(5, Int(kp.rounded(.down)) - 4)
    }

    /// Human label for a G level, NOAA wording.
    public static func gLabel(_ g: Int) -> String {
        switch g {
        case 1: return "G1 Minor"
        case 2: return "G2 Moderate"
        case 3: return "G3 Strong"
        case 4: return "G4 Severe"
        case 5: return "G5 Extreme"
        default: return "Below G1"
        }
    }

    /// Plain-language activity word for a raw Kp (dashboard "what this means" line).
    public static func activity(forKp kp: Double) -> String {
        switch kp {
        case ..<1: return "Quiet"
        case ..<3: return "Unsettled"
        case ..<5: return "Active"
        default: return gLabel(gScale(forKp: kp))
        }
    }

    // MARK: - Daily Ap
    //
    // Ap is the arithmetic mean of the day's eight three-hourly ap amplitudes,
    // rounded to the nearest integer (GFZ definition).

    /// Daily Ap from the eight three-hourly ap values. Returns nil if not exactly 8.
    public static func dailyAp(fromThreeHourlyAp ap: [Int]) -> Int? {
        guard ap.count == 8 else { return nil }
        let mean = Double(ap.reduce(0, +)) / 8.0
        return Int(mean.rounded())
    }

    /// Daily Ap directly from eight three-hourly Kp readings.
    public static func dailyAp(fromThreeHourlyKp kp: [Double]) -> Int? {
        guard kp.count == 8 else { return nil }
        return dailyAp(fromThreeHourlyAp: kp.map { ap(forKp: $0) })
    }
}
