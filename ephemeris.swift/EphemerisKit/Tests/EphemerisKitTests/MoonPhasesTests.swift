import Testing
import Foundation
@testable import EphemerisKit

/// The Moon's phases against Espenak's published catalogue, plus the identities the geometry forces.
///
/// The published comparison is the load-bearing test and the span is the point: 48 phases across
/// 2010–2035. A mean-phase implementation — stepping 29.53 days from a known epoch — reproduces any
/// single date and then drifts by hours, so checking one year would not distinguish it from a
/// correct one. Checking four years a quarter-century apart does.
@Suite("Moon phases")
struct MoonPhasesTests {

    private let zone = TimeZone(secondsFromGMT: 0)!

    /// Finds our instant for a phase near a published one and returns the error in seconds.
    private func error(_ phase: MoonPhases.Phase, near expected: Double) -> TimeInterval? {
        let target = Date(timeIntervalSince1970: expected)
        // Search from five days before: comfortably inside the same lunation, comfortably clear of
        // the neighbouring occurrence of the same phase.
        guard let found = MoonPhases.next(phase, after: target.addingTimeInterval(-5 * 86_400))
        else { return nil }
        return found.date.timeIntervalSince1970 - expected
    }

    // MARK: - Against the published catalogue

    @Test func newAndFullMoonsMatchEspenak() {
        let o = Oracles.require("moonphase-espenak-syzygies")
        for (key, expected) in o.values.sorted(by: { $0.key < $1.key }) {
            let phase: MoonPhases.Phase = key.hasSuffix("new") ? .new : .full
            guard let err = error(phase, near: expected) else {
                Issue.record("no \(phase.rawValue) found near \(key)"); continue
            }
            let detail = "\(key): off by \(String(format: "%.1f", err / 60)) min"
            #expect(o.matches(key, expected + err), "\(detail)")
        }
    }

    @Test func quartersMatchEspenak() {
        let o = Oracles.require("moonphase-espenak-quarters")
        for (key, expected) in o.values.sorted(by: { $0.key < $1.key }) {
            let phase: MoonPhases.Phase = key.hasSuffix("fq") ? .firstQuarter : .lastQuarter
            guard let err = error(phase, near: expected) else {
                Issue.record("no \(phase.rawValue) found near \(key)"); continue
            }
            let detail = "\(key): off by \(String(format: "%.1f", err / 60)) min"
            #expect(o.matches(key, expected + err), "\(detail)")
        }
    }

    /// The property that kills a mean-phase implementation outright: the *interval* between
    /// consecutive new moons is not constant. Asserting the mean matches while the spread is real
    /// is a stronger statement than either alone.
    @Test func lunationsAverageTheSynodicMonthButAreNotEvenlySpaced() {
        let o = Oracles.require("moonphase-synodic-month")
        let year = DateInterval(start: utc(2026, 1, 1), end: utc(2027, 1, 1))
        let news = MoonPhases.phases(in: year).filter { $0.phase == .new }
        #expect(news.count >= 12, "a year holds twelve or thirteen new moons, found \(news.count)")

        let gaps = zip(news, news.dropFirst()).map {
            $1.date.timeIntervalSince($0.date) / 86_400
        }
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        #expect(o.matches("days", mean), "mean lunation \(String(format: "%.4f", mean)) d")

        let spread = (gaps.max() ?? 0) - (gaps.min() ?? 0)
        let why = "true lunations vary by ~0.5 d; a spread of \(String(format: "%.3f", spread)) d suggests mean-phase stepping rather than root-finding"
        #expect(spread > 0.2, "\(why)")
    }

    // MARK: - Construction identities

