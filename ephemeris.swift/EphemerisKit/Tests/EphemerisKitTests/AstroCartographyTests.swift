import Testing
import Foundation
import EphemerisKit

/// Astrocartography is a **construction** oracle: there is no published line table to transcribe,
/// so these tests re-derive the two defining conditions — hour angle zero for the meridian lines,
/// altitude zero for the horizon lines — from raw `Foundation` trig and assert that every point
/// the Kit hands back satisfies them.
///
/// The re-derivation deliberately shares no code with `AstroCartography`: no `AstroMath` trig, no
/// `Houses` formula, no reuse of the Kit's own `altitude(...)`. An algebra slip in the source
/// therefore cannot hide here. Where a check *does* call `Houses`, that is the point of the check —
/// the line and the house engine must name the same angle, which is the invariant that would have
/// caught the two-copies-of-the-angle-maths bug `ChartGeometry` exists for.
@Suite("Astrocartography")
struct AstroCartographyTests {

    /// An arbitrary but fixed birth instant. Nothing about it is special — which is the point:
    /// the identities below hold at every instant, and a date that happened to be degenerate
    /// (an equinox, a culmination at Greenwich) could flatter a wrong implementation.
    static let birth = utc(1990, 2, 14, 7, 42)
    static let solsticeNoon = utc(2026, 6, 21, 12, 0)

    static let wideBand = LatitudeBand(south: -66, north: 66, step: 6)
    static let midBand  = LatitudeBand(south: -50, north: 50, step: 5)

    // MARK: - Independent re-derivation (raw trig only)

    private static let rad = Double.pi / 180

    /// Ecliptic → equatorial, written out longhand.
    private static func equatorial(_ lambda: Double, _ eps: Double) -> (ra: Double, dec: Double) {
        let ra = atan2(sin(lambda * rad) * cos(eps * rad), cos(lambda * rad)) / rad
        let dec = asin(sin(eps * rad) * sin(lambda * rad)) / rad
        return (AstroMath.norm360(ra), dec)
    }

    /// sin h = sin φ sin δ + cos φ cos δ cos H, longhand.
    private static func altitude(dec: Double, lat: Double, hourAngle h: Double) -> Double {
        let s = sin(lat * rad) * sin(dec * rad) + cos(lat * rad) * cos(dec * rad) * cos(h * rad)
        return asin(min(1, max(-1, s))) / rad
    }

    /// Hour angle of a body at a terrestrial longitude, from the instant's GMST.
    private static func hourAngle(rightAscension ra: Double, longitude lon: Double, at t: Date) -> Double {
        AstroMath.norm180(SiderealTime.greenwichMeanSiderealTime(at: t) + lon - ra)
    }

    // MARK: - MC / IC: the meridian lines

