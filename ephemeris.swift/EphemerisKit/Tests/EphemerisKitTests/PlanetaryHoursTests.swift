import Testing
import Foundation
@testable import EphemerisKit

/// Planetary hours — the unequal division of day and night, and the ruler cycle over it.
///
/// The interesting assertions here are the **closures**, not the spot values. There is no published
/// table of hours for arbitrary places, so a test that checked one computed instant against another
/// computed instant would prove nothing. What the definition does pin, exactly, is that the hours
/// tile their intervals with no gap, that the rulers advance without a break at sunset, and that
/// twenty-four of them land on the next weekday's planet. Only a correct implementation closes.
@Suite("Planetary hours")
struct PlanetaryHoursTests {

    /// Named `zone`, not `utc`: TestSupport already exposes a global `utc(y,m,d,…)` date
    /// builder, and a property of the same name shadows it inside this type.
    private let zone = TimeZone(secondsFromGMT: 0)!
    private let london = GeoLocation(latitude: 51.5074, longitude: -0.1278)
    private let equator = GeoLocation(latitude: 0, longitude: 0)

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { utc(y, m, d, 12, 0) }

    // MARK: - The classical tables

    @Test func chaldeanOrderMatchesValens() {
        let oracle = Oracles.require("hours-chaldean-order")
        for (i, body) in PlanetaryHours.chaldean.enumerated() {
            let idx = Double(CelestialBody.allCases.firstIndex(of: body)!)
            #expect(oracle.matches(String(i), idx), "Chaldean position \(i) is \(body.name)")
        }
        #expect(PlanetaryHours.chaldean.count == 7)
    }

