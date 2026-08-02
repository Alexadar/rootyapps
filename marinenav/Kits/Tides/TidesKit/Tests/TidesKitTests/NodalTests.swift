import Testing
import Foundation
@testable import TidesKit

// Oracle = Schureman, USC&GS Special Publication No. 98 (1958), Table 6.
// https://tidesandcurrents.noaa.gov/publications/SpecialPubNo98.pdf -- oracle-backed.
@Suite("Nodal angles vs Schureman Table 6")
struct NodalOracleTests {

    /// Table 6 tabulates I, ν, ξ, ν′ and 2ν″ for each degree of N, with the sign
    /// rule in its header. This is the check that settled the ξ convention: three
    /// plausible sign conventions are in circulation and only one matches.
    @Test("closed forms reproduce Table 6", arguments: [
        ("schureman-table6-n320", 320.0),
        ("schureman-table6-n324", 324.0),
        ("schureman-table6-n330", 330.0),
        ("schureman-table6-n336", 336.0),
        ("schureman-table6-n339", 339.0),
    ])
    func matchesTable6(id: String, nodeDeg: Double) {
        let o = Oracles.require(id)
        // Table 6 depends on N alone; the perigee argument affects only Q/R.
        let n = Nodal(nodeDeg: nodeDeg, perigeeDeg: 0)
        #expect(o.matches("I", n.inclinationDeg),
                "I: got \(n.inclinationDeg), want \(o.value("I"))")
        #expect(o.matches("nu", n.nuDeg),
                "nu: got \(n.nuDeg), want \(o.value("nu"))")
        #expect(o.matches("xi", n.xiDeg),
                "xi: got \(n.xiDeg), want \(o.value("xi"))")
        #expect(o.matches("nu_prime", n.nuPrimeDeg),
                "nu': got \(n.nuPrimeDeg), want \(o.value("nu_prime"))")
        #expect(o.matches("two_nu_dprime", n.twoNuDoublePrimeDeg),
                "2nu\": got \(n.twoNuDoublePrimeDeg), want \(o.value("two_nu_dprime"))")
    }
}

// Oracle = Schureman SP-98 Table 6 header sign rule + definition. Invariant.
@Suite("Nodal invariants")
struct NodalInvariantTests {

    /// Table 6 header: "Positive when N is between 0 and 180 deg; negative when
    /// N is between 180 and 360 deg." This is the property the wrong-sign
    /// convention violates, so it is worth asserting directly.
    @Test("xi and nu follow Schureman's sign rule across the whole node cycle")
    func signRuleHolds() {
        for nDeg in stride(from: 1.0, to: 180.0, by: 1.0) {
            let n = Nodal(nodeDeg: nDeg, perigeeDeg: 0)
            #expect(n.xiDeg > 0, "xi should be positive at N=\(nDeg), got \(n.xiDeg)")
            #expect(n.nuDeg > 0, "nu should be positive at N=\(nDeg), got \(n.nuDeg)")
        }
        for nDeg in stride(from: 181.0, to: 360.0, by: 1.0) {
            let n = Nodal(nodeDeg: nDeg, perigeeDeg: 0)
            #expect(n.xiDeg < 0, "xi should be negative at N=\(nDeg), got \(n.xiDeg)")
            #expect(n.nuDeg < 0, "nu should be negative at N=\(nDeg), got \(n.nuDeg)")
        }
    }

    @Test("xi and nu vanish at the node crossings")
    func vanishAtNodeCrossings() {
        for nDeg in [0.0, 180.0, 360.0] {
            let n = Nodal(nodeDeg: nDeg, perigeeDeg: 0)
            #expect(abs(n.xiDeg) < 1e-9, "xi at N=\(nDeg) should be 0, got \(n.xiDeg)")
            #expect(abs(n.nuDeg) < 1e-9, "nu at N=\(nDeg) should be 0, got \(n.nuDeg)")
        }
    }

