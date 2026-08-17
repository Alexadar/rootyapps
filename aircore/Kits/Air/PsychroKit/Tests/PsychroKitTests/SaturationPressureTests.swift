import Testing
import Foundation
@testable import PsychroKit

@Suite("Saturation pressure — Hyland–Wexler against IAPWS-95")
struct SaturationPressureTests {

    @Test("Over liquid water, 0…100 °C", arguments: Reference.saturationOverWater)
    func overWater(_ point: Reference.SaturationPoint) throws {
        let computed = try Psychrometrics.saturationPressure(dryBulb: point.t)
        #expect(relativeError(computed, point.pws) < Reference.Tolerance.saturationPressureRelative,
                "at \(point.t) °C: \(computed) Pa vs IAPWS-95 \(point.pws) Pa")
    }

    /// Two independent published anchors, both to four figures.
    @Test func publishedAnchors() throws {
        // The triple point of water, 611.657 Pa at 0.01 °C (IAPWS).
        #expect(abs(try Psychrometrics.saturationPressure(dryBulb: 0.01) - 611.657) < 0.05)
        // The normal boiling point: saturation pressure reaches one standard atmosphere at 100 °C.
        #expect(relativeError(try Psychrometrics.saturationPressure(dryBulb: 100), 101_325) < 1e-3)
    }

    /// The ice branch is a *different equation*, and the app reaches it every winter. Below 0 °C
    /// this is the sublimation pressure over ice, not an extrapolation of the water curve —
    /// extrapolating the water form is exactly the bug the scaffold shipped (+19 % at −18 °C).
    /// The ice branch is a *different equation*, and the app reaches it every winter. Below 0 °C
    /// this is the sublimation pressure over ice, not an extrapolation of the water curve —
    /// extrapolating the water form is exactly the bug the scaffold shipped.
    @Test func iceBranchMatchesPublishedSublimationPressures() throws {
        // Published saturation pressure over ice (ASHRAE Fundamentals Ch. 1 Table 3).
        #expect(abs(try Psychrometrics.saturationPressure(dryBulb: -10) - 259.90) < 0.15)
        #expect(abs(try Psychrometrics.saturationPressure(dryBulb: -20) - 103.26) < 0.10)
        #expect(abs(try Psychrometrics.saturationPressure(dryBulb: -30) - 38.02) < 0.05)
    }

    /// Guards the specific defect: a Magnus-over-water form extrapolated below freezing runs
    /// 19 % high at 0 °F, and the resulting dew point is wrong by 1.5 °F on screen.
    @Test func waterFormExtrapolatedBelowFreezingIsFarOff() throws {
        let t = -17.7777777778                    // 0 °F
        let ice = try Psychrometrics.saturationPressure(dryBulb: t)
        let magnusOverWater = 611.2 * exp(17.62 * t / (243.12 + t))
        #expect(abs(ice - 127.569) < 0.05)
        #expect(relativeError(magnusOverWater, ice) > 0.15,
                "the two must differ by more than 15 % — that gap is the defect being guarded")
    }

    /// The correlation's own step at the branch change: under 0.01 %, and it must stay that small.
    @Test func branchesMeetAtFreezing() throws {
        let water = try Psychrometrics.saturationPressure(dryBulb: 0)
        let justBelow = try Psychrometrics.saturationPressure(dryBulb: -1e-9)
        #expect(relativeError(justBelow, water) < 1e-4)
        #expect(abs(water - 611.213) < 0.01)
    }

    @Test func inverseRoundTripsAcrossBothBranches() throws {
        for t in stride(from: -60.0, through: 90.0, by: 3.0) {
            let p = try Psychrometrics.saturationPressure(dryBulb: t)
            let back = try Psychrometrics.saturationTemperature(pressure: p)
            #expect(abs(back - t) < 1e-6, "round trip at \(t) °C returned \(back)")
        }
    }

    @Test func rejectsTemperaturesOutsideThePublishedRange() {
        #expect(throws: PsychroError.temperatureOutOfRange(250)) {
            try Psychrometrics.saturationPressure(dryBulb: 250)
        }
        #expect(throws: PsychroError.temperatureOutOfRange(-150)) {
            try Psychrometrics.saturationPressure(dryBulb: -150)
        }
        #expect(throws: (any Error).self) {
            try Psychrometrics.saturationPressure(dryBulb: .nan)
        }
    }
}
