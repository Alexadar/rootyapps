import Foundation

/// Which of the four chart angles a body occupies along a line.
///
/// The names match `ChartAngles` deliberately: an astrocartography line is nothing more than the
/// set of places where the *house engine* would report this body sitting on that angle at the
/// birth instant. Keeping the vocabulary identical is what lets the tests assert that equivalence
/// instead of trusting two parallel derivations to agree — the failure mode `ChartGeometry` exists
/// to prevent.
public enum AstroCartoAngle: String, CaseIterable, Sendable, Hashable {
    case midheaven, imumCoeli, ascendant, descendant

    /// MC/IC lines are meridians — one terrestrial longitude, valid at every latitude — because
    /// culmination depends only on hour angle, and hour angle does not know about latitude.
    public var isMeridian: Bool { self == .midheaven || self == .imumCoeli }

    /// "MC" / "IC" / "AC" / "DC" — the labels the literature prints on the map.
    public var abbreviation: String {
        switch self {
        case .midheaven: "MC"; case .imumCoeli: "IC"
        case .ascendant: "AC"; case .descendant: "DC"
        }
    }

    /// The angle 180° away, which is always the other line of the same pair.
    public var opposite: AstroCartoAngle {
        switch self {
        case .midheaven: .imumCoeli; case .imumCoeli: .midheaven
        case .ascendant: .descendant; case .descendant: .ascendant
        }
    }
}

/// One geographic point of a line.
public struct AstroCartoPoint: Hashable, Sendable {
    /// Degrees, **north positive**.
    public let latitude: Double
    /// Degrees, **east positive**, in (-180, 180] — the `GeoLocation` convention, so a point can
    /// be handed straight back to the house engine without a sign audit.
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = AstroMath.norm180(longitude)
    }

    public var location: GeoLocation { GeoLocation(latitude: latitude, longitude: longitude) }
}

/// The latitude band a horizon line is sampled over.
///
/// There is no "correct" band: rising/setting lines are curves in latitude and only a sampling can
/// be handed to a renderer. The default stops at ±70° because beyond that the lines of the slower,
/// higher-declination bodies start disappearing into the circumpolar zone anyway, and because
/// `tan φ` — which every horizon formula runs through — starts shedding significant digits.
public struct LatitudeBand: Hashable, Sendable {
    public let south: Double
    public let north: Double
    public let step: Double

    public init(south: Double = -70, north: Double = 70, step: Double = 1) {
        precondition(north > south, "latitude band must run south → north")
        precondition(step > 0, "latitude step must be positive")
        self.south = south
        self.north = north
        self.step = step
    }

    public static let `default` = LatitudeBand()

    /// Sample latitudes, south → north. Both endpoints are always present even when the step does
    /// not divide the band evenly — a line that stops 0.6° short of the band edge looks like a
    /// bug on a map.
    public var latitudes: [Double] {
        let n = Int(((north - south) / step + 1e-9).rounded(.down))
        var out = (0...n).map { south + Double($0) * step }
        if let last = out.last, last < north - 1e-9 { out.append(north) }
        return out
    }
}

/// One body on one angle: the locus, plus the facts a caller needs to draw or query it.
public struct AstroCartoLine: Hashable, Sendable {
    public let body: CelestialBody
    public let angle: AstroCartoAngle
    /// Sampled points ordered south → north. Empty when the whole band is circumpolar for this
    /// body — which is a real answer, not a failure.
    public let points: [AstroCartoPoint]
    /// The single terrestrial longitude of an MC/IC meridian; `nil` for horizon lines.
    public let meridian: Double?
    /// The |latitude| beyond which this line does not exist because the body never crosses the
    /// horizon there (90° − |δ|). `nil` for meridians, which exist everywhere.
    public let latitudeLimit: Double?

    public var isEmpty: Bool { points.isEmpty }