    /// **The MC oracle.** At every point of a body's MC line the body's right ascension equals the
    /// local RAMC — i.e. its hour angle is zero. Latitude never enters, so the line is vertical.
    @Test func mcLinePutsTheBodyOnTheLocalMeridian() {
        let o = astrocartoOracles.all.first { $0.id == "astrocarto-mc-hour-angle" }!
        let eps = SiderealTime.meanObliquity(at: Self.birth)
        for body in CelestialBody.allCases {
            let line = AstroCartography.line(of: body, angle: .midheaven, at: Self.birth, band: Self.wideBand)
            let (ra, _) = Self.equatorial(Ephemeris.longitude(of: body, at: Self.birth), eps)
            #expect(line.angle.isMeridian)
            #expect(line.meridian != nil, "\(body.name) MC line has no meridian")
            #expect(line.latitudeLimit == nil, "a meridian exists at every latitude")
            #expect(line.points.count == Self.wideBand.latitudes.count)
            for p in line.points {
                let h = Self.hourAngle(rightAscension: ra, longitude: p.longitude, at: Self.birth)
                #expect(o.matches("hourAngleDeg", h),
                        "\(body.name) MC at \(p.latitude)°: hour angle \(h), expected 0")
                #expect(p.longitude == line.meridian!, "MC line must not bend with latitude")
            }
        }
    }

    /// The IC line is the MC line's antimeridian — exactly, at every body.
    @Test func icLineIsExactlyOppositeTheMCLine() {
        let o = astrocartoOracles.all.first { $0.id == "astrocarto-ic-opposition" }!
        for body in CelestialBody.allCases {
            let mc = AstroCartography.line(of: body, angle: .midheaven, at: Self.birth, band: Self.wideBand)
            let ic = AstroCartography.line(of: body, angle: .imumCoeli, at: Self.birth, band: Self.wideBand)
            let sep = AstroMath.separation(mc.meridian!, ic.meridian!)
            #expect(o.matches("separationDeg", sep),
                    "\(body.name): MC \(mc.meridian!) vs IC \(ic.meridian!) separated by \(sep)")
        }
    }

    /// The house engine, asked at a point on the MC line, must call that body the Midheaven — and
    /// on the IC line, the Imum Coeli. This is the cross-check that the line maths and
    /// `Houses` have not drifted into two disagreeing conventions.
    @Test func housesAgreeThatMeridianLinesAreCulminations() {
        for body in CelestialBody.allCases {
            let lambda = Ephemeris.longitude(of: body, at: Self.birth)
            for (angle, expected) in [(AstroCartoAngle.midheaven, "mc"), (.imumCoeli, "ic")] {
                let line = AstroCartography.line(of: body, angle: angle, at: Self.birth, band: Self.midBand)
                for p in line.points {
                    let a = Houses.angles(at: Self.birth, location: p.location)
                    let got = expected == "mc" ? a.midheaven : a.imumCoeli
                    #expect(abs(AstroMath.norm180(got - lambda)) < 1e-6,
                            "\(body.name) \(angle.abbreviation) at \(p.latitude)°: \(expected) = \(got), body at \(lambda)")
                }
            }
        }
    }

    /// `equatorial(eclipticLongitude:obliquity:)` must be the exact inverse of
    /// `Houses.midheaven(ramc:obliquity:)`, on the same branch. If it were not, the MC line would
    /// be a quadrant out for half the sky and every other test here would still pass.
    @Test func equatorialTransformInvertsHousesMidheaven() {
        for eps in [0.0, 23.4392911, 40.0] {
            for lambda in stride(from: 0.0, to: 360.0, by: 7.0) {
                let ra = AstroCartography.equatorial(eclipticLongitude: lambda, obliquity: eps).rightAscension
                let back = Houses.midheaven(ramc: ra, obliquity: eps)
                #expect(abs(AstroMath.norm180(back - lambda)) < 1e-9,
                        "ε \(eps), λ \(lambda) → RA \(ra) → λ \(back)")
            }
        }
    }

    // MARK: - AC / DC: the horizon lines

    /// **The AC/DC oracle.** At every point of a rising or setting line the body's geometric
    /// altitude is zero.
    @Test func horizonLinesPutTheBodyOnTheHorizon() {
        let o = astrocartoOracles.all.first { $0.id == "astrocarto-horizon-altitude" }!
        let eps = SiderealTime.meanObliquity(at: Self.birth)
        for body in CelestialBody.allCases {
            let (ra, dec) = Self.equatorial(Ephemeris.longitude(of: body, at: Self.birth), eps)
            for angle in [AstroCartoAngle.ascendant, .descendant] {
                let line = AstroCartography.line(of: body, angle: angle, at: Self.birth, band: Self.wideBand)
                #expect(!line.isEmpty, "\(body.name) \(angle.abbreviation) line came back empty")
                #expect(line.meridian == nil, "a horizon line is not a meridian")
                for p in line.points {
                    let h = Self.hourAngle(rightAscension: ra, longitude: p.longitude, at: Self.birth)
                    let alt = Self.altitude(dec: dec, lat: p.latitude, hourAngle: h)
                    #expect(o.matches("altitudeDeg", alt),
                            "\(body.name) \(angle.abbreviation) at \(p.latitude)°: altitude \(alt)")
                }
            }
        }
    }

    /// Control: the altitude check above must be *discriminating*. Nudge the longitude by one
    /// degree at the equator — where the horizon crossing is steepest — and the altitude has to
    /// move by roughly a degree, otherwise the test would rubber-stamp a wrong line.
    @Test func altitudeCheckWouldCatchAOneDegreeError() {
        let eps = SiderealTime.meanObliquity(at: Self.birth)
        for body in CelestialBody.allCases {
            let (ra, dec) = Self.equatorial(Ephemeris.longitude(of: body, at: Self.birth), eps)
            for angle in [AstroCartoAngle.ascendant, .descendant] {
                let lon = AstroCartography.longitude(of: body, standingOn: angle,
                                                     at: Self.birth, latitude: 0)!
                let h = Self.hourAngle(rightAscension: ra, longitude: lon + 1, at: Self.birth)
                let alt = Self.altitude(dec: dec, lat: 0, hourAngle: h)
                #expect(abs(alt) > 0.5,
                        "1° off \(body.name) \(angle.abbreviation) still gives altitude \(alt)")
            }
        }
    }

    /// The house engine, asked at a point on the AC line, must call that body the Ascendant — and
    /// on the DC line, the Descendant. This is what pins *which* horizon crossing is which; the
    /// altitude test alone cannot tell rising from setting.
    @Test func housesAgreeThatHorizonLinesAreTheAscendantAndDescendant() {
        for body in CelestialBody.allCases {
            let lambda = Ephemeris.longitude(of: body, at: Self.birth)
            for angle in [AstroCartoAngle.ascendant, .descendant] {
                let line = AstroCartography.line(of: body, angle: angle, at: Self.birth, band: Self.midBand)
                for p in line.points {
                    let a = Houses.angles(at: Self.birth, location: p.location)
                    let got = angle == .ascendant ? a.ascendant : a.descendant
                    #expect(abs(AstroMath.norm180(got - lambda)) < 1e-6,
                            "\(body.name) \(angle.abbreviation) at \(p.latitude)°: got \(got), body at \(lambda)")
                }
            }
        }
    }

    /// AC and DC are never the same place except at the tangency latitude — a regression guard for
    /// a branch-selection bug that returns the rising longitude for both.
    @Test func ascendantAndDescendantLinesAreDistinct() {
        for body in CelestialBody.allCases {
            for lat in stride(from: -50.0, through: 50.0, by: 10.0) {
                let ac = AstroCartography.longitude(of: body, standingOn: .ascendant, at: Self.birth, latitude: lat)!
                let dc = AstroCartography.longitude(of: body, standingOn: .descendant, at: Self.birth, latitude: lat)!
                #expect(AstroMath.separation(ac, dc) > 1,
                        "\(body.name) at \(lat)°: AC \(ac) and DC \(dc) coincide")
            }
        }
    }

    /// **Meeus 15.1 as an identity.** Whatever H₀ the Kit returns must satisfy
    /// cos H₀ + tan φ·tan δ = 0 — re-derived here with raw trig over a grid.
    @Test func semiDiurnalArcSatisfiesTheRisingRelation() {
        let o = astrocartoOracles.all.first { $0.id == "astrocarto-rise-hour-angle-relation" }!
        for dec in stride(from: -23.0, through: 23.0, by: 4.6) {
            for lat in stride(from: -66.0, through: 66.0, by: 6.0) {
                let h0 = AstroCartography.semiDiurnalArc(declination: dec, latitude: lat)
                #expect(h0 != nil, "δ \(dec) / φ \(lat) is not circumpolar and must have an arc")
                let residual = cos(h0! * Self.rad) + tan(lat * Self.rad) * tan(dec * Self.rad)
                #expect(o.matches("residual", residual),
                        "δ \(dec) φ \(lat): H₀ \(h0!) leaves residual \(residual)")
            }
        }
    }

    // MARK: - Circumpolar: the API must say "no line", not guess one

    /// **The failure-mode oracle.** At the June solstice the Sun does not set north of the Arctic
    /// Circle, so it has no rising line there — and the published circle, 66°33′49″, is exactly the
    /// latitude limit the maths must produce.
    @Test func sunsRisingLineStopsAtTheArcticCircleOnTheSolstice() {
        let o = astrocartoOracles.all.first { $0.id == "astrocarto-solstice-rising-limit" }!
        let f = AstroCartography.frame(of: .sun, at: Self.solsticeNoon)
        let limit = AstroCartography.risingLatitudeLimit(declination: f.declination)
        #expect(o.matches("limitLatitudeDeg", limit),
                "solstice rising limit \(limit) (δ☉ = \(f.declination)) vs Arctic Circle 66.5636")

        // Just inside the circle the line exists; just outside it must be absent — for BOTH
        // horizon angles, and for the polar night in the south as well as the midnight sun north.
        for angle in [AstroCartoAngle.ascendant, .descendant] {
            #expect(AstroCartography.longitude(of: .sun, standingOn: angle,
                                               at: Self.solsticeNoon, latitude: limit - 0.5) != nil)
            #expect(AstroCartography.longitude(of: .sun, standingOn: angle,
                                               at: Self.solsticeNoon, latitude: limit + 0.5) == nil,
                    "\(angle.abbreviation) must not exist at \(limit + 0.5)°N on the June solstice")
            #expect(AstroCartography.longitude(of: .sun, standingOn: angle,
                                               at: Self.solsticeNoon, latitude: -(limit + 0.5)) == nil,
                    "\(angle.abbreviation) must not exist in the polar night either")
        }

        // …and the meridian lines are unaffected: culmination happens even for a body that never
        // rises. (Refusing an MC line inside the polar circle would be the classic over-eager guard.)
        for angle in [AstroCartoAngle.midheaven, .imumCoeli] {
            #expect(AstroCartography.longitude(of: .sun, standingOn: angle,
                                               at: Self.solsticeNoon, latitude: 85) != nil)
        }
    }

    /// A sampled line must simply stop at the limit rather than emit a nonsense point, and must
    /// advertise where it stopped.
    @Test func sampledLinesAreTruncatedAtTheCircumpolarLimit() {
        let band = LatitudeBand(south: -85, north: 85, step: 1)
        var truncated = 0
        for body in CelestialBody.allCases {
            let f = AstroCartography.frame(of: body, at: Self.solsticeNoon)
            let limit = AstroCartography.risingLatitudeLimit(declination: f.declination)
            for angle in [AstroCartoAngle.ascendant, .descendant] {
                let line = AstroCartography.line(of: body, angle: angle, at: Self.solsticeNoon, band: band)
                #expect(line.latitudeLimit != nil)
                #expect(abs(line.latitudeLimit! - limit) < 1e-9)
                #expect(!line.isEmpty)
                // Exactly the samples inside the limit survive — no more, no fewer.
                let expected = band.latitudes.filter { abs($0) <= limit + 1e-9 }
                #expect(line.points.map(\.latitude) == expected,
                        "\(body.name) \(angle.abbreviation): kept \(line.points.count) of \(expected.count) samples inside |φ| ≤ \(limit)")
                if line.points.count < band.latitudes.count { truncated += 1 }
            }
        }
        // Non-vacuous: the band deliberately runs past the limit of the high-declination bodies.
        #expect(truncated > 0, "nothing was truncated — the band never reached a circumpolar zone")
    }

    /// The poles themselves: `tan φ` is not a usable number at ±90°, so the horizon angles refuse
    /// rather than return a value built on an overflow.
    @Test func horizonLinesRefuseTheGeographicPoles() {
        for lat in [90.0, -90.0] {
            #expect(AstroCartography.semiDiurnalArc(declination: 10, latitude: lat) == nil)
            for angle in [AstroCartoAngle.ascendant, .descendant] {
                #expect(AstroCartography.longitude(of: .mars, standingOn: angle,
                                                   at: Self.birth, latitude: lat) == nil)
            }
        }
    }

    /// At the tangency latitude the body grazes the horizon at a culmination, so the AC and DC
    /// lines meet — on the **IC** meridian when φ and δ share a sign (the body is about to become
    /// circumpolar-above), and on the **MC** meridian when they do not (about to never rise).
    /// Getting this pairing backwards is a sign error the altitude test cannot see.
    @Test func acAndDcMeetOnTheMeridianAtTheTangencyLatitude() {
        for body in CelestialBody.allCases {
            let f = AstroCartography.frame(of: body, at: Self.birth)
            guard abs(f.declination) > 1 else { continue }   // a δ≈0 body has no tangency to test
            let limit = AstroCartography.risingLatitudeLimit(declination: f.declination)
            let mc = AstroCartography.longitude(of: body, standingOn: .midheaven, at: Self.birth, latitude: 0)!
            let ic = AstroCartography.longitude(of: body, standingOn: .imumCoeli, at: Self.birth, latitude: 0)!

            for sign in [1.0, -1.0] {
                let lat = sign * (limit - 0.001)
                let ac = AstroCartography.longitude(of: body, standingOn: .ascendant, at: Self.birth, latitude: lat)!
                let dc = AstroCartography.longitude(of: body, standingOn: .descendant, at: Self.birth, latitude: lat)!
                #expect(AstroMath.separation(ac, dc) < 2,
                        "\(body.name) at \(lat)°: AC \(ac) and DC \(dc) should nearly meet")
                let sameSign = (lat * f.declination) > 0
                let expected = sameSign ? ic : mc
                #expect(AstroMath.separation(ac, expected) < 2,
                        "\(body.name) at \(lat)° (δ \(f.declination)): AC \(ac) should approach \(sameSign ? "IC" : "MC") \(expected)")
            }
        }
    }

    // MARK: - The degenerate equator case, in the pure frame

    /// **The quadrature oracle.** A body on the celestial equator rises exactly 6h before it
    /// culminates at *every* latitude, so its AC and DC lines are meridians 90° either side of the
    /// MC line. Driven from the pure frame with ε = 0 and λ = 0, which makes δ identically zero —
    /// no ephemeris error, so the expected value is exact.
    ///
    /// This is also the sharpest test of the east/west branch: at δ = 0 the two candidate hour
    /// angles are symmetric, so nothing but a correct rising convention separates them.
    @Test func equatorialBodyRisesExactlyNinetyDegreesEastOfItsMeridian() {
        let o = astrocartoOracles.all.first { $0.id == "astrocarto-equinox-quadrature" }!
        let mc = AstroCartography.longitude(ofEclipticDegree: 0, standingOn: .midheaven,
                                            obliquity: 0, latitude: 0, gmst: 0)!
        #expect(abs(mc) < 1e-12)
        for lat in stride(from: -80.0, through: 80.0, by: 8.0) {
            let ac = AstroCartography.longitude(ofEclipticDegree: 0, standingOn: .ascendant,
                                                obliquity: 0, latitude: lat, gmst: 0)!
            let dc = AstroCartography.longitude(ofEclipticDegree: 0, standingOn: .descendant,
                                                obliquity: 0, latitude: lat, gmst: 0)!
            #expect(o.matches("acOffsetDeg", AstroMath.norm180(ac - mc)),
                    "φ \(lat): AC offset \(AstroMath.norm180(ac - mc)), expected -90")
            #expect(o.matches("dcOffsetDeg", AstroMath.norm180(dc - mc)),
                    "φ \(lat): DC offset \(AstroMath.norm180(dc - mc)), expected +90")
        }
    }

    /// **The subsolar oracle.** The Sun's MC meridian at the latitude of its own declination is
    /// the subsolar point, where the Sun is overhead.
    @Test func subsolarPointSitsOnTheSunsMCLine() {
        let o = astrocartoOracles.all.first { $0.id == "astrocarto-subsolar-zenith" }!
        let f = AstroCartography.frame(of: .sun, at: Self.birth)
        let mc = AstroCartography.longitude(of: .sun, standingOn: .midheaven, at: Self.birth, latitude: 0)!
        let h = Self.hourAngle(rightAscension: f.rightAscension, longitude: mc, at: Self.birth)
        let alt = Self.altitude(dec: f.declination, lat: f.declination, hourAngle: h)
        #expect(o.matches("altitudeDeg", alt), "subsolar altitude \(alt)")

        // The Kit's own altitude helper must agree with the longhand one — it is public API.
        let kit = AstroCartography.altitude(of: .sun, at: Self.birth,
                                            seenFrom: GeoLocation(latitude: f.declination, longitude: mc))
        #expect(abs(kit - alt) < 1e-9)
    }

    // MARK: - Wrap handling (rule: the 0/360 seam is explicit and tested)

    /// Every longitude the Kit emits is already in the `GeoLocation` range (-180, 180].
    @Test func everyLongitudeIsInTheCanonicalRange() {
        for line in AstroCartography.lines(at: Self.birth, band: Self.wideBand) {
            for p in line.points {
                #expect(p.longitude > -180 && p.longitude <= 180,
                        "\(line.body.name) \(line.angle.abbreviation): \(p.longitude) out of range")
                #expect(p.location.longitude == p.longitude, "a point must survive GeoLocation unchanged")
            }
        }
    }

    /// Horizon lines cross the antimeridian, where the raw longitudes jump ±360. The unwrapped
    /// series must be continuous *and* still normalise back to the raw one — an unwrap that drifts
    /// would draw the line in the wrong hemisphere.
    @Test func antimeridianWrapIsUnwrappedForDrawing() {
        var sawWrap = false
        let band = LatitudeBand(south: -50, north: 50, step: 1)
        for hour in 0..<24 {
            let t = utc(1990, 2, 14, hour, 0)
            for line in AstroCartography.lines(at: t, bodies: [.sun, .moon, .mars],
                                               angles: [.ascendant, .descendant], band: band) {
                let raw = line.points.map(\.longitude)
                let cont = line.continuousLongitudes
                #expect(raw.count == cont.count)
                for i in raw.indices {
                    #expect(abs(AstroMath.norm180(cont[i] - raw[i])) < 1e-9,
                            "unwrapped series drifted off the raw longitude")
                    guard i > 0 else { continue }
                    #expect(abs(cont[i] - cont[i - 1]) < 15,
                            "\(line.body.name) \(line.angle.abbreviation) h\(hour): unwrapped jump \(cont[i] - cont[i - 1])")
                    if abs(raw[i] - raw[i - 1]) > 180 { sawWrap = true }
                }
            }
        }
        #expect(sawWrap, "no sampled line crossed the antimeridian — the unwrap test proved nothing")
    }

    // MARK: - Shape of the API

    @Test func linesCoversEveryBodyAndAngleExactlyOnce() {
        let lines = AstroCartography.lines(at: Self.birth, band: Self.midBand)
        #expect(lines.count == CelestialBody.allCases.count * AstroCartoAngle.allCases.count)
        let keys = Set(lines.map { "\($0.body.rawValue)-\($0.angle.rawValue)" })
        #expect(keys.count == lines.count, "duplicate body/angle pair")
        for a in AstroCartoAngle.allCases {
            #expect(a.opposite.opposite == a)
            #expect(a.opposite != a)
            #expect(a.isMeridian == a.opposite.isMeridian)
        }
    }

    /// A latitude band always includes both endpoints, even when the step does not divide it.
    @Test func latitudeBandAlwaysReachesBothEnds() {
        let odd = LatitudeBand(south: -60, north: 60, step: 7)
        #expect(odd.latitudes.first == -60)
        #expect(abs(odd.latitudes.last! - 60) < 1e-9)
        let even = LatitudeBand(south: -60, north: 60, step: 10)
        #expect(even.latitudes.count == 13)
        #expect(abs(even.latitudes.last! - 60) < 1e-9)
    }

    /// The offset query must be exact at the place's own latitude, and signed east-positive.
    @Test func longitudeOffsetIsZeroOnTheLineAndSignedEastward() {
        for body in CelestialBody.allCases {
            for angle in AstroCartoAngle.allCases {
                let lat = 41.9
                let lon = AstroCartography.longitude(of: body, standingOn: angle,
                                                     at: Self.birth, latitude: lat)!
                let onLine = GeoLocation(latitude: lat, longitude: lon)
                let offset = AstroCartography.longitudeOffset(of: body, angle: angle,
                                                              at: Self.birth, from: onLine)!
                #expect(abs(offset) < 1e-9, "\(body.name) \(angle.abbreviation): offset \(offset) on its own line")

                // Standing 5° east of the line, the line is 5° to the west.
                let east = GeoLocation(latitude: lat, longitude: lon + 5)
                let shifted = AstroCartography.longitudeOffset(of: body, angle: angle,
                                                               at: Self.birth, from: east)!
                #expect(abs(shifted + 5) < 1e-9, "\(body.name) \(angle.abbreviation): offset \(shifted), expected -5")
            }
        }
    }

    // MARK: - Oracle contract

    /// The module's oracles must satisfy the same rules `OracleGuardTests` enforces on the shared
    /// corpus, *before* an integration pass merges them in — otherwise the merge is what fails.
    @Test func astrocartoOraclesSatisfyTheCorpusContract() {
        #expect(!astrocartoOracles.all.isEmpty)
        var ids = Set<String>()
        for o in astrocartoOracles.all {
            #expect(o.id.hasPrefix("astrocarto-"), "oracle '\(o.id)' is not namespaced")
            #expect(ids.insert(o.id).inserted, "duplicate oracle id '\(o.id)'")
            #expect(!o.source.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(!o.inputs.isEmpty)
            #expect(!o.precision.isEmpty)
            #expect(!o.values.isEmpty)
            for key in o.values.keys {
                #expect((o.tolerances[key] ?? 0) > 0, "'\(o.id)' value '\(key)' has no positive tolerance")
            }
            for key in o.tolerances.keys {
                #expect(o.values[key] != nil, "'\(o.id)' tolerance '\(key)' has no value")
            }
            // This array is merged into the shared corpus, so the id must appear there EXACTLY
            // once: zero means the merge dropped it, two means it collides with another module.
            #expect(Oracles.all.filter { $0.id == o.id }.count == 1,
                    "'\(o.id)' is not present exactly once in Oracles.all")
        }
    }
}
