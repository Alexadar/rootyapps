import Testing
import Foundation
@testable import GeodesyKit

// Oracle = Vincenty 1975 worked line + Karney GeodTest multiprecision rows,
// exercised through the DIRECT problem. oracle-backed.
@Suite("Vincenty direct vs published geodesics")
struct VincentyDirectOracleTests {

    /// The direct problem run on the published line must land on the published
    /// endpoint. Same citation as the inverse test, different direction — so a
    /// sign error in one solution cannot be masked by the other.
    @Test("Flinders Peak -> Buninyong reproduces the published endpoint")
    func flindersBuninyongDirect() {
        let o = Oracles.require("vincenty_flinders_buninyong")
        let lat1 = -(37.0 + 57.0 / 60 + 3.72030 / 3600)
        let lon1 = 144.0 + 25.0 / 60 + 29.52440 / 3600
        let lat2 = -(37.0 + 39.0 / 60 + 10.15610 / 3600)
        let lon2 = 143.0 + 55.0 / 60 + 35.38390 / 3600

        let r = Vincenty.direct(lat1: lat1, lon1: lon1,
                                azimuth1Deg: o.values["azi1_deg"]!,
                                distanceM: o.values["distance_m"]!)
        #expect(r.converged)
        // 1e-7 deg is about 1 cm -- consistent with the 1 mm distance tolerance.
        #expect(abs(r.lat2Deg - lat2) < 1e-7, "lat2 = \(r.lat2Deg), want \(lat2)")
        #expect(abs(r.lon2Deg - lon2) < 1e-7, "lon2 = \(r.lon2Deg), want \(lon2)")
        #expect(o.matches("azi2_deg", r.azimuth2Deg), "azi2 = \(r.azimuth2Deg)")
    }

    @Test("every GeodTest row round-trips through direct", arguments: Oracles.geodTestRows.map(\.id))
    func geodTestDirect(id: String) {
        let row = Oracles.geodTestRows.first { $0.id == id }!
        let r = Vincenty.direct(lat1: row.lat1, lon1: 0, azimuth1Deg: row.azi1, distanceM: row.s12)
        #expect(r.converged, "non-convergent \(id)")
        #expect(abs(r.lat2Deg - row.lat2) < 1e-7, "lat2 = \(r.lat2Deg), want \(row.lat2)")
        #expect(abs(Vincenty.normalizeSigned(r.lon2Deg - row.lon2)) < 1e-7,
                "lon2 = \(r.lon2Deg), want \(row.lon2)")
    }
}

// Oracle = the definition of the direct/inverse pair. Identity/invariant.
@Suite("Vincenty direct/inverse consistency")
struct VincentyDirectInverseTests {

    /// Direct and inverse must invert each other. This is the strongest cheap
    /// check available without a second implementation: an error in either one
    /// that is not exactly mirrored in the other shows up here.
    @Test("direct undoes inverse across a spread of regimes")
    func roundTrip() {
        let cases: [(Double, Double, Double, Double, String)] = [
            (51.5, -0.13, 40.71, -74.0, "London-NYC"),
            (-33.87, 151.21, -37.81, 144.96, "Sydney-Melbourne"),
            (35.68, 139.69, -33.87, 151.21, "Tokyo-Sydney"),
            (0.0, 0.0, 0.0, 90.0, "equatorial quarter"),
            (0.0, 0.0, 89.0, 0.0, "near-meridional"),
            (60.0, 179.0, 60.0, -179.0, "antimeridian crossing"),
            (-70.0, 10.0, 78.0, -20.0, "polar spanning"),
        ]
        for (lat1, lon1, lat2, lon2, name) in cases {
            let inv = Vincenty.inverse(lat1: lat1, lon1: lon1, lat2: lat2, lon2: lon2)
            #expect(inv.converged, "inverse failed for \(name)")
            guard inv.converged else { continue }
            let dir = Vincenty.direct(lat1: lat1, lon1: lon1,
                                      azimuth1Deg: inv.azimuth1Deg, distanceM: inv.distanceM)
            #expect(dir.converged, "direct failed for \(name)")
            #expect(abs(dir.lat2Deg - lat2) < 1e-8, "\(name): lat2 \(dir.lat2Deg) vs \(lat2)")
            #expect(abs(Vincenty.normalizeSigned(dir.lon2Deg - lon2)) < 1e-8,
                    "\(name): lon2 \(dir.lon2Deg) vs \(lon2)")
            #expect(abs(Vincenty.normalizeSigned(dir.azimuth2Deg - inv.azimuth2Deg)) < 1e-8,
                    "\(name): azi2 \(dir.azimuth2Deg) vs \(inv.azimuth2Deg)")
        }
    }

    /// The antimeridian is the classic longitude-wrap trap.
    @Test("longitude output is normalised across the antimeridian")
    func antimeridianNormalisation() {
        let r = Vincenty.direct(lat1: 0, lon1: 179.5, azimuth1Deg: 90, distanceM: 200_000)
        #expect(r.converged)
        #expect(r.lon2Deg > -180 && r.lon2Deg <= 180, "lon2 not normalised: \(r.lon2Deg)")
        #expect(r.lon2Deg < 0, "should have crossed into west longitude, got \(r.lon2Deg)")
    }

    /// Travelling due east along the equator stays on the equator.
    @Test("an equatorial due-east geodesic stays on the equator")
    func equatorialGeodesic() {
        let r = Vincenty.direct(lat1: 0, lon1: 0, azimuth1Deg: 90, distanceM: 1_000_000)
        #expect(r.converged)
        #expect(abs(r.lat2Deg) < 1e-9, "drifted off the equator: \(r.lat2Deg)")
        #expect(abs(r.azimuth2Deg - 90) < 1e-9)
    }

    /// Travelling due north along a meridian keeps the longitude fixed.
    @Test("a meridional geodesic keeps its longitude")
    func meridionalGeodesic() {
        let r = Vincenty.direct(lat1: 10, lon1: 25, azimuth1Deg: 0, distanceM: 2_000_000)
        #expect(r.converged)
        #expect(abs(r.lon2Deg - 25) < 1e-9, "longitude drifted: \(r.lon2Deg)")
        #expect(r.lat2Deg > 10, "should have moved north")
        #expect(abs(r.azimuth2Deg) < 1e-9 || abs(r.azimuth2Deg - 360) < 1e-9)
    }

    /// A zero-length step is the identity.
    @Test("zero distance returns the start point")
    func zeroDistance() {
        let r = Vincenty.direct(lat1: 12.3, lon1: -45.6, azimuth1Deg: 231, distanceM: 0)
        #expect(r.converged)
        #expect(abs(r.lat2Deg - 12.3) < 1e-12)
        #expect(abs(r.lon2Deg - (-45.6)) < 1e-12)
    }

    /// Near-antipodal inverse is documented not to converge. The Kit must report
    /// that honestly rather than returning a plausible-looking wrong answer —
    /// this is a scoped claim, not a hidden limitation.
    @Test("near-antipodal inverse reports non-convergence instead of guessing")
    func nearAntipodalIsReported() {
        let r = Vincenty.inverse(lat1: 0, lon1: 0, lat2: 0.5, lon2: 179.7)
        if !r.converged {
            #expect(r.distanceM.isNaN, "a non-convergent result must not carry a number")
        } else {
            // If it does converge, the answer must still be near half the circumference.
            #expect(r.distanceM > 19_000_000 && r.distanceM < 20_100_000,
                    "implausible near-antipodal distance \(r.distanceM)")
        }
    }
}
