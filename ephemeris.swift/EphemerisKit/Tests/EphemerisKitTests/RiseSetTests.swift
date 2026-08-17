import Testing
import Foundation
@testable import EphemerisKit

/// The civil-day boundary — the part of rise/set that has nothing to do with astronomy.
///
/// Every other test in this Kit runs in `TimeZone(secondsFromGMT: 0)`, which has no daylight saving
/// and therefore no 23- or 25-hour days. That made a whole class of defect invisible: the solver
/// works in fractions of 86 400 s, and a civil day is only 86 400 s long when the clocks do not
/// move. Both directions were caught failing here before the guard was rewritten to ask the
/// calendar for the day's real bounds:
///
/// - a **25-hour** fall-back day *dropped* a moonrise that genuinely fell inside it, at +24.26 h;
/// - a **23-hour** spring-forward day *reported* a rise at +23.90 h — 00:54 the following morning.
///
/// Leap years are a different question and need no code: 29 February is an ordinary 24-hour day and
/// every instant here is absolute time, so Foundation places it. The test below asserts that rather
/// than assuming it, because "the shared library handles it" is exactly the belief worth checking.
@Suite("Rise/set civil-day boundary")
struct RiseSetTests {

    private let london = GeoLocation(latitude: 51.5074, longitude: -0.1278)
    private var uk: TimeZone { TimeZone(identifier: "Europe/London")! }

    private func cal(_ tz: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = tz; return c
    }