    /// The sampled longitudes made continuous — successive differences are taken through
    /// `norm180`, so the series may run outside ±180.
    ///
    /// Every horizon line crosses the antimeridian somewhere, and a renderer that draws the raw
    /// `points` gets a full-width seam artefact at the crossing. Unwrapping here (rather than in
    /// each caller) keeps that trap in one place.
    public var continuousLongitudes: [Double] {
        guard let first = points.first else { return [] }
        var running = first.longitude
        var out = [running]
        for p in points.dropFirst() {
            running += AstroMath.norm180(p.longitude - running)
            out.append(running)
        }
        return out
    }
}

/// Astro\*Carto\*Graphy — for one instant, the loci on Earth where each body is *angular*.
///
/// The whole subject is one substitution. A chart's angles are fixed by the RAMC (= local sidereal
/// time), so "where on Earth is Jupiter on the Midheaven?" is really "at what longitude does the
/// local sidereal time equal Jupiter's right ascension?" — one meridian, latitude-independent.
/// The horizon lines are the same question asked of altitude instead of hour angle, and altitude
/// *does* depend on latitude, so those come out as curves:
///
///     sin h = sin φ·sin δ + cos φ·cos δ·cos H  =  0   ⟹   cos H₀ = −tan φ·tan δ
///
/// with the rising branch at `H = −H₀` (east of the meridian) and the setting branch at `H = +H₀`.
/// `|tan φ·tan δ| > 1` has no solution: the body is circumpolar there and simply has no rising
/// line, which is why every horizon entry point is optional.
///
/// **β = 0 by construction.** This Kit's position engine publishes ecliptic *longitude* only, so a
/// body is treated as the ecliptic degree it occupies. That is a real approximation for the Moon
/// (±5°) and Pluto (±17°) — their true declination differs from the ecliptic degree's — but it is
/// also what makes these lines exactly consistent with `Houses`: on any AC line the house engine
/// returns this very degree as the Ascendant, and that identity is the test oracle. Adding true
/// latitude later means publishing β from the position engine and would break that identity, so it
/// is a deliberate choice rather than an oversight.
public enum AstroCartography {

    /// Everything about a body that the line geometry depends on, resolved once per body.
    public struct BodyFrame: Hashable, Sendable {
        public let body: CelestialBody
        /// Geocentric ecliptic longitude, degrees [0, 360).
        public let eclipticLongitude: Double
        /// Right ascension of that ecliptic degree, degrees [0, 360).
        public let rightAscension: Double
        /// Declination of that ecliptic degree, degrees [-90, 90].
        public let declination: Double
        public let obliquity: Double
        /// Greenwich Mean Sidereal Time, degrees — the bridge from right ascension to terrestrial
        /// longitude.
        public let gmst: Double
    }

    // MARK: - Pure frame (no `Date`, so tests can drive it with exact inputs)

    /// Equatorial coordinates of a point **on** the ecliptic.
    ///
    /// This is the exact inverse of `Houses.midheaven(ramc:obliquity:)` — same branch, same
    /// `atan2` structure — which is asserted in the tests rather than assumed.
    public static func equatorial(eclipticLongitude lambda: Double,
                                  obliquity eps: Double) -> (rightAscension: Double, declination: Double) {
        let ra = AstroMath.norm360(AstroMath.atan2d(AstroMath.sind(lambda) * AstroMath.cosd(eps),
                                                    AstroMath.cosd(lambda)))
        let dec = AstroMath.asind(clampUnit(AstroMath.sind(eps) * AstroMath.sind(lambda)))
        return (ra, dec)
    }

    /// Half the time (expressed as an angle) the body spends above the horizon: `cos H₀ = −tan φ·tan δ`
    /// (Meeus, *Astronomical Algorithms*, 15.1, with the standard altitude taken as exactly 0 —
    /// no refraction, no semidiameter, because an astrocartography line is a geometric locus, not
    /// a rise/set time).
    ///
    /// `nil` when the body is circumpolar at that latitude: it never touches the horizon, so
    /// neither an AC nor a DC line exists there. Returning `nil` rather than clamping is the whole
    /// point — a clamped value would draw a line where there is none.
    public static func semiDiurnalArc(declination dec: Double, latitude phi: Double) -> Double? {
        guard abs(phi) < 90 else { return nil }        // tan(±90°) is not a number we can trust
        let c = -AstroMath.tand(phi) * AstroMath.tand(dec)
        guard abs(c) <= 1 else { return nil }
        return acos(c) * AstroMath.deg
    }

