import Testing
import Foundation
@testable import CelestialNavKit

private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0) -> Date {
    var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(from: c)!
}

@Suite("Oracle corpus integrity")
struct OracleGuardTests {
    @Test func everyOracleHasSource() {
        for o in Oracles.all {
            #expect(!o.source.isEmpty); #expect(!o.values.isEmpty)
            for k in o.values.keys { #expect(o.tolerances[k] != nil) }
        }
    }
    @Test func idsUnique() { #expect(Set(Oracles.all.map(\.id)).count == Oracles.all.count) }
}

// ORACLE-BACKED almanac core (the ephemeris behind GHA/Dec).
@Suite("Almanac vs Meeus oracles")
struct AlmanacTests {
    @Test func sunEquatorial() {
        let o = Oracles.require("meeus-25b-sun")
        let p = SkyMath.sunPosition(utc(1992, 10, 13))
        #expect(o.matches("rightAscension", p.rightAscension), "RA=\(p.rightAscension)")
        #expect(o.matches("declination", p.declination))
    }
    @Test func moonEcliptic() {
        let o = Oracles.require("meeus-47a-moon")
        let p = SkyMath.moonPosition(utc(1992, 4, 12))
        #expect(o.matches("eclipticLongitude", p.eclipticLongitude))
        #expect(o.matches("eclipticLatitude", p.eclipticLatitude))
    }
    @Test func ghaInRange() {
        let g = Navigation.ghaDec(.sun, at: utc(1992, 10, 13, 12))
        #expect(g.gha >= 0 && g.gha < 360)
    }
}

// IDENTITY: sight-reduction spherical trig.
@Suite("Sight reduction — trig identities")
struct ReductionTests {
    @Test func bodyOverheadGivesNinety() {
        // Assumed position directly under the body: lat = dec, LHA = 0 (gha + lonE = 0) → Hc = 90°.
        let r = Navigation.reduce(observedHo: 90, gha: 0, dec: 30, assumedLat: 30, assumedLonEast: 0)
        #expect(abs(r.computedAltitudeHc - 90) < 1e-6)
    }
    @Test func bodyOnHorizonDueWest() {
        // dec 0, lat 0, LHA 90° → Hc 0°, azimuth due west (270°).
        let r = Navigation.reduce(observedHo: 0, gha: 90, dec: 0, assumedLat: 0, assumedLonEast: 0)
        #expect(abs(r.computedAltitudeHc) < 1e-6)
        #expect(abs(r.azimuthZn - 270) < 1e-6)
    }
    @Test func interceptSignAndMagnitude() {
        // Non-degenerate geometry; first find Hc, then feed Ho = Hc and Ho = Hc + 0.5°.
        let hc = Navigation.reduce(observedHo: 0, gha: 30, dec: 10, assumedLat: 25, assumedLonEast: 0).computedAltitudeHc
        let atHc = Navigation.reduce(observedHo: hc, gha: 30, dec: 10, assumedLat: 25, assumedLonEast: 0)
        let above = Navigation.reduce(observedHo: hc + 0.5, gha: 30, dec: 10, assumedLat: 25, assumedLonEast: 0)
        #expect(abs(atHc.interceptNM) < 1e-6)          // Ho == Hc ⇒ zero intercept
        #expect(abs(above.interceptNM - 30) < 1e-6)    // 0.5° ⇒ 30 nm "toward"
    }
}

// EDGE/DOMAIN: longitude sign & hour-angle wrap.
@Suite("Edge cases — conventions")
struct EdgeTests {
    @Test func lhaWrapsWithEastLongitude() {
        // gha 350°, assumed lon +20°E ⇒ LHA 10°. Verify via a reduction whose Hc depends on LHA.
        let a = Navigation.reduce(observedHo: 0, gha: 350, dec: 0, assumedLat: 0, assumedLonEast: 20)
        let b = Navigation.reduce(observedHo: 0, gha: 10, dec: 0, assumedLat: 0, assumedLonEast: 0)
        #expect(abs(a.computedAltitudeHc - b.computedAltitudeHc) < 1e-9)
        #expect(abs(a.azimuthZn - b.azimuthZn) < 1e-9)
    }
    @Test func dipAndRefractionPositive() {
        #expect(Navigation.dipArcmin(heightOfEyeMetres: 4) > 0)
        #expect(Navigation.refractionArcmin(apparentAltitudeDeg: 10) > 0)
        #expect(Navigation.refractionArcmin(apparentAltitudeDeg: 80) < Navigation.refractionArcmin(apparentAltitudeDeg: 10))
    }
    @Test func observedAltitudeLimbSign() {
        let lower = Navigation.observedAltitude(sextantHs: 45, indexErrorArcmin: 0, heightOfEyeMetres: 0, semiDiameterArcmin: 16, lowerLimb: true)
        let upper = Navigation.observedAltitude(sextantHs: 45, indexErrorArcmin: 0, heightOfEyeMetres: 0, semiDiameterArcmin: 16, lowerLimb: false)
        #expect(lower > upper)   // lower-limb adds SD, upper-limb subtracts
    }
}