    private func noon(_ y: Int, _ m: Int, _ d: Int, _ tz: TimeZone) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = 12
        return cal(tz).date(from: c)!
    }

    // MARK: - Leap day

    /// Sunrise across 28 Feb → 29 Feb → 1 Mar of a leap year must step smoothly, and the same span
    /// in a non-leap year must step smoothly too. A calendar that mishandled the leap day would show
    /// a discontinuity of many minutes on one side or the other.
    @Test func leapDayIsAnOrdinaryDay() {
        for (year, expectedDays) in [(2023, 2), (2024, 3)] {
            var risings: [Date] = []
            for day in 0..<expectedDays {
                let d = cal(uk).date(byAdding: .day, value: day, to: noon(year, 2, 28, uk))!
                guard let r = RiseSet.sun(on: d, at: london, timeZone: uk).rise else {
                    Issue.record("no sunrise in \(year) at offset \(day)"); continue
                }
                risings.append(r)
            }
            #expect(risings.count == expectedDays)
            // Late February sunrise advances by roughly two minutes a day at this latitude.
            for (a, b) in zip(risings, risings.dropFirst()) {
                let stepMinutes = b.timeIntervalSince(a) / 60 - 24 * 60
                let why = "\(year): sunrise moved \(String(format: "%.1f", stepMinutes)) min/day"
                #expect(stepMinutes < 0 && stepMinutes > -6, "\(why)")
            }
        }
        // And the leap day itself exists and lands where it should.
        let leap = RiseSet.sun(on: noon(2024, 2, 29, uk), at: london, timeZone: uk)
        #expect(leap.rise != nil && leap.set != nil, "29 February 2024 must have a sunrise and sunset")
    }

    // MARK: - Daylight saving

    /// The invariant that makes the whole thing safe: whatever is returned for a civil day must lie
    /// inside that civil day, on every day of a year in a zone that observes daylight saving.
    ///
    /// Swept over longitude as well as date, because the failure only appears when the crossing sits
    /// within an hour of midnight — which, for the Moon, happens somewhere on Earth every day.
    @Test func everyReportedCrossingLiesInsideItsOwnCivilDay() {
        let c = cal(uk)
        var checked = 0
        for lonI in stride(from: -180, through: 175, by: 15) {
            let loc = GeoLocation(latitude: 51.5, longitude: Double(lonI))
            // Both transition days plus their neighbours, in both directions.
            for base in [noon(2026, 3, 28, uk), noon(2026, 10, 24, uk)] {
                for day in 0..<3 {
                    let d = c.date(byAdding: .day, value: day, to: base)!
                    let start = c.startOfDay(for: d)
                    let end = c.date(byAdding: .day, value: 1, to: start)!
                    for body in [CelestialBody.sun, .moon] {
                        for event in [RiseSet.Event.rise, .set] {
                            guard let t = RiseSet.time(of: event, body: body, on: d,
                                                       at: loc, timeZone: uk) else { continue }
                            checked += 1
                            let off = t.timeIntervalSince(start) / 3600
                            let why = "\(body.name) \(event) lon \(lonI): +\(String(format: "%.2f", off)) h "
                                    + "into a \(Int(end.timeIntervalSince(start) / 3600)) h day"
                            #expect(t >= start && t < end, "\(why)")
                        }
                    }
                }
            }
        }
        #expect(checked > 300, "expected a broad sweep, only checked \(checked) crossings")
    }

    /// A 25-hour day is longer than the 24 h 50 m lunar day, so it can hold a crossing past the
    /// +24 h mark — which a solver that stops at a fraction of 1.0 cannot express. Verified against
    /// a longitude where that crossing actually occurs.
    @Test func aTwentyFiveHourDayKeepsACrossingPastTwentyFourHours() {
        let c = cal(uk)
        let d = noon(2026, 10, 25, uk)
        let start = c.startOfDay(for: d)
        let end = c.date(byAdding: .day, value: 1, to: start)!
        #expect(end.timeIntervalSince(start) == 25 * 3600, "25 Oct 2026 must be a 25-hour day in the UK")

        let loc = GeoLocation(latitude: 51.5, longitude: -100)
        guard let rise = RiseSet.time(of: .rise, body: .moon, on: d, at: loc, timeZone: uk) else {
            Issue.record("moonrise dropped from a 25-hour day — the crossing is inside it"); return
        }
        let off = rise.timeIntervalSince(start) / 3600
        let why = "expected a crossing beyond +24 h inside the long day, got +\(String(format: "%.2f", off)) h"
        #expect(off > 24 && off < 25, "\(why)")
    }

    /// The mirror image: on a 23-hour day the last hour does not exist, and a crossing that would
    /// have fallen there belongs to the next morning. Reporting it is the bug.
    @Test func aTwentyThreeHourDayRejectsTheHourItDoesNotHave() {
        let c = cal(uk)
        let d = noon(2026, 3, 29, uk)
        let start = c.startOfDay(for: d)
        #expect(c.date(byAdding: .day, value: 1, to: start)!.timeIntervalSince(start) == 23 * 3600,
                "29 Mar 2026 must be a 23-hour day in the UK")

        // At this longitude the moonrise solves to ~+23.9 h, which is 00:54 on the 30th.
        let loc = GeoLocation(latitude: 51.5, longitude: -135)
        let rise = RiseSet.time(of: .rise, body: .moon, on: d, at: loc, timeZone: uk)
        if let rise {
            let off = rise.timeIntervalSince(start) / 3600
            Issue.record("reported +\(String(format: "%.2f", off)) h on a 23-hour day")
        }
        #expect(rise == nil)
    }

    /// Planetary hours are built from three separate rise/set solves, so a DST day is where they
    /// would tear: the night of one day must end exactly where the next day's first hour begins.
    @Test func planetaryHoursStayContinuousAcrossADaylightSavingChange() {
        let c = cal(uk)
        for base in [noon(2026, 3, 28, uk), noon(2026, 10, 24, uk)] {
            for day in 0..<2 {
                let d = c.date(byAdding: .day, value: day, to: base)!
                guard let today = PlanetaryHours.hours(startingOn: d, at: london, timeZone: uk),
                      let next = PlanetaryHours.hours(startingOn: c.date(byAdding: .day, value: 1, to: d)!,
                                                      at: london, timeZone: uk)
                else { Issue.record("no hours across the transition"); continue }

                let gap = abs(next[0].start.timeIntervalSince(today[23].end))
                #expect(gap < 1, "hour 24 ends \(gap) s from the next day's hour 1")

                let total = today.reduce(0.0) { $0 + $1.duration }
                let why = "24 hours span \(String(format: "%.1f", total / 3600)) h across a DST day"
                #expect(abs(total - next[0].start.timeIntervalSince(today[0].start)) < 1, "\(why)")
            }
        }
    }
}
