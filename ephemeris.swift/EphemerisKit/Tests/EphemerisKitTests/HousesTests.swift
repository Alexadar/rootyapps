import Testing
import Foundation
import EphemerisKit

@Suite("Houses & angles")
struct HousesTests {

    // A well-separated set of places, including one inside the Arctic circle.
    static let kyiv      = GeoLocation(latitude:  50.45, longitude:  30.52, name: "Kyiv")
    static let losAngeles = GeoLocation(latitude: 34.05, longitude: -118.24, name: "Los Angeles")
    static let quito     = GeoLocation(latitude:   0.00, longitude: -78.47, name: "Quito")
    static let sydney    = GeoLocation(latitude: -33.87, longitude: 151.21, name: "Sydney")
    static let longyearbyen = GeoLocation(latitude: 78.22, longitude: 15.65, name: "Longyearbyen")

    static let moment = utc(2026, 6, 21, 12, 0)

    // MARK: Sidereal time & obliquity — external oracles

    /// Meeus, *Astronomical Algorithms*, Example 12.a: 1987 April 10 at 0h UT,
    /// GMST = 13h 10m 46.3668s = 197.693195°.
    @Test func gmstMatchesMeeusExample12a() {
        let gmst = SiderealTime.greenwichMeanSiderealTime(at: utc(1987, 4, 10, 0, 0))
        let expected = (13 + 10.0 / 60 + 46.3668 / 3600) * 15
        #expect(abs(AstroMath.norm180(gmst - expected)) < 1e-4,
                "GMST \(gmst) vs Meeus \(expected)")
    }

    /// Meeus Example 22.a: 1987 April 10, mean obliquity ε₀ = 23° 26′ 27.407″.
    @Test func obliquityMatchesMeeusExample22a() {
        let eps = SiderealTime.meanObliquity(at: utc(1987, 4, 10, 0, 0))
        let expected = 23 + 26.0 / 60 + 27.407 / 3600
        #expect(abs(eps - expected) < 1e-5, "ε \(eps) vs Meeus \(expected)")
    }

    /// Regression for the epoch trap: this module counts centuries from J2000.0
    /// (JD 2451545.0), *not* from the engine's Schlyter epoch (JD 2451543.5).
    /// Mixing them up shifts everything by 1.5 days (≈0.37° of sidereal rotation).
    @Test func julianCenturiesUsesJ2000NotSchlyterEpoch() {
        let j2000 = Date(timeIntervalSince1970: (2_451_545.0 - 2_440_587.5) * 86_400)
        #expect(abs(SiderealTime.julianCenturies(j2000)) < 1e-12)
        // One Julian century later, T == 1.
        let century = Date(timeIntervalSince1970: (2_451_545.0 + 36_525 - 2_440_587.5) * 86_400)
        #expect(abs(SiderealTime.julianCenturies(century) - 1) < 1e-9)
    }

    /// LST advances with east longitude, one degree per degree.
    @Test func localSiderealTimeTracksLongitude() {
        let t = Self.moment
        let g = SiderealTime.greenwichMeanSiderealTime(at: t)
        let e30 = SiderealTime.localMeanSiderealTime(at: t, longitude: 30)
        let w30 = SiderealTime.localMeanSiderealTime(at: t, longitude: -30)
        #expect(abs(AstroMath.norm180(e30 - g - 30)) < 1e-9)
        #expect(abs(AstroMath.norm180(w30 - g + 30)) < 1e-9)
    }

    // MARK: Angles

    @Test func angleOppositesAreExact() {
        for place in [Self.kyiv, Self.losAngeles, Self.quito, Self.sydney] {
            let a = Houses.angles(at: Self.moment, location: place)
            #expect(abs(AstroMath.norm180(a.descendant - a.ascendant - 180)) < 1e-9)
            #expect(abs(AstroMath.norm180(a.imumCoeli - a.midheaven - 180)) < 1e-9)
            #expect(a.ascendant >= 0 && a.ascendant < 360)
            #expect(a.midheaven >= 0 && a.midheaven < 360)
        }
    }

    /// The Midheaven is the ecliptic point whose right ascension is the RAMC — so mapping it
    /// back through tan(RA) = tan(λ)·cos(ε) must return the RAMC.
    @Test func midheavenHasRightAscensionEqualToRAMC() {
        for place in [Self.kyiv, Self.sydney, Self.quito] {
            let a = Houses.angles(at: Self.moment, location: place)
            let ra = AstroMath.norm360(atan2(sin(a.midheaven * .pi / 180) * cos(a.obliquity * .pi / 180),
                                             cos(a.midheaven * .pi / 180)) * 180 / .pi)
            #expect(abs(AstroMath.norm180(ra - a.ramc)) < 1e-6, "MC RA \(ra) vs RAMC \(a.ramc)")
        }
    }

    /// At the equator with 0° Aries culminating, the eastern horizon cuts the ecliptic at 90°.
    /// (Pure geometry: the east point has RA = RAMC + 90°, and RA 90° ↔ λ 90°.)
    @Test func ascendantAtEquatorIsQuarterTurnFromMC() {
        // Find a moment whose RAMC ≈ 0 at longitude 0 by searching the day.
        var best = Self.moment, bestErr = 999.0
        for minute in stride(from: 0, to: 1440, by: 1) {
            let t = utc(2026, 3, 20, 0, minute)
            let err = abs(AstroMath.norm180(SiderealTime.ramc(at: t, longitude: 0)))
            if err < bestErr { bestErr = err; best = t }
        }
        let a = Houses.angles(at: best, location: GeoLocation(latitude: 0, longitude: 0))
        #expect(bestErr < 0.3)
        #expect(abs(AstroMath.norm180(a.midheaven - 0)) < 0.5, "MC \(a.midheaven)")
        #expect(abs(AstroMath.norm180(a.ascendant - 90)) < 0.5, "Asc \(a.ascendant)")
    }

    // MARK: Cusp invariants — hold for every system, no external oracle needed

    @Test func oppositeCuspsAreAlwaysOpposed() {
        for system in HouseSystem.allCases {
            for place in [Self.kyiv, Self.losAngeles, Self.quito, Self.sydney] {
                guard let h = Houses.compute(at: Self.moment, location: place, system: system) else {
                    continue    // Placidus/Koch may be undefined; covered by its own test
                }
                for n in 1...6 {
                    let d = AstroMath.norm180(h.cusp(n + 6) - h.cusp(n) - 180)
                    #expect(abs(d) < 1e-9, "\(system) cusp \(n)/\(n + 6) not opposed (Δ\(d))")
                }
            }
        }
    }

    /// Cusps must march counterclockwise and close the circle exactly once.
    @Test func cuspsAdvanceMonotonicallyAroundTheCircle() {
        for system in HouseSystem.allCases {
            for place in [Self.kyiv, Self.losAngeles, Self.quito, Self.sydney] {
                guard let h = Houses.compute(at: Self.moment, location: place, system: system) else { continue }
                var total = 0.0
                for n in 1...12 {
                    let span = AstroMath.norm360(h.cusp(n + 1) - h.cusp(n))
                    #expect(span > 0 && span < 180, "\(system) house \(n) span \(span) at \(place.name ?? "")")
                    total += span
                }
                #expect(abs(total - 360) < 1e-6, "\(system) spans sum to \(total)")
            }
        }
    }

    /// Quadrant systems pin cusp 1 to the Ascendant *and* cusp 10 to the Midheaven.
    /// The ecliptic systems deliberately do not — that's the defining difference.
    @Test func quadrantSystemsPinBothAngles() {
        for system in HouseSystem.allCases {
            guard let h = Houses.compute(at: Self.moment, location: Self.kyiv, system: system) else { continue }
            let a = h.angles
            if system.isQuadrant {
                #expect(abs(AstroMath.norm180(h.cusp(1) - a.ascendant)) < 1e-9, "\(system) cusp1")
                #expect(abs(AstroMath.norm180(h.cusp(10) - a.midheaven)) < 1e-9, "\(system) cusp10")
            } else {
                // Equal still starts at the Asc; Whole Sign snaps to the sign boundary.
                if system == .equal {
                    #expect(abs(AstroMath.norm180(h.cusp(1) - a.ascendant)) < 1e-9)
                }
                // …but neither tracks the MC (it floats), which is the whole point.
                #expect(abs(AstroMath.norm180(h.cusp(10) - a.midheaven)) > 1e-6, "\(system) cusp10 should float")
            }
        }
    }

    @Test func wholeSignCuspsSitOnSignBoundaries() {
        let h = Houses.compute(at: Self.moment, location: Self.kyiv, system: .wholeSign)!
        for n in 1...12 {
            let inSign = h.cusp(n).truncatingRemainder(dividingBy: 30)
            #expect(inSign < 1e-9 || inSign > 30 - 1e-9, "cusp \(n) = \(h.cusp(n))")
        }
        // House 1 is the sign the Ascendant falls in.
        #expect(h.sign(ofCusp: 1) == h.angles.ascendantSign)
    }

    @Test func equalHousesAreExactlyThirtyDegreesApart() {
        let h = Houses.compute(at: Self.moment, location: Self.kyiv, system: .equal)!
        for n in 1...12 {
            #expect(abs(AstroMath.norm180(h.cusp(n + 1) - h.cusp(n) - 30)) < 1e-9)
        }
    }

    /// **The identity that pins Koch.** Its cusps are the degrees that were on the Ascendant at
    /// sidereal times spaced by thirds of the *culminating* degree's semi-diurnal arc. Step one
    /// further third back and you must land exactly on the MC — because the culminating degree
    /// rose precisely one semi-arc ago.
    ///
    /// Regression: an earlier cut trisected the *Ascendant's* semi-arc instead. That is a
    /// different system, it satisfies every structural invariant above, and it fails this test.
    @Test func kochClosesOnTheMidheaven() {
        for place in [Self.kyiv, Self.losAngeles, Self.sydney] {
            for hour in stride(from: 0, to: 24, by: 3) {
                let t = utc(2026, 6, 21, hour, 0)
                let a = Houses.angles(at: t, location: place)
                let sinAD = tan(place.latitude * .pi / 180) * tan(a.obliquity * .pi / 180)
                          * sin(a.ramc * .pi / 180)
                guard abs(sinAD) <= 1 else { continue }
                let semiArc = 90 + asin(sinAD) * 180 / .pi
                func ascAt(_ thirds: Double) -> Double {
                    Houses.ascendant(ramc: a.ramc + thirds * semiArc,
                                     latitude: place.latitude, obliquity: a.obliquity)
                }
                // One more third back must be the Midheaven — the closure property.
                #expect(abs(AstroMath.norm180(ascAt(-1) - a.midheaven)) < 1e-6,
                        "\(place.name ?? "") h\(hour): Asc(RAMC−SA)=\(ascAt(-1)) vs MC=\(a.midheaven)")

                // …and the shipped cusps must actually be built that way. This is what fails for
                // any system that trisects a different arc.
                guard let k = Houses.compute(at: t, location: place, system: .koch) else { continue }
                for (house, thirds) in [(11, -2.0 / 3), (12, -1.0 / 3), (1, 0.0),
                                        (2, 1.0 / 3), (3, 2.0 / 3)] {
                    #expect(abs(AstroMath.norm180(k.cusp(house) - ascAt(thirds))) < 1e-6,
                            "\(place.name ?? "") h\(hour) cusp \(house): \(k.cusp(house)) vs \(ascAt(thirds))")
                }
            }
        }
    }

    /// At the equator the prime vertical and the celestial equator coincide, so Campanus and
    /// Regiomontanus must produce identical cusps.
    @Test func campanusEqualsRegiomontanusOnTheEquator() {
        let c = Houses.compute(at: Self.moment, location: Self.quito, system: .campanus)!
        let r = Houses.compute(at: Self.moment, location: Self.quito, system: .regiomontanus)!
        for n in 1...12 {
            #expect(abs(AstroMath.norm180(c.cusp(n) - r.cusp(n))) < 1e-6,
                    "house \(n): campanus \(c.cusp(n)) vs regiomontanus \(r.cusp(n))")
        }
    }

    // MARK: Independent geometric re-derivation
    //
    // No published cusp oracle is wired in yet (see docs/VALIDATION.md — attempts to source one
    // failed and nothing was invented). These tests are the substitute: they rebuild the geometry
    // from vectors and assert the shipped closed forms land on it. Crucially they share **no**
    // code path with the implementation — no `atan2` cusp formula, no `AstroMath`, no house-circle
    // offset derivation — so an algebra slip in `Houses.swift` cannot hide here.

    /// Unit vector of an ecliptic degree in a frame where +x is the meridian point on the equator,
    /// +y is 90° east of it along the equator, and +z is the north celestial pole.
    private static func meridianFrameVector(longitude lon: Double, ramc: Double,
                                            obliquity eps: Double) -> (Double, Double, Double) {
        let r = Double.pi / 180
        // ecliptic → equatorial (rotate about the x axis by ε)
        let xe = cos(lon * r)
        let ye = sin(lon * r) * cos(eps * r)
        let ze = sin(lon * r) * sin(eps * r)
        // rotate about z so that RA = RAMC becomes +x
        return ( xe * cos(ramc * r) + ye * sin(ramc * r),
                -xe * sin(ramc * r) + ye * cos(ramc * r),
                 ze )
    }

    private static func cross(_ a: (Double, Double, Double), _ b: (Double, Double, Double))
        -> (Double, Double, Double) {
        (a.1 * b.2 - a.2 * b.1, a.2 * b.0 - a.0 * b.2, a.0 * b.1 - a.1 * b.0)
    }
    private static func dot(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        a.0 * b.0 + a.1 * b.1 + a.2 * b.2
    }

    /// Regiomontanus divides the **celestial equator** into 30° arcs. So each cusp must lie on the
    /// great circle through the horizon's north/south points and the equator point 30k° east of
    /// the meridian — checked here as a plane equation, not a formula.
    @Test func regiomontanusCuspsLieOnTheirHouseCircle() {
        let r = Double.pi / 180
        for place in [Self.kyiv, Self.losAngeles, Self.sydney] {
            let a = Houses.angles(at: Self.moment, location: place)
            let h = Houses.compute(at: Self.moment, location: place, system: .regiomontanus)!
            let north = (-sin(place.latitude * r), 0.0, cos(place.latitude * r))
            for (n, house) in [(1, 11), (2, 12), (3, 1), (4, 2), (5, 3)] {
                let equatorPoint = (cos(Double(n) * 30 * r), sin(Double(n) * 30 * r), 0.0)
                let normal = Self.cross(north, equatorPoint)
                let v = Self.meridianFrameVector(longitude: h.cusp(house), ramc: a.ramc,
                                                 obliquity: a.obliquity)
                #expect(abs(Self.dot(v, normal)) < 1e-9,
                        "\(place.name ?? "") cusp \(house) off its house circle by \(Self.dot(v, normal))")

                // Control: the same check on a cusp nudged 1° must FAIL, otherwise the plane
                // test is vacuous and would rubber-stamp a wrong implementation.
                let nudged = Self.meridianFrameVector(longitude: h.cusp(house) + 1,
                                                      ramc: a.ramc, obliquity: a.obliquity)
                #expect(abs(Self.dot(nudged, normal)) > 1e-4,
                        "plane test is not discriminating — a 1° error would pass")
            }
        }
    }

    /// Campanus divides the **prime vertical** instead. Same independent check, different circle:
    /// through the north/south points and the prime-vertical point C° up from the east point.
    @Test func campanusCuspsLieOnTheirPrimeVerticalCircle() {
        let r = Double.pi / 180
        for place in [Self.kyiv, Self.losAngeles, Self.sydney] {
            let a = Houses.angles(at: Self.moment, location: place)
            let h = Houses.compute(at: Self.moment, location: place, system: .campanus)!
            let phi = place.latitude * r
            let north = (-sin(phi), 0.0, cos(phi))
            for (n, house) in [(1, 11), (2, 12), (3, 1), (4, 2), (5, 3)] {
                let c = (90 - 30 * Double(n)) * r
                // cos(C)·east + sin(C)·zenith
                let pv = (sin(c) * cos(phi), cos(c), sin(c) * sin(phi))
                let normal = Self.cross(north, pv)
                let v = Self.meridianFrameVector(longitude: h.cusp(house), ramc: a.ramc,
                                                 obliquity: a.obliquity)
                #expect(abs(Self.dot(v, normal)) < 1e-9,
                        "\(place.name ?? "") cusp \(house) off its prime-vertical circle")
            }
        }
    }

    /// Placidus is defined by *time*: cusp 11 has covered 1/3 of its own semi-diurnal arc since
    /// culminating, cusp 12 two thirds, and symmetrically below the horizon. Verified straight
    /// from that definition — hour angle vs semi-arc — rather than from the solver's own relation.
    @Test func placidusCuspsSatisfyTheirSemiArcDefinition() {
        let r = Double.pi / 180
        for place in [Self.kyiv, Self.losAngeles, Self.sydney] {
            let a = Houses.angles(at: Self.moment, location: place)
            let h = Houses.compute(at: Self.moment, location: place, system: .placidus)!
            for (house, fraction, diurnal) in [(11, 1.0 / 3, true), (12, 2.0 / 3, true),
                                               (2, 2.0 / 3, false), (3, 1.0 / 3, false)] {
                let lon = h.cusp(house)
                let dec = asin(sin(a.obliquity * r) * sin(lon * r))
                let ad = asin(tan(place.latitude * r) * tan(dec)) / r      // ascensional difference
                let ra = atan2(sin(lon * r) * cos(a.obliquity * r), cos(lon * r)) / r
                let hourAngle = AstroMath.norm180(ra - a.ramc)             // east of the meridian
                let expected = diurnal ? fraction * (90 + ad)
                                       : 180 - fraction * (90 - ad)
                #expect(abs(AstroMath.norm180(hourAngle - expected)) < 1e-6,
                        "\(place.name ?? "") cusp \(house): hour angle \(hourAngle) vs \(expected)")
            }
        }
    }

    // MARK: Failure modes

    /// Placidus needs a semi-arc for *every* intermediate cusp, so inside the polar circle it
    /// collapses as soon as one of them is circumpolar — it must return nil, not nonsense.
    @Test func placidusIsUndefinedInsideThePolarCircle() {
        #expect(Houses.compute(at: Self.moment, location: Self.longyearbyen, system: .placidus) == nil,
                "Placidus should be undefined at 78°N")
        #expect(Self.longyearbyen.isPolar)
        #expect(!Self.kyiv.isPolar)
    }

    /// Koch is likewise undefined beyond the polar circle — and must stay undefined for the whole
    /// day, not just some hours. (Regression: an earlier cut only checked whether the ascending
    /// degree was circumpolar, which let Koch hand back degenerate houses wider than 180°.)
    @Test func kochIsUndefinedInsideThePolarCircleAllDay() {
        for hour in 0..<24 {
            let t = utc(2026, 6, 21, hour, 0)
            #expect(Houses.compute(at: t, location: Self.longyearbyen, system: .koch) == nil,
                    "Koch should be undefined at 78°N (hour \(hour))")
        }
    }

    /// Just *outside* the polar circle both time-based systems must still work, and produce
    /// well-formed houses — i.e. the cutoff is the polar circle, not an over-eager guard.
    @Test func timeBasedSystemsStillWorkJustOutsideThePolarCircle() {
        let tromso = GeoLocation(latitude: 64.0, longitude: 18.0, name: "below the circle")
        for system in [HouseSystem.placidus, .koch] {
            guard let h = Houses.compute(at: Self.moment, location: tromso, system: system) else {
                Issue.record("\(system) should be defined at 64°N"); continue
            }
            for n in 1...12 {
                let span = AstroMath.norm360(h.cusp(n + 1) - h.cusp(n))
                #expect(span > 0 && span < 180, "\(system) house \(n) span \(span)")
            }
        }
    }

    /// The geometric systems are pure spherical trig — they never break, at any latitude.
    @Test func geometricSystemsWorkEvenAtPolarLatitudes() {
        for system in [HouseSystem.campanus, .regiomontanus, .equal, .wholeSign] {
            for hour in stride(from: 0, to: 24, by: 6) {
                let t = utc(2026, 6, 21, hour, 0)
                #expect(Houses.compute(at: t, location: Self.longyearbyen, system: system) != nil,
                        "\(system) should still work at 78°N (hour \(hour))")
            }
        }
    }

    @Test func allSystemsResolveAtTemperateLatitudes() {
        for system in HouseSystem.allCases {
            for place in [Self.kyiv, Self.losAngeles, Self.sydney] {
                #expect(Houses.compute(at: Self.moment, location: place, system: system) != nil,
                        "\(system) failed at \(place.name ?? "")")
            }
        }
    }

    // MARK: Lookup

    @Test func houseLookupAgreesWithCuspOrdering() {
        for system in HouseSystem.allCases {
            guard let h = Houses.compute(at: Self.moment, location: Self.kyiv, system: system) else { continue }
            for n in 1...12 {
                // A degree just inside a house must report that house.
                let justInside = AstroMath.norm360(h.cusp(n) + 0.001)
                #expect(h.house(containing: justInside) == n, "\(system) house \(n)")
            }
            // Every planet lands in exactly one house.
            let sun = Ephemeris.longitude(of: .sun, at: Self.moment)
            #expect((1...12).contains(h.house(containing: sun)))
        }
    }

    /// Coordinates are clamped/wrapped on the way in.
    @Test func geoLocationNormalizesInput() {
        #expect(GeoLocation(latitude: 120, longitude: 0).latitude == 90)
        #expect(GeoLocation(latitude: -120, longitude: 0).latitude == -90)
        #expect(abs(GeoLocation(latitude: 0, longitude: 200).longitude - (-160)) < 1e-9)
    }
}