    /// The |latitude| at which a body of this declination only grazes the horizon; poleward of it
    /// there is no rising line at all. Falls straight out of `|tan φ·tan δ| ≤ 1`.
    public static func risingLatitudeLimit(declination dec: Double) -> Double {
        90 - abs(dec)
    }

    /// Terrestrial longitude (east positive) where the ecliptic degree `lambda` stands on `angle`
    /// at `latitude`, given the instant's obliquity and Greenwich sidereal time.
    ///
    /// `nil` only for the horizon angles, and only when the degree is circumpolar there.
    public static func longitude(ofEclipticDegree lambda: Double,
                                 standingOn angle: AstroCartoAngle,
                                 obliquity eps: Double,
                                 latitude phi: Double,
                                 gmst: Double) -> Double? {
        let (ra, dec) = equatorial(eclipticLongitude: lambda, obliquity: eps)

        switch angle {
        case .midheaven:
            // Culmination is H = 0, i.e. local sidereal time == right ascension.
            return AstroMath.norm180(ra - gmst)
        case .imumCoeli:
            return AstroMath.norm180(ra + 180 - gmst)

        case .ascendant, .descendant:
            guard let h0 = semiDiurnalArc(declination: dec, latitude: phi) else { return nil }
            // Two hour angles put the body on the horizon, ∓H₀. Which one is *rising* is exactly
            // the sign convention this codebase has been bitten by before, so it is not asserted
            // here — it is asked of the house engine. The horizon and the ecliptic are both great
            // circles, so they meet at two antipodal points: whichever RAMC makes
            // `Houses.ascendant` return *this* degree is the rising one, and the other returns the
            // degree 180° away. The discrimination is therefore 0° vs 180° wide, not marginal.
            let east = AstroMath.norm360(ra - h0)      // body east of the meridian
            let west = AstroMath.norm360(ra + h0)      // body west of the meridian
            let eastMiss = AstroMath.separation(Houses.ascendant(ramc: east, latitude: phi, obliquity: eps), lambda)
            let westMiss = AstroMath.separation(Houses.ascendant(ramc: west, latitude: phi, obliquity: eps), lambda)
            let eastIsRising = eastMiss <= westMiss
            let wantRising = angle == .ascendant
            let ramc = (eastIsRising == wantRising) ? east : west
            return AstroMath.norm180(ramc - gmst)
        }
    }

    // MARK: - Bodies and instants

    /// Resolves a body's position into the equatorial frame once, so a whole line costs one
    /// ephemeris evaluation rather than one per sampled latitude.
    public static func frame(of body: CelestialBody, at date: Date) -> BodyFrame {
        let eps = SiderealTime.meanObliquity(at: date)
        let lambda = Ephemeris.longitude(of: body, at: date)
        let (ra, dec) = equatorial(eclipticLongitude: lambda, obliquity: eps)
        return BodyFrame(body: body,
                         eclipticLongitude: lambda,
                         rightAscension: ra,
                         declination: dec,
                         obliquity: eps,
                         gmst: SiderealTime.greenwichMeanSiderealTime(at: date))
    }

    /// Terrestrial longitude of a body's line at one latitude, or `nil` if the (horizon) line does
    /// not reach that latitude.
    public static func longitude(of body: CelestialBody,
                                 standingOn angle: AstroCartoAngle,
                                 at date: Date,
                                 latitude: Double) -> Double? {
        let f = frame(of: body, at: date)
        return longitude(ofEclipticDegree: f.eclipticLongitude, standingOn: angle,
                         obliquity: f.obliquity, latitude: latitude, gmst: f.gmst)
    }

