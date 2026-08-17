import Foundation

/// The Moon's phases, and the derived values a lunar calendar needs.
///
/// ## Relationship to `Lunations`
///
/// `Lunations` already found new and full moons for the general event timeline, and still does —
/// this does not replace it. What it adds is everything a phase-focused surface needs and an event
/// timeline does not: the **quarters**, the **illuminated fraction** at an arbitrary instant, and
/// whether the Moon is waxing or waning. All four phases come from the same root-find on Sun–Moon
/// elongation that was already there; only the target angle differs.
///
/// ## True phase, never mean phase
///
/// The instants are found by refining the actual elongation to zero, not by stepping a mean synodic
/// month of 29.53 days from a known epoch. A mean-phase approximation passes a spot check against
/// one published date and then drifts by hours across a year, because the Moon's true motion varies
/// with its eccentric orbit. Agreement with published times across a **decade** is the property the
/// oracle checks, and it is the one thing a mean-phase implementation cannot fake.
public enum MoonPhases {

    /// The four principal phases, by Sun–Moon elongation.
    public enum Phase: String, CaseIterable, Identifiable, Sendable {
        case new, firstQuarter, full, lastQuarter

        public var id: String { rawValue }

        /// Elongation of the Moon from the Sun at this phase, degrees.
        public var elongation: Double {
            switch self {
            case .new:          0
            case .firstQuarter: 90
            case .full:         180
            case .lastQuarter:  270
            }
        }

        public var symbol: String {
            switch self {
            case .new:          "🌑"
            case .firstQuarter: "🌓"
            case .full:         "🌕"
            case .lastQuarter:  "🌗"
            }
        }
    }

    /// A phase occurring at an instant.
    public struct Event: Identifiable, Hashable, Sendable {
        public let phase: Phase
        public let date: Date
        /// Where the Moon was, so a caller can name the sign without recomputing.
        public let moonLongitude: Double

        public var sign: ZodiacSign { ZodiacSign.from(longitude: moonLongitude) }
        public var id: String { "\(phase.rawValue)-\(date.timeIntervalSince1970)" }
    }

    /// Mean length of the synodic month, days (Meeus, *Astronomical Algorithms*, ch. 49).
    /// Used only for sanity bounds and step sizing — never to *generate* a phase time.
    public static let meanSynodicMonth = 29.530588

    // MARK: - Finding the phases

