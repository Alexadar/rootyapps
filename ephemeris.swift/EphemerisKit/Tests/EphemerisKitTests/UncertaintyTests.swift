import Testing
import Foundation
@testable import EphemerisKit

/// What an unknown birth time leaves undetermined — and, just as importantly, what it does not.
///
/// The oracle here is the Moon's published daily motion, because that single quantity sets the
/// width of the ignorance: an untimed chart knows the Sun's sign for certain and the Moon's only
/// most of the time. Everything else in this suite is a property that must hold for *every* day,
/// which is the right shape for a guard — a range that is merely plausible on the one date someone
/// checked is how a wrong bound survives.
@Suite("Unknown birth time")
struct UncertaintyTests {

    private func day(_ y: Int, _ m: Int, _ d: Int, zone: String = "UTC") -> DateInterval {
        Uncertainty.unknownDay(around: utc(y, m, d, 12, 0), timeZoneID: zone)
    }

    // MARK: - Against the published figure

    @Test func moonsMeanDailyTravelMatchesTheAlmanac() {
        let oracle = Oracles.require("uncertainty-moon-mean-daily-motion")
        var total = 0.0
        var days = 0
        // Sampled across two centuries and spread over the anomalistic cycle, so the mean is not
        // taken from one corner of the Moon's orbit.
        for year in stride(from: 1900, through: 2100, by: 5) {
            for month in [1, 4, 7, 10] {
                total += Uncertainty.longitudeArc(of: .moon, across: day(year, month, 9)).extent
                days += 1
            }
        }
        let mean = total / Double(days)
        #expect(oracle.matches("degreesPerDay", mean),
                "mean lunar daily travel \(String(format: "%.4f", mean))° vs oracle 13.176358°")
    }

    @Test func moonsDailyTravelStaysInsideTheQuotedExtremes() {
        let oracle = Oracles.require("uncertainty-moon-daily-motion-bounds")
        var slowest = Double.greatestFiniteMagnitude
        var fastest = -Double.greatestFiniteMagnitude
        for year in stride(from: 1950, through: 2050, by: 1) {
            for month in [2, 8] {
                let e = Uncertainty.longitudeArc(of: .moon, across: day(year, month, 15)).extent
                slowest = min(slowest, e); fastest = max(fastest, e)
            }
        }
        #expect(oracle.matches("slowestDegreesPerDay", slowest),
                "slowest day \(String(format: "%.3f", slowest))°")
        #expect(oracle.matches("fastestDegreesPerDay", fastest),
                "fastest day \(String(format: "%.3f", fastest))°")
    }

    // MARK: - The wrap, which is where a naive implementation breaks

    /// A body crossing 0° Aries must report the small arc it actually travelled. Taking min and max
    /// of wrapped longitudes would report ~347° for a Moon that moved 13°, and the UI would offer
    /// the reader every sign in the zodiac as a candidate.
    @Test func crossingZeroAriesDoesNotInflateTheArc() {
        var checked = 0
        // Walk a year of days and test every one on which the Moon crosses the 0° seam.
        for offset in 0..<366 {
            let noon = utc(2026, 1, 1, 12, 0).addingTimeInterval(Double(offset) * 86_400)
            let interval = Uncertainty.unknownDay(around: noon, timeZoneID: "UTC")
            let a = Ephemeris.longitude(of: .moon, at: interval.start)
            let b = Ephemeris.longitude(of: .moon, at: interval.end)
            guard b < a else { continue }        // wrapped past 360° during this day
            checked += 1
            let extent = Uncertainty.longitudeArc(of: .moon, across: interval).extent
            #expect(extent < 16.0,
                    "seam day \(interval.start): extent \(String(format: "%.2f", extent))°")
        }
        #expect(checked >= 10, "expected ~13 seam crossings in a year, found \(checked)")
    }

    // MARK: - Sign candidates

    /// A day yields one sign or two, never more: nothing in the solar system covers 30° in a day,
    /// so two cusps cannot fall inside one. Three candidates would mean the arc is inflated.
    @Test func aDayNeverProducesMoreThanTwoSignCandidates() {
        for offset in stride(from: 0, to: 400, by: 7) {
            let noon = utc(2026, 1, 1, 12, 0).addingTimeInterval(Double(offset) * 86_400)
            let interval = Uncertainty.unknownDay(around: noon, timeZoneID: "UTC")
            for body in CelestialBody.allCases {
                let signs = Uncertainty.signCandidates(of: body, across: interval)
                #expect((1...2).contains(signs.count),
                        "\(body.name) on \(interval.start): \(signs.count) candidates")
            }
        }
    }

    /// The Moon changes sign roughly every 2.3 days, so across a long run a meaningful fraction of
    /// days must be ambiguous. If this ever returned one sign for every day, the cusp walk would
    /// have silently stopped detecting crossings — the failure mode that makes the whole feature
    /// quietly do nothing.
    @Test func someDaysAreGenuinelyAmbiguousForTheMoon() {
        var ambiguous = 0
        let total = 120
        for offset in 0..<total {
            let noon = utc(2026, 3, 1, 12, 0).addingTimeInterval(Double(offset) * 86_400)
            let interval = Uncertainty.unknownDay(around: noon, timeZoneID: "UTC")
            if Uncertainty.signCandidates(of: .moon, across: interval).count == 2 { ambiguous += 1 }
        }
        // 13.18°/day over 30° per sign ⇒ about 44% of days contain a cusp.
        #expect((0.30...0.60).contains(Double(ambiguous) / Double(total)),
                "\(ambiguous)/\(total) days ambiguous — expected roughly 44%")
    }

    /// The Sun never leaves its sign twice in a day, and on most days not at all.
    @Test func theSunIsAlmostAlwaysCertain() {
        var ambiguous = 0
        for offset in 0..<365 {
            let noon = utc(2026, 1, 1, 12, 0).addingTimeInterval(Double(offset) * 86_400)
            let interval = Uncertainty.unknownDay(around: noon, timeZoneID: "UTC")
            if Uncertainty.signCandidates(of: .sun, across: interval).count == 2 { ambiguous += 1 }
        }
        #expect(ambiguous <= 12, "the Sun should be ambiguous on ~12 ingress days, got \(ambiguous)")
    }

    // MARK: - Orb ranges

    /// The stored instant lies inside the unknown day, so the range must contain the nominal orb.
    /// A range that excludes its own centre would put the UI in the position of showing a value
    /// outside the bounds printed beside it.
    @Test func theRangeAlwaysContainsTheNominalOrb() {
        let olena = SavedChart(name: "A", birthInstant: utc(1990, 3, 15, 14, 30),
                               timeZoneID: "Europe/Berlin", isTimeKnown: true,
                               latitude: 52.52, longitude: 13.405)
        let untimed = SavedChart(name: "B", birthInstant: utc(1968, 9, 9, 12, 0),
                                 timeZoneID: "Europe/London", isTimeKnown: false,
                                 latitude: 51.51, longitude: -0.13)
        let ranged = olena.rangedSynastry(with: untimed)
        #expect(!ranged.isEmpty)
        for r in ranged {
            #expect(r.orbRange.min <= r.orbRange.nominal + 1e-9 &&
                    r.orbRange.nominal <= r.orbRange.max + 1e-9,
                    "\(r.aspect.id): \(r.orbRange.min)…\(r.orbRange.max) excludes \(r.orbRange.nominal)")
        }
    }

    /// Two timed charts produce no ranges at all — the feature must stay invisible when the data
    /// is complete, rather than decorating every row with a spurious ±0.
    @Test func twoTimedChartsProduceNoRanges() {
        let a = SavedChart(name: "A", birthInstant: utc(1990, 3, 15, 14, 30),
                           timeZoneID: "Europe/Berlin", isTimeKnown: true,
                           latitude: 52.52, longitude: 13.405)
        let b = SavedChart(name: "B", birthInstant: utc(1984, 11, 2, 7, 5),
                           timeZoneID: "Europe/Warsaw", isTimeKnown: true,
                           latitude: 52.23, longitude: 21.01)
        for r in a.rangedSynastry(with: b) {
            #expect(r.orbRange.span == 0)
            #expect(!r.isRanged)
        }
    }

    /// Uncertainty on both sides cannot be narrower than uncertainty on one: the two people's
    /// unknown times are unrelated, so the bound is over the product of the days. A implementation
    /// that swept them in lockstep would report a tighter — and wrong — range.
    @Test func twoUnknownTimesBoundAtLeastAsWideAsOne() {
        let timed = SavedChart(name: "T", birthInstant: utc(1990, 3, 15, 14, 30),
                               timeZoneID: "UTC", isTimeKnown: true,
                               latitude: 52.52, longitude: 13.405)
        let untimedA = SavedChart(name: "A", birthInstant: utc(1990, 3, 15, 12, 0),
                                  timeZoneID: "UTC", isTimeKnown: false,
                                  latitude: 52.52, longitude: 13.405)
        let untimedB = SavedChart(name: "B", birthInstant: utc(1968, 9, 9, 12, 0),
                                  timeZoneID: "UTC", isTimeKnown: false,
                                  latitude: 51.51, longitude: -0.13)
        let oneSide = Dictionary(uniqueKeysWithValues:
            timed.rangedSynastry(with: untimedB).map { ($0.id, $0.orbRange.span) })
        for r in untimedA.rangedSynastry(with: untimedB) {
            guard let single = oneSide[r.id] else { continue }
            #expect(r.orbRange.span >= single - 1e-9,
                    "\(r.id): both-unknown span \(r.orbRange.span) < one-unknown \(single)")
        }
    }

    /// The Moon against an untimed chart is the case the UI tags `RANGE`; if this stopped being
    /// true the tag would never appear and the feature would be dead code that still compiles.
    @Test func theMoonIsTheBodyThatActuallyNeedsTheTag() {
        let timed = SavedChart(name: "T", birthInstant: utc(2026, 6, 1, 9, 0),
                               timeZoneID: "UTC", isTimeKnown: true,
                               latitude: 0, longitude: 0)
        let untimed = SavedChart(name: "U", birthInstant: utc(1975, 7, 4, 12, 0),
                                 timeZoneID: "UTC", isTimeKnown: false,
                                 latitude: 34.05, longitude: -118.24)
        let ranged = timed.rangedSynastry(with: untimed, orbFactor: 2.0)
        let moonRows = ranged.filter { $0.aspect.reference == .moon }
        #expect(!moonRows.isEmpty, "expected contacts to the untimed Moon")
        #expect(moonRows.contains { $0.isRanged },
                "no Moon contact was wide enough to tag — the day sweep is not reaching the Moon")
        // The slow bodies on the same untimed side move too little for a range to be meaningful.
        for r in ranged where r.aspect.reference == .pluto {
            #expect(!r.isRanged, "Pluto should never need a range across one day")
        }
    }

    // MARK: - Chart-level accessors

    @Test func aTimedChartHasNoUnknownDayAndOneSignPerBody() {
        let timed = SavedChart(name: "T", birthInstant: utc(1990, 3, 15, 14, 30),
                               timeZoneID: "Europe/Berlin", isTimeKnown: true,
                               latitude: 52.52, longitude: 13.405)
        #expect(timed.unknownDay == nil)
        for body in CelestialBody.allCases {
            #expect(timed.signCandidates(for: body).count == 1)
        }
    }

    /// The window is the chart's own civil day, not UTC's. Two charts on the same calendar date in
    /// different zones cover different 24-hour spans, and using the wrong one slides the Moon's
    /// candidate signs.
    @Test func theUnknownDayFollowsTheChartsOwnTimeZone() {
        let instant = utc(1996, 6, 21, 23, 40)
        let tokyo = Uncertainty.unknownDay(around: instant, timeZoneID: "Asia/Tokyo")
        let london = Uncertainty.unknownDay(around: instant, timeZoneID: "Europe/London")
        #expect(tokyo.start != london.start)
        #expect(abs(tokyo.duration - 86_400) < 3601)   // DST days are 23 or 25 hours
        #expect(abs(london.duration - 86_400) < 3601)
    }

    /// An unusable zone identifier must fall back to UTC, not to whatever zone the machine running
    /// the test happens to be in — otherwise the same chart reports different candidates on
    /// different devices.
    @Test func anUnknownTimeZoneFallsBackToUTCNotTheDevice() {
        let instant = utc(1990, 3, 15, 2, 0)
        let bogus = Uncertainty.unknownDay(around: instant, timeZoneID: "Not/AZone")
        let utcDay = Uncertainty.unknownDay(around: instant, timeZoneID: "UTC")
        #expect(bogus == utcDay)
    }
}