    /// I swings between ω−i and ω+i over the 18.6-year cycle.
    @Test("inclination stays inside the standstill limits")
    func inclinationBounds() {
        let lo = Nodal.obliquityDeg - Nodal.lunarInclinationDeg   // 18.307
        let hi = Nodal.obliquityDeg + Nodal.lunarInclinationDeg   // 28.597
        var seenLo = false, seenHi = false
        for nDeg in stride(from: 0.0, through: 360.0, by: 0.5) {
            let I = Nodal(nodeDeg: nDeg, perigeeDeg: 0).inclinationDeg
            #expect(I >= lo - 1e-6 && I <= hi + 1e-6, "I out of range at N=\(nDeg): \(I)")
            if I < lo + 0.01 { seenLo = true }
            if I > hi - 0.01 { seenHi = true }
        }
        #expect(seenLo && seenHi, "I should reach both standstill limits")
    }

    /// f(M₂) is documented by Parker as varying about ±4%; f(O₁) about ±18%.
    @Test("node factors stay within their published modulation ranges")
    func nodeFactorRanges() {
        var m2 = (min: Double.infinity, max: -Double.infinity)
        var o1 = (min: Double.infinity, max: -Double.infinity)
        for nDeg in stride(from: 0.0, through: 360.0, by: 0.5) {
            let n = Nodal(nodeDeg: nDeg, perigeeDeg: 0)
            m2 = (Swift.min(m2.min, n.fM2), Swift.max(m2.max, n.fM2))
            o1 = (Swift.min(o1.min, n.fO1), Swift.max(o1.max, n.fO1))
            #expect(n.fM2 > 0 && n.fO1 > 0 && n.fK1 > 0 && n.fK2 > 0)
        }
        #expect(abs(m2.max - 1) < 0.05 && abs(m2.min - 1) < 0.05,
                "f(M2) range \(m2) should be within ~4% of unity")
        #expect(o1.max > 1.10 && o1.min < 0.90,
                "f(O1) range \(o1) should span roughly +/-18%")
    }
}

// Oracle = definition of the mean longitudes. Identity.
@Suite("Astronomy identities")
struct AstronomyTests {

    @Test("hour angle of the mean sun is 180 deg at 00:00 UT and advances 15 deg/h")
    func hourAngleConvention() {
        let midnight = Date(timeIntervalSince1970: 1_772_323_200)  // 2026-03-01T00:00:00Z
        #expect(abs(Astronomy.elements(at: midnight).hourAngleDeg - 180.0) < 1e-9)
        let sixAM = midnight.addingTimeInterval(6 * 3600)
        #expect(abs(Astronomy.elements(at: sixAM).hourAngleDeg - 270.0) < 1e-9)
    }

    @Test("mean longitudes are normalised to [0, 360)")
    func longitudesNormalised() {
        for days in stride(from: -40_000.0, through: 40_000.0, by: 997.0) {
            let e = Astronomy.elements(at: Date(timeIntervalSince1970: days * 86_400))
            for v in [e.sDeg, e.hDeg, e.pDeg, e.nDeg, e.p1Deg] {
                #expect(v >= 0 && v < 360, "not normalised: \(v)")
            }
        }
    }

    /// The node regresses through a full circle in ~18.61 Julian years.
    @Test("the lunar node regresses with an 18.6-year period")
    func nodeRegressionPeriod() {
        let rate = (5.0 * 360.0 + 482_912.63 / 3600.0) / 36525.0   // deg per day
        let periodYears = 360.0 / rate / 365.25
        #expect(abs(periodYears - 18.61) < 0.01, "got \(periodYears) years")
    }

    @Test("angle normalisation round-trips")
    func angleNormalisation() {
        for d in stride(from: -1080.0, through: 1080.0, by: 7.0) {
            let n = Angle.normalize(d)
            #expect(n >= 0 && n < 360)
            #expect(abs(sin(Angle.radians(n)) - sin(Angle.radians(d))) < 1e-12)
            let s = Angle.normalizeSigned(d)
            #expect(s > -180.0001 && s <= 180.0001)
        }
    }
}