    /// One sampled line.
    ///
    /// Meridian lines are still emitted at every sampled latitude (all with the same longitude) so
    /// a caller can draw every line the same way; `meridian` carries the fact that it is vertical.
    public static func line(of body: CelestialBody,
                            angle: AstroCartoAngle,
                            at date: Date,
                            band: LatitudeBand = .default) -> AstroCartoLine {
        let f = frame(of: body, at: date)
        return line(from: f, angle: angle, band: band)
    }

    /// All four lines for every requested body, from a single ephemeris evaluation per body.
    public static func lines(at date: Date,
                             bodies: [CelestialBody] = CelestialBody.allCases,
                             angles: [AstroCartoAngle] = AstroCartoAngle.allCases,
                             band: LatitudeBand = .default) -> [AstroCartoLine] {
        bodies.flatMap { body -> [AstroCartoLine] in
            let f = frame(of: body, at: date)
            return angles.map { line(from: f, angle: $0, band: band) }
        }
    }

    private static func line(from f: BodyFrame,
                             angle: AstroCartoAngle,
                             band: LatitudeBand) -> AstroCartoLine {
        if angle.isMeridian {
            let lon = longitude(ofEclipticDegree: f.eclipticLongitude, standingOn: angle,
                                obliquity: f.obliquity, latitude: 0, gmst: f.gmst)!
            return AstroCartoLine(body: f.body, angle: angle,
                                  points: band.latitudes.map { AstroCartoPoint(latitude: $0, longitude: lon) },
                                  meridian: lon,
                                  latitudeLimit: nil)
        }
        let points = band.latitudes.compactMap { lat -> AstroCartoPoint? in
            guard let lon = longitude(ofEclipticDegree: f.eclipticLongitude, standingOn: angle,
                                      obliquity: f.obliquity, latitude: lat, gmst: f.gmst)
            else { return nil }
            return AstroCartoPoint(latitude: lat, longitude: lon)
        }
        return AstroCartoLine(body: f.body, angle: angle,
                              points: points, meridian: nil,
                              latitudeLimit: risingLatitudeLimit(declination: f.declination))
    }

    // MARK: - Queries

    /// How far **east** you would have to travel from `place` to stand on the line, in degrees of
    /// longitude, in (-180, 180]. Negative means the line lies to the west.
    ///
    /// Computed exactly at the place's own latitude — not interpolated from `line(...)` samples —
    /// so an app can report an orb without caring what step the map was drawn at.
    /// `nil` when the line does not exist at that latitude.
    public static func longitudeOffset(of body: CelestialBody,
                                       angle: AstroCartoAngle,
                                       at date: Date,
                                       from place: GeoLocation) -> Double? {
        guard let lon = longitude(of: body, standingOn: angle, at: date, latitude: place.latitude)
        else { return nil }
        return AstroMath.norm180(lon - place.longitude)
    }

    /// Geometric altitude of a body above the horizon, degrees. No refraction, no parallax, no
    /// semidiameter: this is the quantity the horizon lines are defined to zero, and mixing in
    /// the ~34′ refraction correction would put the lines somewhere the definition does not.
    public static func altitude(of body: CelestialBody,
                                at date: Date,
                                seenFrom place: GeoLocation) -> Double {
        let f = frame(of: body, at: date)
        let hourAngle = AstroMath.norm180(SiderealTime.ramc(at: date, longitude: place.longitude)
                                          - f.rightAscension)
        return altitude(declination: f.declination, latitude: place.latitude, hourAngle: hourAngle)
    }

    /// Altitude from the pure frame: `sin h = sin φ·sin δ + cos φ·cos δ·cos H`.
    public static func altitude(declination dec: Double,
                                latitude phi: Double,
                                hourAngle h: Double) -> Double {
        AstroMath.asind(clampUnit(AstroMath.sind(phi) * AstroMath.sind(dec)
                                  + AstroMath.cosd(phi) * AstroMath.cosd(dec) * AstroMath.cosd(h)))
    }

    /// Rounding can push a sine one ULP past ±1; `asin` would then hand back NaN and poison a
    /// whole line. Clamp at the one place all of them go through.
    private static func clampUnit(_ x: Double) -> Double { min(1, max(-1, x)) }
}
