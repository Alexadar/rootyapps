import Foundation

/// What a chart can still say when the birth time is unknown.
///
/// ## Why this exists
///
/// A chart with no birth time is not a chart with a birth time of noon. The app already refuses to
/// pretend otherwise for houses and angles — they are omitted with an explanation rather than
/// computed from an assumed midday. But *positions* are currently reported as single values, and
/// for one body that is nearly as dishonest: the Moon moves about 13° per day, so an untimed chart
/// pins it only to within roughly half a sign. A synastry orb of "1.4°" computed from noon is a
/// number the data does not support.
///
/// So the same principle extends downward: compute what the day allows, state the range, and never
/// present a range as a point. This type is what lets a view say `RANGE 0.2°–7.9°` instead of a
/// confident lie.
///
/// ## Why sampling rather than endpoints
///
/// The obvious implementation takes the value at 00:00 and at 24:00 and calls that the range. It is
/// wrong twice over. A planet can station within the day — turning retrograde mid-day puts the
/// extremum in the interior, not at either end — and any body can cross 0° Aries, where a naive
/// min/max over wrapped longitudes reports a span of ~360° for a body that barely moved. Sampling
/// with an unwrapped series handles both without special cases.
public enum Uncertainty {

    /// Samples across an unknown day: every fifteen minutes, inclusive of both ends.
    ///
    /// Chosen against the fastest thing being measured. The Moon covers ~13.2°/day, so 15-minute
    /// steps resolve it to ~0.14° — an order of magnitude finer than the arcminute the UI prints,
    /// so the reported bound is limited by the ephemeris rather than by this sampling.
    public static let samplesPerDay = 97

    // MARK: - The unknown day

    /// The civil day the birth fell on, in the chart's own zone.
    ///
    /// The zone matters and is not cosmetic: "some time on 9 September 1968 in London" is a
    /// different 24 hours from the same date in Tokyo, and using UTC would slide the window by up
    /// to half a day and quietly change which signs the Moon could have occupied.
    ///
    /// An unresolvable zone identifier falls back to UTC rather than to the device's current zone —
    /// a wrong-but-fixed window is inspectable, while one that changes with the reader's location
    /// makes the same chart report different ranges on different devices.
    public static func unknownDay(around instant: Date, timeZoneID: String) -> DateInterval {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 0)!
        let start = cal.startOfDay(for: instant)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    /// The instants sampled across `interval`, both ends included.
    public static func samples(across interval: DateInterval) -> [Date] {
        let n = max(2, samplesPerDay)
        let step = interval.duration / Double(n - 1)
        return (0..<n).map { interval.start.addingTimeInterval(step * Double($0)) }
    }

    // MARK: - Longitude across an unknown day

    /// The span of ecliptic longitude a body could have occupied, as a start degree and an extent.
    ///
    /// Expressed as (from, extent) rather than (min, max) because the arc can straddle 0° Aries,
    /// where `max` would be numerically smaller than `min`. `from` is where the arc begins going
    /// anticlockwise; `extent` is how far it runs, always ≥ 0.
    public struct Arc: Hashable, Sendable {
        public let from: Double
        public let extent: Double

        public init(from: Double, extent: Double) {
            self.from = AstroMath.norm360(from)
            self.extent = max(0, extent)
        }

        public var to: Double { AstroMath.norm360(from + extent) }

        /// True when the arc is wide enough that presenting a single degree would misinform.
        /// One degree is the threshold: below it the printed degree-and-minute is stable enough
        /// that a range adds noise rather than honesty.
        public var isWide: Bool { extent >= 1.0 }
    }

