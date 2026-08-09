import Foundation

/// A secondary-progressed chart: the *natal computation re-run at a later ephemeris instant*.
///
/// Nothing here is a new astronomy model — that is the whole point. Every longitude in
/// `positions` is `Ephemeris.longitude(of:at:)` evaluated at `progressedDate`, so the chart
/// can never drift away from the engine that produced the natal chart.
public struct ProgressedChart: Hashable {
    /// The natal instant the progression is measured from.
    public let birth: Date
    /// The calendar instant the chart is *for* (the person's "now").
    public let target: Date
    /// The ephemeris instant actually evaluated — `birth + ageYears` **days**.
    public let progressedDate: Date
    /// Elapsed tropical years between `birth` and `target`. Negative before birth (converse).
    public let ageYears: Double
    /// Progressed body positions. `speed` is degrees per ephemeris *day*, which under the
    /// day-for-a-year map is also degrees per *year of life* — the rate the chart appears to
    /// move at when the user scrubs a birthday slider.
    public let positions: [BodyPosition]
    /// Progressed angles, present only when the caller supplied a birth place. The natal
    /// time-of-day is carried inside `progressedDate`, so this is again just the natal
    /// computation re-run — no separate MC-directing convention is applied.
    public let angles: ChartAngles?

    public func position(_ body: CelestialBody) -> BodyPosition? {
        positions.first { $0.body == body }
    }
}

/// A solar-arc directed chart: every natal position advanced by one single arc.
public struct DirectedChart: Hashable {
    public let birth: Date
    public let target: Date
    /// The arc the progressed Sun has travelled from the natal Sun, in degrees.
    /// Signed and *unwrapped* — see `Progressions.solarArc(birth:on:)`.
    public let arc: Double
    /// Natal positions, kept so callers (and tests) can see what the arc was applied to.
    public let natalPositions: [BodyPosition]
    /// Directed positions: `norm360(natal + arc)` for every body.
    public let positions: [BodyPosition]

    public func position(_ body: CelestialBody) -> BodyPosition? {
        positions.first { $0.body == body }
    }
}

/// Secondary progressions and solar arc directions.
///
/// Both techniques are *symbolic* time maps, not new physics: they reuse the existing ephemeris
/// at a shifted instant. Because the shift is the only new idea, the date map is exposed on its
/// own (`progressedDate` / `calendarDate`) — it is the part that is worth testing directly, and
/// the part callers want when they ask "which ephemeris day is my 41st birthday?".
///
/// **Secondary progression** — one *day* after birth stands for one *year* of life. The
/// fractional part uses the mean tropical year rather than a calendar year, so the map is
/// uniform: no leap-day discontinuity, and no jump when a birthday crosses a year boundary.
///
/// **Solar arc direction** — take the arc the progressed Sun has covered and add it to every
/// natal position. By construction the Sun's own directed position *is* its progressed
/// position; the other bodies simply inherit the Sun's rate.
public enum Progressions {

    // MARK: The day-for-a-year map

    /// Mean tropical year in days (Meeus, *Astronomical Algorithms* 2nd ed., ch. 27, at J2000).
    /// The tropical year — not the sidereal or the calendar year — because the progressed Sun
    /// is measured against the tropical zodiac it is defined in.
    public static let tropicalYearDays = 365.242190

    /// Mean solar motion, degrees per day (360° / tropical year ≈ 0.9856°/d).
    /// Used *only* to unwrap the solar arc past 360°, never as a position.
    public static let meanSolarMotion = 360.0 / tropicalYearDays

    private static let secondsPerDay = 86_400.0

    /// Elapsed tropical years from `birth` to `target`. Negative before birth.
    public static func age(birth: Date, on target: Date) -> Double {
        target.timeIntervalSince(birth) / (tropicalYearDays * secondsPerDay)
    }

    /// The ephemeris instant whose sky *is* the progressed chart: `birth + ageYears` days.
    public static func progressedDate(birth: Date, age: Double) -> Date {
        birth.addingTimeInterval(age * secondsPerDay)
    }