    /// At each returned instant the elongation is its defining angle. This is what makes the
    /// instants *mean* something rather than merely being close to a published table.
    @Test func elongationIsExactAtEveryReturnedPhase() {
        let year = DateInterval(start: utc(2026, 1, 1), end: utc(2027, 1, 1))
        for event in MoonPhases.phases(in: year) {
            let e = MoonPhases.elongation(at: event.date)
            let off = abs(AstroMath.norm180(e - event.phase.elongation))
            #expect(off < 0.01,
                    "\(event.phase.rawValue) at \(event.date): elongation \(String(format: "%.4f", e))°")
        }
    }

    @Test func illuminationIsZeroAtNewOneAtFullAndHalfAtTheQuarters() {
        let year = DateInterval(start: utc(2026, 1, 1), end: utc(2027, 1, 1))
        for event in MoonPhases.phases(in: year) {
            let k = MoonPhases.illuminatedFraction(at: event.date)
            switch event.phase {
            case .new:   #expect(k < 0.001, "new moon lit \(k)")
            case .full:  #expect(k > 0.999, "full moon lit \(k)")
            case .firstQuarter, .lastQuarter:
                #expect(abs(k - 0.5) < 0.001, "\(event.phase.rawValue) lit \(k)")
            }
        }
    }

    /// Never leaves [0,1], anywhere in the month — including at the wrap, where a naive formula
    /// can go slightly negative and a UI then draws a disc with negative width.
    @Test func illuminationStaysInRangeAllYear() {
        var t = utc(2026, 1, 1)
        let end = utc(2027, 1, 1)
        while t < end {
            let k = MoonPhases.illuminatedFraction(at: t)
            #expect(k >= 0 && k <= 1, "illumination \(k) at \(t)")
            t = t.addingTimeInterval(6 * 3600)
        }
    }

    /// New → first quarter → full → last quarter, strictly, with no skips. A root-finder that
    /// missed a crossing would still return a plausible-looking list; this catches it.
    @Test func phasesCycleInOrderWithoutSkipping() {
        let year = DateInterval(start: utc(2026, 1, 1), end: utc(2027, 1, 1))
        let events = MoonPhases.phases(in: year)
        let order: [MoonPhases.Phase] = [.new, .firstQuarter, .full, .lastQuarter]
        for (a, b) in zip(events, events.dropFirst()) {
            let i = order.firstIndex(of: a.phase)!
            #expect(b.phase == order[(i + 1) % 4],
                    "\(a.phase.rawValue) at \(a.date) is followed by \(b.phase.rawValue)")
            #expect(b.date > a.date, "phases must be strictly increasing in time")
        }
    }

    @Test func waxingAndWaningFollowTheElongation() {
        let year = DateInterval(start: utc(2026, 1, 1), end: utc(2027, 1, 1))
        let events = MoonPhases.phases(in: year)
        for e in events {
            // Half a day past the phase, the state is unambiguous.
            let after = e.date.addingTimeInterval(43_200)
            switch e.phase {
            case .new, .firstQuarter: #expect(MoonPhases.isWaxing(at: after))
            case .full, .lastQuarter: #expect(!MoonPhases.isWaxing(at: after))
            }
        }
        #expect(events.count >= 48, "a year holds ~49 principal phases, found \(events.count)")
    }

    /// The label must name the phase just *passed*, never the one approaching — a calendar that
    /// reads "Full Moon" three days early is wrong in the way users notice immediately.
    @Test func currentPhaseNamesThePrecedingPhaseNotTheNearest() {
        guard let full = MoonPhases.next(.full, after: utc(2026, 3, 1)) else {
            Issue.record("expected a full moon in March 2026"); return
        }
        #expect(MoonPhases.currentPhase(at: full.date.addingTimeInterval(3600)) == .full)
        // A day before it, the Moon is still in the first-quarter stretch.
        #expect(MoonPhases.currentPhase(at: full.date.addingTimeInterval(-86_400)) == .firstQuarter)
    }

    // MARK: - Rise and set

    /// Moonrise and moonset genuinely fail to occur on some ordinary days at any latitude, because
    /// the lunar day is ~24h50m long. The absence must be reported, never papered over — so this
    /// asserts both that most days have both, and that some day in the month has a gap.
    @Test func moonriseIsAbsentOnSomeOrdinaryDays() {
        let london = GeoLocation(latitude: 51.5074, longitude: -0.1278)
        var missing = 0, present = 0
        for day in 0..<30 {
            let d = utc(2026, 3, 1).addingTimeInterval(Double(day) * 86_400)
            let rs = MoonPhases.riseSet(on: d, at: london, timeZone: zone)
            if rs.rise == nil { missing += 1 } else { present += 1 }
        }
        #expect(present >= 26, "the Moon rises on most days; got \(present)/30")
        let why = "over a month the Moon must skip at least one day's rise — a run with none suggests a fabricated time rather than a reported absence"
        #expect(missing >= 1, "\(why)")
    }

    @Test func polarLatitudesReportAbsenceRatherThanAFabricatedTime() {
        let tromso = GeoLocation(latitude: 69.6496, longitude: 18.9560)
        // Around midsummer the Moon stays below the horizon for days on end at this latitude.
        var missing = 0
        for day in 0..<20 {
            let d = utc(2026, 6, 10).addingTimeInterval(Double(day) * 86_400)
            if MoonPhases.riseSet(on: d, at: tromso, timeZone: zone).rise == nil { missing += 1 }
        }
        #expect(missing >= 2, "expected several riseless days inside the Arctic Circle, got \(missing)")
    }

    // MARK: - The display snapshot

    /// `Snapshot` is what the widget, the calendar and the notification scheduler all read, so its
    /// day arithmetic is load-bearing in three places at once.
    @Test func snapshotAgreesWithTheFunctionsItAggregates() {
        var t = utc(2026, 1, 1)
        let end = utc(2026, 4, 1)
        while t < end {
            let s = MoonPhases.snapshot(at: t)
            #expect(s.illumination == MoonPhases.illuminatedFraction(at: t))
            #expect(s.waxing == MoonPhases.isWaxing(at: t))
            #expect(s.phase == MoonPhases.currentPhase(at: t))
            #expect(s.percent >= 0 && s.percent <= 100, "percent \(s.percent)")
            t = t.addingTimeInterval(7 * 3600)
        }
    }

    /// The count must never read zero, and never count a past event. Truncation would print
    /// "full in 0 d" for the whole final day, which is the one day a user is most likely to look.
    @Test func daysUntilNeverReturnsZeroAndIgnoresThePast() {
        let now = utc(2026, 3, 1)
        let s = MoonPhases.snapshot(at: now)

        #expect(s.days(until: nil) == nil)
        #expect(s.days(until: now) == nil, "an event at this instant is not upcoming")
        #expect(s.days(until: now.addingTimeInterval(-3600)) == nil, "past events do not count")

        // Anything strictly in the future is at least one day away, however close.
        for seconds in [1.0, 60, 3600, 86_399] {
            let d = s.days(until: now.addingTimeInterval(seconds))
            #expect(d == 1, "\(seconds) s ahead should read 1 d, got \(d.map(String.init) ?? "nil")")
        }
        #expect(s.days(until: now.addingTimeInterval(86_401)) == 2)
    }

    /// `soonest` must pick the nearer of the two, and one of them always exists — a widget with no
    /// line to show is the empty state this surface is supposed to be incapable of.
    @Test func soonestPicksTheNearerEventAndAlwaysExists() {
        var t = utc(2026, 1, 1)
        let end = utc(2027, 1, 1)
        while t < end {
            let s = MoonPhases.snapshot(at: t)
            guard let soonest = s.soonest else {
                Issue.record("no upcoming full or new moon at \(t)"); t = t.addingTimeInterval(86_400); continue
            }
            let f = s.days(until: s.nextFull) ?? Int.max
            let n = s.days(until: s.nextNew) ?? Int.max
            #expect(soonest.days == Swift.min(f, n))
            #expect(soonest.phase == (f <= n ? .full : .new))
            // Never more than a synodic month away.
            #expect(soonest.days <= 30, "\(soonest.days) d at \(t)")
            t = t.addingTimeInterval(86_400)
        }
    }
}