    /// Where a body could have been, across an unknown day.
    ///
    /// The series is unwrapped before taking extremes — each sample is shifted by whole turns to
    /// sit within 180° of its predecessor — so a body crossing 0° Aries yields the small arc it
    /// actually travelled instead of the ~360° a wrapped comparison would report.
    public static func longitudeArc(of body: CelestialBody, across interval: DateInterval) -> Arc {
        let times = samples(across: interval)
        var unwrapped: [Double] = []
        unwrapped.reserveCapacity(times.count)
        for t in times {
            let raw = Ephemeris.longitude(of: body, at: t)
            guard let previous = unwrapped.last else { unwrapped.append(raw); continue }
            unwrapped.append(previous + AstroMath.norm180(raw - previous))
        }
        let lo = unwrapped.min() ?? 0
        let hi = unwrapped.max() ?? 0
        return Arc(from: lo, extent: hi - lo)
    }

    /// Every zodiac sign the body could have occupied on an unknown day.
    ///
    /// Usually one. Two when the arc crosses a cusp — which for the Moon happens on roughly two
    /// days in nine, and is exactly when a dignity score computed from a single assumed sign would
    /// be confidently wrong. Returned in the order travelled, so the caller can present them as
    /// "either / or" rather than as a set.
    public static func signCandidates(of body: CelestialBody,
                                      across interval: DateInterval) -> [ZodiacSign] {
        let arc = longitudeArc(of: body, across: interval)
        // Walk the arc in 30° steps from its start, collecting each sign entered. Stepping rather
        // than sampling again keeps this exact at the boundary: a sign is included when the arc
        // reaches it, not when a sample happens to land in it.
        var signs: [ZodiacSign] = [ZodiacSign.from(longitude: arc.from)]
        var walked = 30.0 - arc.from.truncatingRemainder(dividingBy: 30)
        while walked <= arc.extent {
            let next = ZodiacSign.from(longitude: arc.from + walked)
            if signs.last != next { signs.append(next) }
            walked += 30
        }
        return signs
    }

    // MARK: - Orb across an unknown day

    /// How close an aspect could have been, across an unknown day.
    ///
    /// `nominal` is the orb at the stored instant — what the app shows today, and what stays on
    /// screen when the range is too narrow to matter. `min`/`max` bound it.
    public struct OrbRange: Hashable, Sendable {
        public let nominal: Double
        public let min: Double
        public let max: Double

        public init(nominal: Double, min: Double, max: Double) {
            self.nominal = nominal
            self.min = Swift.min(min, max)
            self.max = Swift.max(min, max)
        }

        public var span: Double { max - min }

        /// Whether the UI should show `min–max` instead of a single figure. Half a degree: below
        /// that the two ends round to the same displayed value, so a range would be visual noise
        /// implying a precision distinction that is not there.
        public var isRange: Bool { span >= 0.5 }
    }

    /// The orb range for one cross-aspect when one or both charts lack a birth time.
    ///
    /// `movingDay` and `referenceDay` are the unknown days for the two sides; pass nil for a side
    /// whose time is known, and its body is held at `at`. With both nil the result is a degenerate
    /// range equal to the nominal orb, which callers can treat as "no range".
    ///
    /// Both sides are swept together when both are unknown, rather than combining two independent
    /// ranges: the two charts are separate people whose unknown times are unrelated, so the true
    /// bound is over the *product* of the two days. Sweeping the pair as a grid is what gives the
    /// honest outer bound instead of a narrower one that assumes the errors move in step.
    public static func orbRange(type: AspectType,
                                moving: CelestialBody, movingAt: Date, movingDay: DateInterval?,
                                reference: CelestialBody, referenceAt: Date,
                                referenceDay: DateInterval?) -> OrbRange {
        func orb(_ a: Double, _ b: Double) -> Double {
            abs(AstroMath.separation(a, b) - type.angle)
        }
        let nominal = orb(Ephemeris.longitude(of: moving, at: movingAt),
                          Ephemeris.longitude(of: reference, at: referenceAt))

        let movingTimes = movingDay.map(samples(across:)) ?? [movingAt]
        let referenceTimes = referenceDay.map(samples(across:)) ?? [referenceAt]
        guard movingDay != nil || referenceDay != nil else {
            return OrbRange(nominal: nominal, min: nominal, max: nominal)
        }

        let movingLongitudes = movingTimes.map { Ephemeris.longitude(of: moving, at: $0) }
        let referenceLongitudes = referenceTimes.map { Ephemeris.longitude(of: reference, at: $0) }
        var lo = Double.greatestFiniteMagnitude
        var hi = -Double.greatestFiniteMagnitude
        for m in movingLongitudes {
            for r in referenceLongitudes {
                let o = orb(m, r)
                lo = Swift.min(lo, o); hi = Swift.max(hi, o)
            }
        }
        return OrbRange(nominal: nominal, min: lo, max: hi)
    }
}

