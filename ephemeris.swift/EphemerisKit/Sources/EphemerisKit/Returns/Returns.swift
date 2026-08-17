import Foundation

/// One instant at which a body is exactly on a natal ecliptic longitude.
public struct ReturnEvent: Identifiable, Hashable {
    public let body: CelestialBody
    /// The exact instant of the crossing (UTC).
    public let date: Date
    /// The degree being returned to, normalized to [0, 360).
    public let natalLongitude: Double
    /// The body's longitude at `date`. Equal to `natalLongitude` up to the bisection floor —
    /// exposed rather than assumed so callers (and tests) can audit the root-find.
    public let longitude: Double
    public let retrograde: Bool

    public var id: String { "\(body.rawValue)-\(date.timeIntervalSince1970)" }
    public var sign: ZodiacSign { ZodiacSign.from(longitude: longitude) }

    /// How far the root-find actually landed from the natal degree, in degrees.
    /// Uses `separation`, so it is immune to the 0°/360° wrap: a hit at 359.9999999°
    /// against a natal 0° reads as ~1e-7, not ~360.
    public var residual: Double { AstroMath.separation(longitude, natalLongitude) }
}

/// One *passage* of a body over the natal degree.
///
/// A direct-moving body crosses once. A body that stations while still within its retrograde
/// arc of the degree crosses three times (forward, back, forward) — the astrologer's "triple
/// return". The count is always odd: whatever comes back must first have gone past.
public struct ReturnCycle: Identifiable, Hashable {
    public let body: CelestialBody
    public let natalLongitude: Double
    /// Time-ordered, never empty.
    public let hits: [ReturnEvent]

    public var id: String { "\(body.rawValue)-cycle-\(hits[0].date.timeIntervalSince1970)" }
    public var first: ReturnEvent { hits[0] }
    public var last: ReturnEvent { hits[hits.count - 1] }
    public var isTriple: Bool { hits.count > 1 }
    /// From the first crossing to the last — zero-length for a single-hit cycle.
    public var span: DateInterval { DateInterval(start: first.date, end: last.date) }
}

/// Return charts — the instants a body comes back to a natal ecliptic longitude.
/// Solar return (Sun), lunar return (Moon), Saturn return, and the general case.
///
/// Everything here reduces to one root-find on
///
///     f(t) = norm180( λ_body(t) − λ_natal )
///
/// The `norm180` is load-bearing, not cosmetic. The raw difference `λ_body(t) − λ_natal`
/// carries a 360° cliff at the natal degree itself — precisely where the root is — so a
/// bisector would converge onto the cliff and report a "return" that is a whole turn wrong.
/// Wrapping to (−180, 180] moves the only discontinuity to the antipode, half a circle from
/// every root, where `RootFinding.crossesZero`'s |f| < 90 guard discards it as a wrap instead
/// of accepting it as a crossing. (This package already paid for one copy of the angle maths
/// disagreeing with another; it does not get a second bisector either — `RootFinding.refine`
/// is the only one.)
public enum Returns {

    // MARK: Mean periods

    /// Mean interval between successive returns, in days.
    ///
    /// These are **tropical** (equinox-of-date) periods, because `Ephemeris.longitude` is
    /// tropical: a sidereal period would be ~1 precession-step too long and would slowly walk
    /// the search windows off the true returns (12.3 days per revolution for Saturn).
    ///
    /// Mercury and Venus get the tropical *year*: geocentrically they never leave the Sun's
    /// side, so their mean geocentric motion is the Sun's and they re-cross a fixed degree
    /// about once a year — their 88- and 225-day heliocentric periods are the wrong quantity
    /// here and would size the search window far too small.
    ///
    /// Sources: tropical year and tropical month — Meeus, *Astronomical Algorithms* (2nd ed.),
    /// ch. 27 and ch. 47. Planetary tropical orbit periods — NASA/NSSDC planetary fact sheets.
    public static func meanPeriodDays(_ body: CelestialBody) -> Double {
        switch body {
        case .sun, .mercury, .venus: 365.242190
        case .moon:    27.321582
        case .mars:    686.973
        case .jupiter: 4330.595
        case .saturn:  10746.94
        case .uranus:  30588.740
        case .neptune: 59799.9
        case .pluto:   90463.2
        }
    }

    // MARK: Crossings

    /// Every instant inside `interval` at which `body` sits on `natalLongitude`.
    ///
    /// Daily sampling, like every other finder in this package. That sets the blind spot
    /// honestly: a retrograde dip that crosses the degree and returns inside 24 hours is
    /// invisible, which for the slow bodies means a dip shallower than their daily motion
    /// (~0.13° for Saturn). A crossing landing exactly on `interval.start` is also skipped —
    /// `crossesZero` needs a sign change, and an endpoint zero has no side.
    public static func hits(of body: CelestialBody,
                            to natalLongitude: Double,
                            in interval: DateInterval) -> [ReturnEvent] {
        let target = AstroMath.norm360(natalLongitude)
        func f(_ t: Date) -> Double {
            AstroMath.norm180(Ephemeris.longitude(of: body, at: t) - target)
        }

        var out: [ReturnEvent] = []
        let step = 86_400.0
        var t = interval.start
        var prev = f(t)
        t = t.addingTimeInterval(step)
        while t <= interval.end {
            let cur = f(t)
            if RootFinding.crossesZero(prev, cur) {
                let root = RootFinding.refine(t.addingTimeInterval(-step), t, f)
                out.append(ReturnEvent(body: body,
                                       date: root,
                                       natalLongitude: target,
                                       longitude: Ephemeris.longitude(of: body, at: root),
                                       retrograde: Ephemeris.isRetrograde(body, at: root)))
            }
            prev = cur
            t = t.addingTimeInterval(step)
        }
        return out
    }