    @Test func weekdayRulersMatchTheClassicalAssignment() {
        let oracle = Oracles.require("hours-weekday-rulers")
        for weekday in 1...7 {
            let body = PlanetaryHours.weekdayRuler(weekday)
            let idx = Double(CelestialBody.allCases.firstIndex(of: body)!)
            #expect(oracle.matches(String(weekday), idx),
                    "weekday \(weekday) is ruled by \(body.name)")
        }
    }

    /// The weekday table and the Chaldean cycle are transcribed separately in the corpus, so this
    /// proves they agree rather than assuming it: stepping 24 hours through the 7-cycle advances
    /// exactly 3 places, and three places from any weekday's ruler is the next weekday's ruler.
    /// This identity is the historical reason the week is ordered as it is.
    @Test func twentyFourHoursAdvancesOneWeekday() {
        let o = Oracles.require("hours-weekday-closure-step")
        let step = Int(o.values["step"]!), cycle = Int(o.values["cycleLength"]!)
        #expect(PlanetaryHours.chaldean.count == cycle)
        #expect(Int(o.values["hoursPerDay"]!) % cycle == step)

        for weekday in 1...7 {
            let today = PlanetaryHours.weekdayRuler(weekday)
            let tomorrow = PlanetaryHours.weekdayRuler(weekday % 7 + 1)
            let i = PlanetaryHours.chaldean.firstIndex(of: today)!
            let advanced = PlanetaryHours.chaldean[(i + step) % cycle]
            #expect(advanced == tomorrow,
                    "weekday \(weekday): \(today.name) + \(step) = \(advanced.name), expected \(tomorrow.name)")
        }
    }

    /// The same closure, but asserted against the **generated hours** rather than against the two
    /// tables.
    ///
    /// The test above compares `chaldean` to `weekdayRuler` and never calls `hours(startingOn:)`, so
    /// it passes even when the produced sequence is wrong — verified by breaking the advance at
    /// sunset, which that test did not notice and this one does. The distinction is the whole point
    /// of the closure: hour 24 is the twenty-fourth link of one unbroken chain, so the planet one
    /// step past it must be the planet the next sunrise actually opens with. An implementation that
    /// restarts the cycle at sunset, or assigns rulers by clock hour, cannot close this.
    @Test func theGeneratedHoursCloseOntoTheNextDaysFirstRuler() {
        for offset in 0..<7 {
            let d = day(2026, 3, 2).addingTimeInterval(Double(offset) * 86_400)
            guard let today = PlanetaryHours.hours(startingOn: d, at: london, timeZone: zone),
                  let next = PlanetaryHours.hours(startingOn: d.addingTimeInterval(86_400),
                                                  at: london, timeZone: zone)
            else { Issue.record("expected hours on both days"); return }

            let last = today[23].ruler
            let i = PlanetaryHours.chaldean.firstIndex(of: last)!
            let continued = PlanetaryHours.chaldean[(i + 1) % PlanetaryHours.chaldean.count]
            let why = "day \(offset): hour 24 is \(last.name), so the next hour is "
                    + "\(continued.name), but the next day opens with \(next[0].ruler.name)"
            #expect(continued == next[0].ruler, "\(why)")
        }
    }

    // MARK: - The external number

    /// At declination 0 and latitude 0 the geometric horizon sits at hour angle 90° exactly, so the
    /// day is exactly twelve hours and each planetary hour exactly sixty minutes. This is the one
    /// value in this function that comes from spherical geometry rather than from our own output.
    @Test func atEquinoxOnTheEquatorGeometricHoursAreExactlySixtyMinutes() {
        let o = Oracles.require("hours-equinox-equator-geometric")
        guard let h = RiseSet.hourAngleAtHorizon(declination: 0, latitude: 0, altitude: 0) else {
            Issue.record("the geometric horizon must be defined at the equator"); return
        }
        #expect(o.matches("hourAngleDeg", h))
        let dayHours = h * 2 / 15                     // degrees of hour angle → hours
        #expect(o.matches("dayLengthHours", dayHours))
        #expect(o.matches("hourLengthMinutes", dayHours * 60 / 12))
    }

    /// …and with the shipping convention it is *not* sixty minutes, because the Sun is refracted
    /// and has a disc. Asserted so nobody "corrects" the standard altitude away.
    @Test func refractionMakesTheEquinoxDayLongerThanTheNight() {
        let o = Oracles.require("hours-refraction-extends-the-day")
        let d = day(2026, 3, 20)
        let s = RiseSet.sun(on: d, at: equator, timeZone: zone)
        guard let rise = s.rise, let set = s.set else {
            Issue.record("the Sun rises and sets at the equator"); return
        }
        let dayMinutes = set.timeIntervalSince(rise) / 60
        #expect(o.matches("dayExcessMinutes", dayMinutes - 720),
                "equinox day length \(String(format: "%.1f", dayMinutes)) min")
        #expect(dayMinutes > 720, "refraction always lengthens the day; it never shortens it")
    }

    // MARK: - The division itself

    /// Twelve day hours tile sunrise→sunset with no gap and no overlap, and twelve night hours tile
    /// sunset→sunrise. Checked as a tiling rather than as a sum, so a set of hours that added up
    /// while overlapping would still fail.
    @Test func hoursTileTheirIntervalsExactly() {
        for (place, loc) in [("London", london), ("equator", equator)] {
            for (m, d) in [(3, 20), (6, 21), (12, 21)] {
                guard let hs = PlanetaryHours.hours(startingOn: day(2026, m, d),
                                                    at: loc, timeZone: zone) else {
                    Issue.record("\(place) \(m)/\(d): expected a division"); continue
                }
                #expect(hs.count == 24)
                for i in 1..<hs.count {
                    #expect(abs(hs[i].start.timeIntervalSince(hs[i-1].end)) < 1e-6,
                            "\(place) \(m)/\(d): gap before hour \(i + 1)")
                }
                // `Array(...)`, not the slices themselves: `suffix(12)` keeps the parent's
                // indices, so `nightHours[0]` would be index 12 of a 12-element slice — a crash,
                // not a failed assertion.
                let dayHours = Array(hs.prefix(12)), nightHours = Array(hs.suffix(12))
                let dayTotal = dayHours.last!.end.timeIntervalSince(dayHours.first!.start)
                #expect(abs(dayHours.map(\.duration).reduce(0, +) - dayTotal) < 1e-6)
                // Within a half, every hour is the same length; across halves they differ.
                for h in dayHours { #expect(abs(h.duration - dayHours[0].duration) < 1e-6) }
                for h in nightHours { #expect(abs(h.duration - nightHours[0].duration) < 1e-6) }
            }
        }
    }

    /// The whole point of the system: an hour is not sixty minutes. If day and night hours ever came
    /// out equal at a high latitude in June, the implementation would have quietly reverted to clock
    /// hours — which is the classic wrong implementation and looks entirely plausible.
    @Test func dayAndNightHoursAreUnequalAwayFromTheEquinox() {
        guard let hs = PlanetaryHours.hours(startingOn: day(2026, 6, 21),
                                            at: london, timeZone: zone) else {
            Issue.record("London has a sunrise in June"); return
        }
        let dayHour = hs[0].duration / 60, nightHour = hs[12].duration / 60
        #expect(dayHour > 75, "London midsummer day hour was \(Int(dayHour))m")
        #expect(nightHour < 45, "London midsummer night hour was \(Int(nightHour))m")
        #expect(abs(dayHour + nightHour - 120) < 0.5, "the pair must still average 60 minutes")
    }

    /// Rulers advance continuously across the sunset boundary. An implementation that restarts the
    /// cycle for the night would pass every duration test above and be wrong about every night hour.
    @Test func rulersAdvanceWithoutABreakAtSunset() {
        guard let hs = PlanetaryHours.hours(startingOn: day(2026, 6, 21),
                                            at: london, timeZone: zone) else { return }
        for i in 1..<hs.count {
            let prev = PlanetaryHours.chaldean.firstIndex(of: hs[i-1].ruler)!
            let cur = PlanetaryHours.chaldean.firstIndex(of: hs[i].ruler)!
            #expect(cur == (prev + 1) % 7,
                    "hour \(i + 1) does not follow hour \(i) in Chaldean order")
        }
    }

    /// The 24-hour closure, end to end through the real implementation: hour 1 of each successive
    /// planetary day is the next weekday's ruler. Runs across a week so a single lucky day cannot
    /// carry it.
    @Test func firstHourOfEachDayIsThatWeekdaysRuler() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        for offset in 0..<7 {
            let d = day(2026, 6, 21).addingTimeInterval(Double(offset) * 86_400)
            guard let hs = PlanetaryHours.hours(startingOn: d, at: london, timeZone: zone) else {
                Issue.record("expected a division on day \(offset)"); continue
            }
            let weekday = cal.component(.weekday, from: hs[0].start)
            #expect(hs[0].ruler == PlanetaryHours.weekdayRuler(weekday),
                    "day \(offset): hour 1 was \(hs[0].ruler.name) on weekday \(weekday)")
        }
    }

    // MARK: - Honesty at the poles

    /// Above the Arctic Circle in midsummer there is no sunrise, so there is no daylight interval to
    /// divide. The answer is "no hours", never twelve fabricated ones.
    @Test func polarDayHasNoHoursRatherThanFabricatedOnes() {
        let tromso = GeoLocation(latitude: 69.6496, longitude: 18.9560)
        #expect(PlanetaryHours.hours(startingOn: day(2026, 6, 21), at: tromso, timeZone: zone) == nil,
                "midnight sun: no sunrise, so no division")
        #expect(PlanetaryHours.hours(startingOn: day(2026, 12, 21), at: tromso, timeZone: zone) == nil,
                "polar night: no sunrise, so no division")
        // …and the same place in spring is perfectly ordinary.
        #expect(PlanetaryHours.hours(startingOn: day(2026, 3, 20), at: tromso, timeZone: zone) != nil)
    }

    // MARK: - Lookup

    /// An instant between midnight and sunrise belongs to the planetary day that began at
    /// *yesterday's* sunrise. Resetting at midnight is the second classic wrong implementation.
    @Test func beforeDawnBelongsToThePreviousPlanetaryDay() {
        let preDawn = utc(2026, 6, 22, 1, 0)          // London sunrise is ~03:43 UT
        guard let hour = PlanetaryHours.current(at: preDawn, location: london, timeZone: zone) else {
            Issue.record("01:00 falls inside a planetary day"); return
        }
        #expect(!hour.isDay, "01:00 is a night hour")
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        // Its sequence started at the 21st's sunrise, so the ruler is Sunday's, not Monday's.
        let openingDay = cal.component(.day, from: preDawn.addingTimeInterval(-86_400))
        #expect(openingDay == 21)
        #expect(hour.contains(preDawn))
    }
}