// MARK: - Cross-aspects that admit their own uncertainty

/// A cross-aspect together with what the unknown birth time does to its orb.
public struct RangedCrossAspect: Identifiable, Hashable, Sendable {
    public let aspect: CrossAspect
    public let orbRange: Uncertainty.OrbRange

    public var id: String { aspect.id }
    /// The UI's cue to draw the `RANGE` tag rather than a single orb.
    public var isRanged: Bool { orbRange.isRange }

    public init(aspect: CrossAspect, orbRange: Uncertainty.OrbRange) {
        self.aspect = aspect
        self.orbRange = orbRange
    }
}

extension SavedChart {

    /// The unknown day this chart's birth fell on, or nil when the time is known.
    public var unknownDay: DateInterval? {
        isTimeKnown ? nil : Uncertainty.unknownDay(around: birthInstant, timeZoneID: timeZoneID)
    }

    /// Signs a body could occupy given what this chart knows. One entry when the time is known.
    ///
    /// This is what lets dignities show both candidate scores instead of picking one: with the
    /// Moon's sign genuinely undetermined, naming a single ruler would be a coin toss presented as
    /// a result.
    public func signCandidates(for body: CelestialBody) -> [ZodiacSign] {
        guard let day = unknownDay else {
            return [ZodiacSign.from(longitude: Ephemeris.longitude(of: body, at: birthInstant))]
        }
        return Uncertainty.signCandidates(of: body, across: day)
    }

    /// Synastry against another chart, with each aspect's orb bounded by whatever either side
    /// leaves unknown.
    ///
    /// Aspect *detection* still runs at the stored instants — which pairs are in aspect is decided
    /// once, from the nominal chart — and the range describes how tight each detected contact
    /// could be. Detecting across the sweep instead would make the list itself flicker with the
    /// assumed time, which is a different and much larger claim than this feature makes.
    public func rangedSynastry(with other: SavedChart,
                               orbFactor: Double = 1.0) -> [RangedCrossAspect] {
        let mine = unknownDay
        let theirs = other.unknownDay
        return synastry(with: other, orbFactor: orbFactor).map { aspect in
            RangedCrossAspect(
                aspect: aspect,
                orbRange: Uncertainty.orbRange(
                    type: aspect.type,
                    moving: aspect.moving, movingAt: birthInstant, movingDay: mine,
                    reference: aspect.reference, referenceAt: other.birthInstant,
                    referenceDay: theirs))
        }
    }

    /// Transits to this chart, bounded the same way. Only the natal side can be uncertain — the
    /// transiting moment is whatever "now" the caller passed, and is exact by construction.
    public func rangedTransits(at date: Date = Date(),
                               orbFactor: Double = 1.0) -> [RangedCrossAspect] {
        let mine = unknownDay
        return transits(at: date, orbFactor: orbFactor).map { aspect in
            RangedCrossAspect(
                aspect: aspect,
                orbRange: Uncertainty.orbRange(
                    type: aspect.type,
                    moving: aspect.moving, movingAt: date, movingDay: nil,
                    reference: aspect.reference, referenceAt: birthInstant, referenceDay: mine))
        }
    }
}
