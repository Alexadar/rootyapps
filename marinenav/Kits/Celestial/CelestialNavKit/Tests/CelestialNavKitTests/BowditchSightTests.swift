import Testing
import Foundation
@testable import CelestialNavKit

// Oracle = Bowditch, American Practical Navigator, NGA Pub. No. 9 (2024), Vol. 2,
// Chapter 8 Section 805 -- a complete published worked sight. U.S. Government work,
// public domain. oracle-backed.
//
// This closes the TODO(oracle) that stood open through two earlier scaffold passes:
// the sight-reduction pipeline had only trig identities behind it, never a real
// published sight. Each stage is asserted separately, so an error that cancels
// between two stages cannot hide.
@Suite("Bowditch Section 805 worked sight")
struct BowditchWorkedSightTests {

    private var oracle: Oracle { Oracles.require("bowditch-805-kochab") }

    // Published inputs, transcribed from the example.
    private let hs = dm(34, 54.6)            // sextant altitude
    private let heightOfEyeFeet = 40.0
    private let indexCorrection = Navigation.IndexCorrection.offTheArc(arcmin: 2.0)
    private let gha = dm(153, 47.9)
    private let dec = dm(74, 3.4)
    private let assumedLat = 36.0
    private let assumedLonWest = dm(66, 47.9)

    @Test("dip for a 40 ft height of eye matches the published D")
    func dip() {
        #expect(oracle.matches("dip_arcmin",
                               Navigation.dipArcmin(heightOfEyeFeet: heightOfEyeFeet)),
                "dip = \(Navigation.dipArcmin(heightOfEyeFeet: heightOfEyeFeet))'")
    }

    @Test("apparent altitude ha matches the published value")
    func apparentAltitude() {
        let ha = Navigation.apparentAltitude(sextantHs: hs, indexCorrection: indexCorrection,
                                             heightOfEyeFeet: heightOfEyeFeet)
        #expect(oracle.matches("ha_deg", ha), "ha = \(ha) deg")
    }

    @Test("refraction at ha matches the published St-P correction")
    func refraction() {
        let ha = oracle.values["ha_deg"]!
        let r = Navigation.refractionArcmin(apparentAltitudeDeg: ha)
        #expect(oracle.matches("refraction_arcmin", r), "refraction = \(r)'")
    }

    @Test("observed altitude Ho matches the published value")
    func observedAltitude() {
        let ho = Navigation.observedAltitude(sextantHs: hs, indexCorrection: indexCorrection,
                                             heightOfEyeFeet: heightOfEyeFeet)
        #expect(oracle.matches("ho_deg", ho), "Ho = \(ho) deg")
    }

    /// The Kit carries full precision; the almanac rounds dip and refraction to
    /// 0.1' before applying them. Rounding the same way must reproduce the printed
    /// value **exactly** — which shows the residual above is the almanac's own
    /// rounding and not an error in our formulas.
    @Test("rounding the way the almanac does reproduces the printed values exactly")
    func almanacRoundedChainIsExact() {
        func round01(_ arcmin: Double) -> Double { (arcmin * 10).rounded() / 10 }

        let dipRounded = round01(Navigation.dipArcmin(heightOfEyeFeet: heightOfEyeFeet))
        let ha = hs + indexCorrection.correctionArcmin / 60 - dipRounded / 60
        #expect(abs(ha - oracle.values["ha_deg"]!) * 60 < 0.01,
                "ha = \(ha) deg, off by \(abs(ha - oracle.values["ha_deg"]!) * 60)'")

        let refractionRounded = round01(Navigation.refractionArcmin(apparentAltitudeDeg: ha))
        let ho = ha - refractionRounded / 60
        #expect(abs(ho - oracle.values["ho_deg"]!) * 60 < 0.01,
                "Ho = \(ho) deg, off by \(abs(ho - oracle.values["ho_deg"]!) * 60)'")
    }

    /// LHA = GHA + east longitude. The assumed position is west, so the sign
    /// convention is exercised here rather than assumed.
    @Test("LHA from GHA and the assumed longitude matches the published value")
    func localHourAngle() {
        let lha = Deg.norm360(gha + (-assumedLonWest))
        #expect(oracle.matches("lha_deg", lha), "LHA = \(lha) deg")
    }

    @Test("Hc, Zn and the intercept match the published solution")
    func reduction() {
        let ho = oracle.values["ho_deg"]!
        let r = Navigation.reduce(observedHo: ho, gha: gha, dec: dec,
                                  assumedLat: assumedLat, assumedLonEast: -assumedLonWest)
        #expect(oracle.matches("hc_deg", r.computedAltitudeHc),
                "Hc = \(r.computedAltitudeHc) deg")
        #expect(oracle.matches("zn_deg", r.azimuthZn), "Zn = \(r.azimuthZn) deg")
        #expect(oracle.matches("intercept_nm", r.interceptNM),
                "intercept = \(r.interceptNM) nm")
    }

    /// "Computed Greater Away" — Bowditch's own mnemonic. Hc (35deg13.6') exceeds
    /// Ho (34deg49.1'), so the line of position is AWAY from the body.
    @Test("the intercept is labelled away, per Computed Greater Away")
    func interceptDirection() {
        let ho = oracle.values["ho_deg"]!
        let r = Navigation.reduce(observedHo: ho, gha: gha, dec: dec,
                                  assumedLat: assumedLat, assumedLonEast: -assumedLonWest)
        #expect(r.computedAltitudeHc > ho, "this sight should be Computed Greater")
        #expect(r.interceptNM < 0, "Computed Greater must give an AWAY intercept")
    }
}

