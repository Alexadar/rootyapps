import Foundation

/// When a body crosses the horizon at a place — sunrise, sunset, moonrise, moonset.
///
/// ## Why this exists once
///
/// Two functions need it and neither should own it: planetary hours divide sunrise→sunset, and a
/// lunar calendar wants moonrise→moonset. Building it twice is how two copies of one calculation
/// start disagreeing, which this Kit has already been bitten by once (`ChartGeometry` had two
/// definitions that differed about which way the zodiac turns).
///
/// ## How it works, and why nothing new is derived here
///
/// Everything needed already exists. A body's ecliptic longitude comes from `Ephemeris`; converting
/// it to declination is `AstroCartography.equatorial`; and the hour angle at which a body of that
/// declination meets the horizon at a latitude is `AstroCartography.semiDiurnalArc` — the same
/// quantity astrocartography already uses to draw its AC/DC lines. This type only turns that hour
/// angle back into a clock time.
///
/// ## The polar case is not an edge case
///
/// `semiDiurnalArc` returns `nil` when |tan φ · tan δ| > 1 — the body is circumpolar or never rises.
/// That is not a failure to handle; it is the answer. Every result here is optional for that reason,
/// and callers must propagate the absence. Fabricating a time above the Arctic Circle is the failure
/// mode all three of the function documents call out by name.
///
/// ## Iterated, because the body moves
///
/// The naive form computes declination at local noon and solves once. That is fine for the Sun
/// (≈0.4°/day of declination) and badly wrong for the Moon, which can shift declination by 5° in a
/// day and move 13° of longitude while you are solving for its own rise. So the solve is repeated
/// with the position recomputed at the estimated event time until it settles — three passes is
/// ample and the loop exits early once the change falls below the tolerance.
public enum RiseSet {

    /// Which horizon crossing.
    public enum Event: Sendable {
        case rise, set
    }

    /// Standard altitude of the body's centre at the moment it is *said* to rise or set, in degrees.
    ///
    /// Not zero, and the difference is not cosmetic — it is about four minutes at mid-latitudes.
    ///
    /// - Sun: **−0.8333°**, which is refraction at the horizon (34′) plus the semidiameter (16′),
    ///   because sunrise is conventionally the upper limb touching the horizon, not the centre.
    /// - Moon: **+0.125°**, Meeus's simplification of refraction minus the Moon's much larger
    ///   parallax, which lifts it rather than depressing it.
    /// - Anything else: **−0.5667°**, refraction alone; a planet's disc is too small to matter.
    ///
    /// The document for planetary hours says: pick one convention, document it, oracle it. This is
    /// the pick — true rise/set of the upper limb, not civil twilight.
    public static func standardAltitude(of body: CelestialBody) -> Double {
        switch body {
        case .sun:  -0.8333
        case .moon:  0.125
        default:    -0.5667
        }
    }

    /// The local hour angle at which `body` sits at its standard altitude, or nil when it never
    /// does — circumpolar, or never rising, at this latitude on this date.
    ///
    /// This generalises `semiDiurnalArc`, which assumes the geometric horizon (h = 0). Refraction
    /// and semidiameter move the horizon slightly, and at high latitude that shift is the whole
    /// difference between "the Sun rises today" and "it does not".
    public static func hourAngleAtHorizon(declination dec: Double,
                                          latitude phi: Double,
                                          altitude h0: Double) -> Double? {
        guard abs(phi) < 90 else { return nil }
        let cosH = (AstroMath.sind(h0) - AstroMath.sind(phi) * AstroMath.sind(dec))
                 / (AstroMath.cosd(phi) * AstroMath.cosd(dec))
        guard cosH.isFinite, abs(cosH) <= 1 else { return nil }
        return acos(cosH) * AstroMath.deg
    }