    /// The same crossings, grouped into passages.
    ///
    /// Two crossings belong to the same passage when they are closer together than half a mean
    /// period. That threshold is safe by a wide margin in both directions: a triple return
    /// closes inside the retrograde arc (months for Saturn, weeks for Mercury) while successive
    /// passages are a whole period apart, and even the worst geocentric jitter — Venus's ±47°
    /// elongation swing shifting its yearly crossing by ±47 days — leaves adjacent passages
    /// ~270 days apart against a 183-day threshold.
    public static func cycles(of body: CelestialBody,
                              to natalLongitude: Double,
                              in interval: DateInterval) -> [ReturnCycle] {
        let all = hits(of: body, to: natalLongitude, in: interval)
        guard !all.isEmpty else { return [] }
        let gap = meanPeriodDays(body) * 0.5 * 86_400

        var out: [ReturnCycle] = []
        var group: [ReturnEvent] = [all[0]]
        for h in all.dropFirst() {
            if h.date.timeIntervalSince(group[group.count - 1].date) < gap {
                group.append(h)
            } else {
                out.append(ReturnCycle(body: body, natalLongitude: group[0].natalLongitude, hits: group))
                group = [h]
            }
        }
        out.append(ReturnCycle(body: body, natalLongitude: group[0].natalLongitude, hits: group))
        return out
    }

    /// The first crossing strictly after `date`, or `nil` if none inside ~3.6 mean periods.
    ///
    /// Note this is the literal next crossing, retrograde re-crossings included: asked right
    /// after a birth whose Saturn is retrograde, it answers with the re-crossing weeks later,
    /// not the return 29 years out. For "the nth return" use `cycle(_:of:natal:)`, which is
    /// anchored on the mean period and cannot be fooled that way.
    public static func next(_ body: CelestialBody,
                            to natalLongitude: Double,
                            after date: Date) -> ReturnEvent? {
        let window = meanPeriodDays(body) * 1.2 * 86_400
        var start = date
        for _ in 0..<3 {
            let end = start.addingTimeInterval(window)
            // Windows abut rather than overlap: the pair (end − 1 day, end) is tested by this
            // window, and the next one opens at `end`, so no crossing falls between them.
            if let hit = hits(of: body, to: natalLongitude, in: DateInterval(start: start, end: end)).first {
                return hit
            }
            start = end
        }
        return nil
    }

    // MARK: Natal-anchored returns

    /// The `n`-th return passage after `natal` (n ≥ 1), against the body's own natal longitude.
    ///
    /// Anchored on `natal + n · meanPeriod` and taking the passage nearest that anchor, rather
    /// than counting crossings forward. Counting would be wrong twice over: a retrograde body
    /// re-crosses its own degree within months of birth (three "returns" before the first
    /// birthday), and a passage that happens to be a single hit in one cycle and a triple in
    /// the next would renumber everything after it.
    public static func cycle(_ n: Int, of body: CelestialBody, natal: Date) -> ReturnCycle? {
        guard n >= 1 else { return nil }
        let period = meanPeriodDays(body) * 86_400
        let anchor = natal.addingTimeInterval(Double(n) * period)
        // ±0.75 period: wide enough that the target passage is never clipped at an edge even
        // when it drifts (Saturn's geocentric loop moves a passage by up to ~2 months), narrow
        // enough that the nearest-to-anchor pick is never ambiguous.
        let half = period * 0.75
        let window = DateInterval(start: anchor.addingTimeInterval(-half),
                                  end: anchor.addingTimeInterval(half))
        let natalLongitude = Ephemeris.longitude(of: body, at: natal)
        return cycles(of: body, to: natalLongitude, in: window)
            .min { abs($0.first.date.timeIntervalSince(anchor)) < abs($1.first.date.timeIntervalSince(anchor)) }
    }

    /// Solar return for a given age — the birthday chart's exact moment. The Sun never
    /// retrogrades, so the passage is always a single hit.
    public static func solarReturn(natal: Date, age: Int) -> ReturnEvent? {
        cycle(age, of: .sun, natal: natal)?.first
    }

    /// The `index`-th lunar return (~27.32 days apart). The Moon's apparent longitude is
    /// always direct, so this too is a single hit.
    public static func lunarReturn(natal: Date, index: Int) -> ReturnEvent? {
        cycle(index, of: .moon, natal: natal)?.first
    }

    /// The classic Saturn return (~29.4 years). `ordinal` 1 is the first, 2 the second.
    /// Returns the whole passage: when Saturn stations inside its own natal degree the
    /// "return" is three exact hits spread over months, and collapsing that to one date
    /// throws away the part everyone actually asks about.
    public static func saturnReturn(natal: Date, ordinal: Int = 1) -> ReturnCycle? {
        cycle(ordinal, of: .saturn, natal: natal)
    }
}