    /// Every principal phase in `interval`, in time order.
    ///
    /// Steps daily and refines each crossing, exactly as the other event finders in this Kit do.
    /// A day is comfortably short enough: the Moon's elongation advances about 12.2° per day, so no
    /// two of the four targets can be crossed within one step.
    public static func phases(in interval: DateInterval) -> [Event] {
        var out: [Event] = []
        let step = 86_400.0

        // Signed offset from each target, wrapped to ±180 so a crossing is a sign change.
        func offset(_ phase: Phase, _ at: Date) -> Double {
            AstroMath.norm180(RootFinding.signedSeparation(.moon, .sun, at: at) - phase.elongation)
        }

        for phase in Phase.allCases {
            var t = interval.start
            var previous = offset(phase, t)
            t = t.addingTimeInterval(step)
            while t <= interval.end {
                let current = offset(phase, t)
                if RootFinding.crossesZero(previous, current) {
                    let root = RootFinding.refine(t.addingTimeInterval(-step), t) { offset(phase, $0) }
                    out.append(Event(phase: phase, date: root,
                                     moonLongitude: Ephemeris.longitude(of: .moon, at: root)))
                }
                previous = current
                t = t.addingTimeInterval(step)
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// The next occurrence of `phase` at or after `date`.
    ///
    /// Searches a window of one and a half synodic months, which is enough to contain any single
    /// phase from any starting point with margin.
    public static func next(_ phase: Phase, after date: Date) -> Event? {
        let window = DateInterval(start: date,
                                  end: date.addingTimeInterval(meanSynodicMonth * 1.5 * 86_400))
        return phases(in: window).first { $0.phase == phase && $0.date >= date }
    }

    // MARK: - Continuous state

    /// Elongation of the Moon from the Sun, degrees in [0, 360).
    ///
    /// This is the quantity everything else here is derived from: 0 at new, 180 at full, and
    /// increasing monotonically through the month.
    public static func elongation(at date: Date) -> Double {
        AstroMath.norm360(Ephemeris.longitude(of: .moon, at: date)
                          - Ephemeris.longitude(of: .sun, at: date))
    }

    /// Fraction of the Moon's disc that is lit, 0…1.
    ///
    /// `k = (1 − cos e) / 2`, where `e` is the elongation. Derived from the geometry rather than
    /// interpolated between named phases — interpolation would be wrong in the middle of every
    /// week, and only correct at the four instants anyone would check.
    ///
    /// This ignores the Moon's ecliptic latitude, which shifts the phase angle by at most a few
    /// tenths of a percent of illumination — far below the precision of the underlying position
    /// series, so modelling it would be false precision.
    public static func illuminatedFraction(at date: Date) -> Double {
        let k = (1 - AstroMath.cosd(elongation(at: date))) / 2
        return Swift.min(1, Swift.max(0, k))
    }

    /// Whether the lit fraction is growing. Elongation 0→180 waxes, 180→360 wanes.
    ///
    /// A renderer needs this *and* the observer's hemisphere to draw the crescent facing the right
    /// way; getting that wrong is a visible, frequently-reported defect, so the state is exposed
    /// rather than left to be inferred from a phase name.
    public static func isWaxing(at date: Date) -> Bool { elongation(at: date) < 180 }

    /// The most recent principal phase at or before `date` — what a "current phase" label shows.
    ///
    /// Deliberately the *preceding* phase, not the nearest: a calendar that flips to "Full Moon"
    /// three days early is wrong in the way users notice.
    public static func currentPhase(at date: Date) -> Phase {
        switch elongation(at: date) {
        case ..<90:   .new
        case ..<180:  .firstQuarter
        case ..<270:  .full
        default:      .lastQuarter
        }
    }

    /// The next `limit` occurrences of any phase in `wanted`, in time order.
    ///
    /// `phases(in:)` needs an interval, and a caller who wants "the next eight full and new moons"
    /// has to guess one — guess short and the list comes back incomplete, guess long and every
    /// caller pays for a scan it did not need. This grows the window instead, a synodic month at a
    /// time, and stops as soon as it has enough.
    ///
    /// Used by the notification scheduler, which must respect a hard cap on pending notifications
    /// and therefore asks for an exact count rather than a date range.
    public static func upcoming(_ wanted: Set<Phase>, from date: Date, limit: Int) -> [Event] {
        guard limit > 0, !wanted.isEmpty else { return [] }
        var out: [Event] = []
        var months = 2.0
        // Bounded so a caller asking for something unreachable cannot spin: each pass roughly
        // doubles the horizon, so this covers decades long before it gives up.
        while out.count < limit, months < 1_024 {
            let end = date.addingTimeInterval(months * meanSynodicMonth * 86_400)
            out = phases(in: DateInterval(start: date, end: end))
                .filter { wanted.contains($0.phase) && $0.date > date }
            if out.count >= limit { break }
            months *= 2
        }
        return Array(out.prefix(limit))
    }

    // MARK: - Everything a display needs, in one read

    /// The full lunar state at an instant.
    ///
    /// Exists because three surfaces need exactly this set — the widget, the month calendar and the
    /// notification scheduler — and each computing it separately is how one calculation acquires
    /// two definitions. `ChartGeometry` already taught this repo that lesson once, with two
    /// disagreeing answers about which way the zodiac turns.
    ///
    /// Building it costs four position lookups, so callers should hold one rather than ask for the
    /// pieces individually.
    public struct Snapshot: Hashable, Sendable {
        public let date: Date
        /// 0…1.
        public let illumination: Double
        public let waxing: Bool
        /// The phase most recently *passed*, never the one approaching.
        public let phase: Phase
        public let nextFull: Date?
        public let nextNew: Date?

        /// Illumination as whole percent, 0…100.
        public var percent: Int { Int((illumination * 100).rounded()) }

        /// Whole days from this instant until `target`, rounded **up**, or nil when `target` is nil
        /// or already past.
        ///
        /// Rounding up and flooring at 1 is deliberate: a UI saying "full in 0 days" is nonsense,
        /// and truncation produces it for the whole final day before the event. The event's own day
        /// reads "full in 1 d" right up to the instant, then the count moves to the next occurrence.
        public func days(until target: Date?) -> Int? {
            guard let target else { return nil }
            let seconds = target.timeIntervalSince(date)
            guard seconds > 0 else { return nil }
            return Swift.max(1, Int((seconds / 86_400).rounded(.up)))
        }

        /// Whichever of the next full or new moon comes first, with its day count — the single most
        /// useful thing a glanceable surface can show, and one of the two always exists.
        public var soonest: (phase: Phase, days: Int)? {
            let f = days(until: nextFull)
            let n = days(until: nextNew)
            switch (f, n) {
            case let (f?, n?): return f <= n ? (.full, f) : (.new, n)
            case let (f?, nil): return (.full, f)
            case let (nil, n?): return (.new, n)
            default: return nil
            }
        }
    }

    /// The lunar state at `date`.
    public static func snapshot(at date: Date) -> Snapshot {
        Snapshot(date: date,
                 illumination: illuminatedFraction(at: date),
                 waxing: isWaxing(at: date),
                 phase: currentPhase(at: date),
                 nextFull: next(.full, after: date)?.date,
                 nextNew: next(.new, after: date)?.date)
    }

    // MARK: - Rise and set

    /// Moonrise and moonset for a civil day, either of which can legitimately be absent.
    ///
    /// Missing values here are ordinary, not polar-only: the lunar day runs about fifty minutes
    /// longer than the solar one, so roughly once a month the Moon fails to rise (or set) within a
    /// given calendar day at any latitude. Reporting the absence is correct; substituting a
    /// neighbouring day's time is the bug.
    public static func riseSet(on date: Date, at location: GeoLocation,
                               timeZone: TimeZone) -> (rise: Date?, set: Date?) {
        RiseSet.moon(on: date, at: location, timeZone: timeZone)
    }
}