    /// The instant `body` rises or sets, for the civil day containing `date` in `timeZone`.
    ///
    /// Returns nil when the event does not occur that day — the honest answer at high latitude, and
    /// also the ordinary answer for the Moon, which genuinely fails to rise on roughly one day a
    /// month everywhere because its day is ~24h50m long.
    public static func time(of event: Event,
                            body: CelestialBody,
                            on date: Date,
                            at location: GeoLocation,
                            timeZone: TimeZone) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let dayStart = cal.startOfDay(for: date)
        // The civil day is NOT always 86 400 s. Where daylight saving is observed it is 23 h on the
        // spring-forward day and 25 h on the fall-back day, so the bounds are asked of the calendar
        // rather than assumed. Both directions were observed failing before this: a 25-hour day
        // dropped a moonrise that genuinely fell inside it, and a 23-hour day reported a rise from
        // the following morning as if it belonged to that day.
        //
        // A leap day needs nothing here — 29 February is an ordinary 24-hour day, and every instant
        // in this Kit is absolute time, so Foundation places it without help.
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)
                     ?? dayStart.addingTimeInterval(86_400)
        let h0 = standardAltitude(of: body)

        /// Local hour angle of the body, degrees in (−180, 180], at a fraction `m` through the day.
        /// Negative means "east of the meridian, not yet transited".
        func localHourAngle(atFraction m: Double) -> (h: Double, limit: Double?) {
            let t = dayStart.addingTimeInterval(m * 86_400)
            let eps = SiderealTime.meanObliquity(at: t)
            let lambda = Ephemeris.longitude(of: body, at: t)
            let (ra, dec) = AstroCartography.equatorial(eclipticLongitude: lambda, obliquity: eps)
            let lst = SiderealTime.localMeanSiderealTime(at: t, longitude: location.longitude)
            return (AstroMath.norm180(lst - ra),
                    hourAngleAtHorizon(declination: dec, latitude: location.latitude, altitude: h0))
        }

        // Meeus, ch. 15: solve for the *fraction of the day* at which the body reaches the horizon,
        // iterating that fraction rather than jumping to an absolute instant.
        //
        // The distinction matters and cost a debugging round. Re-solving from the current absolute
        // guess re-anchors on whichever transit is nearest to *it*, so an evening moonrise pulls the
        // next estimate past midnight, onto tomorrow's transit, and the iteration oscillates between
        // two days and lands outside the one being asked about. It silently lost seven moonrises a
        // month in London — every rise falling roughly between 18:00 and midnight.
        /// Converge on the crossing nearest `seed`, as a fraction of 86 400 s past local midnight.
        func solve(from seed: Double) -> Double? {
            var m = seed
            for _ in 0..<5 {
                let (h, limit) = localHourAngle(atFraction: m)
                guard let h0Limit = limit else { return nil }   // circumpolar or never rises
                // Where we want the hour angle to be: −H at rise, +H at set.
                let want = event == .rise ? -h0Limit : h0Limit
                let correction = AstroMath.norm180(want - h) / 360.0
                m += correction
                if abs(correction) < 1e-7 { break }             // ~0.01 s
            }
            return m
        }

        // Three seeds, not one. Each converges to whichever crossing is nearest it, and a crossing
        // landing outside the civil day is discarded rather than reported — that absence is a real
        // and ordinary answer for the Moon, which skips a rise about once a month at every latitude
        // because its day runs ~50 minutes longer than the solar one.
        //
        // The third seed is what a single mid-day solve cannot reach: a 25-hour fall-back day is
        // longer than the 24 h 50 m lunar day, so it can contain TWO moonrises. The earliest is
        // returned; a single solve seeded at noon would silently see only one of them.
        let candidates = [0.25, 0.75, 1.25]
            .compactMap(solve)
            .map { dayStart.addingTimeInterval($0 * 86_400) }
            .filter { $0 >= dayStart && $0 < dayEnd }

        return candidates.min()
    }

    /// Sunrise and sunset for a civil day, or nil for either when it does not occur.
    public static func sun(on date: Date, at location: GeoLocation,
                           timeZone: TimeZone) -> (rise: Date?, set: Date?) {
        (time(of: .rise, body: .sun, on: date, at: location, timeZone: timeZone),
         time(of: .set,  body: .sun, on: date, at: location, timeZone: timeZone))
    }

    /// Moonrise and moonset for a civil day. Either can legitimately be nil on an ordinary day at
    /// any latitude, because the lunar day runs about 50 minutes longer than the solar one.
    public static func moon(on date: Date, at location: GeoLocation,
                            timeZone: TimeZone) -> (rise: Date?, set: Date?) {
        (time(of: .rise, body: .moon, on: date, at: location, timeZone: timeZone),
         time(of: .set,  body: .moon, on: date, at: location, timeZone: timeZone))
    }
}
