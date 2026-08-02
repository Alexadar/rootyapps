import Testing
import Foundation
@testable import GeomagKit

/// ORACLE = GFZ Potsdam / Bartels definition of the Kp index and its ap conversion,
///          plus the NOAA Space Weather Prediction Center G-scale.
///
///  • Kp↔ap conversion table (the standard 28-step Bartels scale):
///    Kp:  0o 0+ 1- 1o 1+ 2- 2o 2+ 3- 3o 3+ 4- 4o 4+ 5- 5o 5+ 6- 6o 6+ 7- 7o 7+ 8- 8o 8+ 9- 9o
///    ap:   0  2  3  4  5  6  7  9 12 15 18 22 27 32 39 48 56 67 80 94 111 132 154 179 207 236 300 400
///    Source: GFZ German Research Centre for Geosciences — Kp index definition
///            (Bartels 1949; Menvielle & Berthelier 1991), kp.gfz.de.
///  • G-scale: G1=Kp5, G2=Kp6, G3=Kp7, G4=Kp8, G5=Kp9.
///            Source: NOAA SWPC "NOAA Space Weather Scales" (Geomagnetic Storms G).
///  • Daily Ap = mean of the eight three-hourly ap values, rounded. GFZ definition.
@Suite("Geomag oracle — Bartels Kp↔ap + NOAA G-scale")
struct GeomagOracleTests {

    /// The full 28-entry ap table, transcribed independently from the published standard.
    static let oracleAp: [Int] = [
        0, 2, 3, 4, 5, 6, 7, 9, 12, 15,
        18, 22, 27, 32, 39, 48, 56, 67, 80, 94,
        111, 132, 154, 179, 207, 236, 300, 400,
    ]
    static let oracleSymbols: [String] = [
        "0o", "0+", "1-", "1o", "1+", "2-", "2o", "2+", "3-", "3o",
        "3+", "4-", "4o", "4+", "5-", "5o", "5+", "6-", "6o", "6+",
        "7-", "7o", "7+", "8-", "8o", "8+", "9-", "9o",
    ]

    @Test func tableMatchesPublishedStandardExactly() {
        #expect(Geomag.apTable == Self.oracleAp)
        #expect(Geomag.symbols == Self.oracleSymbols)
        #expect(Geomag.apTable.count == 28)
        #expect(Geomag.symbols.count == 28)
    }

    @Test func everyStepConvertsToItsTabulatedAp() {
        for i in 0..<28 {
            let s = Geomag.KpStep(clampingStep: i)
            #expect(s.ap == Self.oracleAp[i], "step \(i) (\(s.symbol)) ap")
            #expect(s.symbol == Self.oracleSymbols[i])
        }
    }

    @Test func stepDecimalValuesAreThirds() {
        #expect(Geomag.KpStep(clampingStep: 0).value == 0.0)   // 0o
        #expect(abs(Geomag.KpStep(clampingStep: 1).value - 1.0/3.0) < 1e-9)  // 0+
        #expect(abs(Geomag.KpStep(clampingStep: 2).value - 2.0/3.0) < 1e-9)  // 1-
        #expect(Geomag.KpStep(clampingStep: 3).value == 1.0)   // 1o
        #expect(Geomag.KpStep(clampingStep: 15).value == 5.0)  // 5o
        #expect(Geomag.KpStep(clampingStep: 27).value == 9.0)  // 9o
    }

    @Test func kpToApWorkedValues() {
        #expect(Geomag.ap(forKp: 0.0) == 0)
        #expect(Geomag.ap(forKp: 1.0) == 4)    // 1o
        #expect(Geomag.ap(forKp: 4.0) == 27)   // 4o
        #expect(Geomag.ap(forKp: 5.0) == 48)   // 5o
        #expect(Geomag.ap(forKp: 7.0) == 132)  // 7o
        #expect(Geomag.ap(forKp: 9.0) == 400)  // 9o
    }

    @Test func apToKpRoundTrips() {
        for i in 0..<28 {
            #expect(Geomag.kpStep(forAp: Self.oracleAp[i]).step == i, "ap \(Self.oracleAp[i])")
        }
    }

    @Test func rawKpSnapsToNearestThird() {
        #expect(Geomag.step(forKp: 5.3).symbol == "5+")   // 5.333 nearest → 5+
        #expect(Geomag.step(forKp: 5.1).symbol == "5o")   // nearest 5.0
        #expect(Geomag.step(forKp: 6.9).symbol == "7o")   // nearest 7.0
    }

    @Test func gScaleMatchesNOAA() {
        #expect(Geomag.gScale(forKp: 4.99) == 0)
        #expect(Geomag.gScale(forKp: 5.0) == 1)   // G1
        #expect(Geomag.gScale(forKp: 5.67) == 1)  // still G1
        #expect(Geomag.gScale(forKp: 6.0) == 2)   // G2
        #expect(Geomag.gScale(forKp: 7.0) == 3)   // G3
        #expect(Geomag.gScale(forKp: 8.0) == 4)   // G4
        #expect(Geomag.gScale(forKp: 9.0) == 5)   // G5
    }

    @Test func dailyApAveraging() {
        // All-quiet day: eight ap=4 (Kp 1o) → Ap 4.
        #expect(Geomag.dailyAp(fromThreeHourlyAp: Array(repeating: 4, count: 8)) == 4)
        // Exact-mean worked example: sum 40 / 8 = 5.
        #expect(Geomag.dailyAp(fromThreeHourlyAp: [0, 2, 4, 6, 7, 9, 12, 0]) == 5)
        // From Kp readings: eight 5o (ap 48) → Ap 48.
        #expect(Geomag.dailyAp(fromThreeHourlyKp: Array(repeating: 5.0, count: 8)) == 48)
        // Wrong cardinality rejected.
        #expect(Geomag.dailyAp(fromThreeHourlyAp: [1, 2, 3]) == nil)
    }
}
