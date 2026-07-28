import Testing
import Foundation
@testable import GeodesyKit

@Suite("Oracle corpus integrity")
struct GuardTests {
    @Test func hasSources() {
        for o in Oracles.all { #expect(!o.source.isEmpty); #expect(!o.values.isEmpty)
            for k in o.values.keys { #expect(o.tolerances[k] != nil) } }
    }
    @Test func idsUnique() { #expect(Set(Oracles.all.map(\.id)).count == Oracles.all.count) }
}

// Oracle = Vincenty 1975 worked line + Karney GeodTest multiprecision rows.  oracle-backed
@Suite("Vincenty inverse vs published geodesics")
struct VincentyOracleTests {
    @Test func flindersBuninyong() {
        let o = Oracles.require("vincenty_flinders_buninyong")
        let r = Vincenty.inverse(lat1: -(37.0 + 57.0/60 + 3.72030/3600),
                                 lon1: 144.0 + 25.0/60 + 29.52440/3600,
                                 lat2: -(37.0 + 39.0/60 + 10.15610/3600),
                                 lon2: 143.0 + 55.0/60 + 35.38390/3600)
        #expect(r.converged)
        #expect(o.matches("distance_m", r.distanceM), "s=\(r.distanceM)")
        #expect(o.matches("azi1_deg", r.azimuth1Deg), "azi1=\(r.azimuth1Deg)")
        #expect(o.matches("azi2_deg", r.azimuth2Deg), "azi2=\(r.azimuth2Deg)")
    }
    @Test(arguments: Oracles.geodTestRows.map(\.id))
    func geodTestRow(id: String) {
        let row = Oracles.geodTestRows.first { $0.id == id }!
        let o = Oracles.require(id)
        let r = Vincenty.inverse(lat1: row.lat1, lon1: 0, lat2: row.lat2, lon2: row.lon2)
        #expect(r.converged, "non-convergent \(id)")
        #expect(o.matches("distance_m", r.distanceM), "s=\(r.distanceM) vs \(row.s12)")
        #expect(o.matches("azi1_deg", r.azimuth1Deg), "azi1=\(r.azimuth1Deg) vs \(row.azi1)")
        #expect(o.matches("azi2_deg", r.azimuth2Deg), "azi2=\(r.azimuth2Deg) vs \(row.azi2)")
    }
}

// Oracle = ellipsoid geometry identities (WGS84 quarter-meridian, equatorial arc, symmetry).
// identity | invariant.  Scoped claim: near-antipodal non-convergence is reported, not hidden.
@Suite("Vincenty identities")
struct VincentyIdentityTests {
    @Test func equatorEastQuarter() {
        // Along the equator 0°→90°E: distance = a·π/2, azimuth due east (90°).
        let r = Vincenty.inverse(lat1: 0, lon1: 0, lat2: 0, lon2: 90)
        #expect(r.converged)
        #expect(abs(r.distanceM - Vincenty.a * .pi / 2) < 1.0)     // within 1 m
        #expect(abs(r.azimuth1Deg - 90) < 1e-6)
    }
    @Test func quarterMeridian() {
        // 0°N→90°N on a meridian: WGS84 quarter-meridian ≈ 10,001,965.7 m.
        let r = Vincenty.inverse(lat1: 0, lon1: 0, lat2: 90, lon2: 0)
        #expect(r.converged)
        #expect(abs(r.distanceM - 10_001_965.7) < 100.0)
    }
    @Test func distanceSymmetric() {
        let ab = Vincenty.inverse(lat1: 51.5, lon1: -0.13, lat2: 40.71, lon2: -74.0)   // London→NYC
        let ba = Vincenty.inverse(lat1: 40.71, lon1: -74.0, lat2: 51.5, lon2: -0.13)
        #expect(ab.converged && ba.converged)
        #expect(abs(ab.distanceM - ba.distanceM) < 1e-6)
        #expect(abs(ab.distanceM - 5_570_000) < 20_000)   // ~5,570 km sanity
    }
}