// Oracle = the almanac sign conventions themselves. Identity/invariant.
// These are the conventions that fail silently, so each is asserted directly.
@Suite("Sextant sign conventions")
struct SextantConventionTests {

    /// Off the arc means the sextant reads low, so the correction is ADDED and the
    /// index error is negative. Getting this backwards moves a fix by twice the
    /// index error, and nothing else in the pipeline would complain.
    @Test("index correction and index error are opposite in sign")
    func indexSignConvention() {
        let off = Navigation.IndexCorrection.offTheArc(arcmin: 2.0)
        #expect(off.correctionArcmin == 2.0)
        #expect(off.errorArcmin == -2.0)

        let on = Navigation.IndexCorrection.onTheArc(arcmin: 2.0)
        #expect(on.correctionArcmin == -2.0)
        #expect(on.errorArcmin == 2.0)

        #expect(Navigation.IndexCorrection.none.correctionArcmin == 0)

        // Off the arc raises the altitude; on the arc lowers it. Compared on the
        // APPARENT altitude, where the correction enters linearly -- Ho also picks
        // up the refraction difference between the two altitudes.
        let base = Navigation.apparentAltitude(sextantHs: 40, indexCorrection: .none,
                                               heightOfEyeFeet: 0)
        let raised = Navigation.apparentAltitude(sextantHs: 40, indexCorrection: off,
                                                 heightOfEyeFeet: 0)
        let lowered = Navigation.apparentAltitude(sextantHs: 40, indexCorrection: on,
                                                  heightOfEyeFeet: 0)
        #expect(raised > base && base > lowered)
        #expect(abs((raised - lowered) - 4.0 / 60) < 1e-12, "should differ by 2x the index error")

        // The ordering still holds after refraction, just not the exact spacing.
        let hoRaised = Navigation.observedAltitude(sextantHs: 40, indexCorrection: off,
                                                   heightOfEyeFeet: 0)
        let hoLowered = Navigation.observedAltitude(sextantHs: 40, indexCorrection: on,
                                                    heightOfEyeFeet: 0)
        #expect(hoRaised > hoLowered)
    }

    /// The magnitude is taken as given regardless of how the caller signs it —
    /// `.offTheArc(arcmin: -2)` still means off the arc.
    @Test("the case names carry the sign, not the magnitude")
    func magnitudeSignIsIgnored() {
        #expect(Navigation.IndexCorrection.offTheArc(arcmin: -2).correctionArcmin == 2.0)
        #expect(Navigation.IndexCorrection.onTheArc(arcmin: -2).correctionArcmin == -2.0)
    }

    @Test("the feet and metres dip formulas agree")
    func dipUnitsAgree() {
        for feet in stride(from: 0.0, through: 120.0, by: 7.0) {
            let a = Navigation.dipArcmin(heightOfEyeFeet: feet)
            let b = Navigation.dipArcmin(heightOfEyeMetres: feet * 0.3048)
            #expect(abs(a - b) < 1e-12)
        }
        #expect(Navigation.dipArcmin(heightOfEyeFeet: 0) == 0)
    }

    /// Dip grows with height of eye, refraction shrinks with altitude.
    @Test("dip and refraction are monotonic in the right direction")
    func monotonicity() {
        var previousDip = -1.0
        for feet in stride(from: 0.0, through: 200.0, by: 10.0) {
            let d = Navigation.dipArcmin(heightOfEyeFeet: feet)
            #expect(d > previousDip); previousDip = d
        }
        var previousRefraction = Double.infinity
        for alt in stride(from: 1.0, through: 89.0, by: 4.0) {
            let r = Navigation.refractionArcmin(apparentAltitudeDeg: alt)
            #expect(r < previousRefraction); previousRefraction = r
            #expect(r > 0)
        }
        // Refraction is ~34' at the horizon and under 1' above 45 degrees.
        #expect(Navigation.refractionArcmin(apparentAltitudeDeg: 0) > 30)
        #expect(Navigation.refractionArcmin(apparentAltitudeDeg: 45) < 1.1)
    }

    @Test("degrees-and-minutes conversion handles both signs")
    func degreeMinuteHelper() {
        #expect(abs(dm(34, 54.6) - 34.91) < 1e-12)
        #expect(abs(dm(-34, 54.6) - (-34.91)) < 1e-12)
        #expect(dm(0, 30) == 0.5)
    }
}

// Oracle = Bowditch Section 805 published LHA + the LHA definition. oracle-backed | invariant.
@Suite("Local hour angle")
struct LocalHourAngleTests {

    @Test("LHA at the published assumed position matches Bowditch")
    func matchesBowditch() {
        let o = Oracles.require("bowditch-805-kochab")
        let lha = Navigation.localHourAngle(gha: dm(153, 47.9),
                                            assumedLonEast: -dm(66, 47.9))
        #expect(o.matches("lha_deg", lha), "LHA = \(lha) deg")
    }

    /// East longitude wraps past 360 — the trap this helper exists to contain.
    @Test("LHA wraps in east longitude")
    func wrapsInEastLongitude() {
        #expect(abs(Navigation.localHourAngle(gha: 350, assumedLonEast: 20) - 10) < 1e-9)
        #expect(abs(Navigation.localHourAngle(gha: 10, assumedLonEast: -30) - 340) < 1e-9)
        for g in stride(from: 0.0, to: 360.0, by: 23.0) {
            for lon in stride(from: -180.0, through: 180.0, by: 37.0) {
                let lha = Navigation.localHourAngle(gha: g, assumedLonEast: lon)
                #expect(lha >= 0 && lha < 360, "LHA out of range: \(lha)")
            }
        }
    }
}