    /// The ephemeris instant standing in for `target`.
    public static func progressedDate(birth: Date, on target: Date) -> Date {
        progressedDate(birth: birth, age: age(birth: birth, on: target))
    }

    /// Inverse map: the calendar instant a progressed ephemeris instant stands for.
    /// Exact inverse of `progressedDate(birth:on:)` — one day back becomes one year back.
    public static func calendarDate(birth: Date, progressedDate p: Date) -> Date {
        birth.addingTimeInterval(p.timeIntervalSince(birth) * tropicalYearDays)
    }

    // MARK: Positions

    /// Body positions straight from the engine. Public because the *definition* of a
    /// progressed chart is "these, at the progressed date" — a caller comparing the two must be
    /// able to call the same function, not a lookalike.
    public static func positions(at date: Date,
                                 bodies: [CelestialBody] = CelestialBody.allCases) -> [BodyPosition] {
        bodies.map {
            BodyPosition(body: $0,
                         longitude: AstroMath.norm360(Ephemeris.longitude(of: $0, at: date)),
                         speed: Ephemeris.dailyMotion(of: $0, at: date))
        }
    }

    /// The secondary-progressed chart for `target`.
    public static func secondary(birth: Date,
                                 on target: Date,
                                 location: GeoLocation? = nil,
                                 bodies: [CelestialBody] = CelestialBody.allCases) -> ProgressedChart {
        let a = age(birth: birth, on: target)
        let p = progressedDate(birth: birth, age: a)
        return ProgressedChart(birth: birth,
                               target: target,
                               progressedDate: p,
                               ageYears: a,
                               positions: positions(at: p, bodies: bodies),
                               angles: location.map { Houses.angles(at: p, location: $0) })
    }

    // MARK: Solar arc

    /// The solar arc: progressed Sun − natal Sun, **signed and unwrapped**.
    ///
    /// The naive `norm360(progressed − natal)` is wrong twice over. A converse direction
    /// (`target` before birth) would come back as +330° instead of −30°, and past ~365 years of
    /// life the arc genuinely exceeds 360° and would silently fold back to a small angle.
    /// So the arc is resolved around its mean value `age × meanSolarMotion`: the Sun's real
    /// motion never departs from the mean by more than ~2° over any arc we can be handed, so
    /// `norm180` of the residual picks the correct turn unambiguously.
    public static func solarArc(birth: Date, on target: Date) -> Double {
        let a = age(birth: birth, on: target)
        let natal = Ephemeris.longitude(of: .sun, at: birth)
        let progressed = Ephemeris.longitude(of: .sun, at: progressedDate(birth: birth, age: a))
        let mean = a * meanSolarMotion          // `a` years of life = `a` days of ephemeris
        return mean + AstroMath.norm180(progressed - natal - mean)
    }

    /// Apply an arc to a longitude. The only place the 0°/360° wrap is handled, so that
    /// "arc crossed Aries" is one behaviour with one test, not a case in every caller.
    public static func directed(longitude: Double, arc: Double) -> Double {
        AstroMath.norm360(longitude + arc)
    }

    /// The solar-arc directed chart for `target`.
    ///
    /// Every directed body carries the *Sun's* progressed speed, because that is literally the
    /// derivative of its directed longitude with respect to age: the natal position is a
    /// constant and the arc is the only thing moving. A directed Mercury does not retrograde.
    public static func solarArcDirected(birth: Date,
                                        on target: Date,
                                        bodies: [CelestialBody] = CelestialBody.allCases) -> DirectedChart {
        let a = age(birth: birth, on: target)
        let arc = solarArc(birth: birth, on: target)
        let rate = Ephemeris.dailyMotion(of: .sun, at: progressedDate(birth: birth, age: a))
        let natal = positions(at: birth, bodies: bodies)
        let moved = natal.map {
            BodyPosition(body: $0.body,
                         longitude: directed(longitude: $0.longitude, arc: arc),
                         speed: rate)
        }
        return DirectedChart(birth: birth, target: target, arc: arc,
                             natalPositions: natal, positions: moved)
    }
}
