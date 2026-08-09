import Testing
import Foundation
import EphemerisKit

/// Return charts. The oracle kind here is *construction*: the identity λ(t_return) = λ_natal is
/// what a return means, so it is asserted on every event these tests produce, and the published
/// mean periods are checked against the spacing of successive returns.
@Suite("Returns")
struct ReturnsTests {

    /// The natal chart every oracle in `Oracles+returns.swift` was measured against.
    let natal = utc(1990, 3, 15, 12, 0)

    /// Schlyter's Pluto series is only valid to ~2099, so no sweep here runs past it —
    /// a "return" computed from a diverged series would be arithmetic, not astronomy.
    let horizon = utc(2099, 12, 31)

    /// Looks in this module's own array first, so the tests work both before and after the
    /// integration pass merges `returnsOracles.all` into `Oracles.all`.
    private func oracle(_ id: String) -> Oracle {
        returnsOracles.all.first { $0.id == id } ?? Oracles.require(id)
    }

    /// ±1e-6°, from the identity oracle.
    private var identityTolerance: Double {
        oracle("returns-identity-residual").tolerances["residualDeg"]!
    }

    /// Mean spacing, in days, of `count` consecutive return passages of `body`.
    private func meanGapDays(_ body: CelestialBody, count: Int) -> Double {
        var firsts: [Date] = []
        for n in 1...count {
            guard let c = Returns.cycle(n, of: body, natal: natal) else {
                Issue.record("no return cycle \(n) for \(body.name)")
                return .nan
            }
            for h in c.hits { #expect(h.residual <= identityTolerance) }
            firsts.append(c.first.date)
        }
        let gaps = zip(firsts, firsts.dropFirst()).map { $1.timeIntervalSince($0) / 86_400 }
        return gaps.reduce(0, +) / Double(gaps.count)
    }

    // MARK: The defining identity

    @Test func solarReturnsLandExactlyOnTheNatalSun() {
        let natalSun = Ephemeris.longitude(of: .sun, at: natal)
        for age in 1...40 {
            let e = Returns.solarReturn(natal: natal, age: age)
            #expect(e != nil)
            guard let e else { continue }
            // Checked two ways: against the stored natal longitude, and against a fresh
            // ephemeris call — a return that only agrees with its own bookkeeping proves nothing.
            #expect(e.residual <= identityTolerance)
            #expect(AstroMath.separation(Ephemeris.longitude(of: .sun, at: e.date), natalSun) <= identityTolerance)
            #expect(e.sign == ZodiacSign.from(longitude: natalSun))
            #expect(!e.retrograde)
        }
    }

    @Test func lunarReturnsLandExactlyOnTheNatalMoon() {
        let natalMoon = Ephemeris.longitude(of: .moon, at: natal)
        for index in 1...80 {
            guard let e = Returns.lunarReturn(natal: natal, index: index) else {
                Issue.record("no lunar return \(index)"); continue
            }
            #expect(e.residual <= identityTolerance)
            #expect(AstroMath.separation(Ephemeris.longitude(of: .moon, at: e.date), natalMoon) <= identityTolerance)
            #expect(!e.retrograde)   // the Moon's apparent longitude never runs backwards
        }
    }

    /// Every body, over its own full period — so Uranus's 84-year return is exercised too, not
    /// just the fast ones. Neptune and Pluto do not complete a revolution before the horizon;
    /// they still get their crossings checked, they just cannot be required to have any.
    @Test func everyBodyReturnsAndEveryCrossingIsExact() {
        for body in CelestialBody.allCases {
            let period = Returns.meanPeriodDays(body) * 86_400
            let end = min(natal.addingTimeInterval(period * 1.6), horizon)
            let hits = Returns.hits(of: body, to: Ephemeris.longitude(of: body, at: natal),
                                    in: DateInterval(start: natal, end: end))
            if end.timeIntervalSince(natal) > period * 1.05 {
                #expect(!hits.isEmpty, "\(body.name) never returned in a full period")
            }
            for h in hits {
                #expect(h.residual <= identityTolerance,
                        "\(body.name) return at \(h.date) missed by \(h.residual)°")
                #expect(h.retrograde == Ephemeris.isRetrograde(body, at: h.date))
                #expect(h.sign == ZodiacSign.from(longitude: h.longitude))
            }
            for (a, b) in zip(hits, hits.dropFirst()) {
                #expect(b.date > a.date, "\(body.name): crossings out of order")
                // Two roots inside one daily bracket would be one crossing reported twice.
                #expect(b.date.timeIntervalSince(a.date) > 86_400 * 0.5)
            }
        }
    }

    // MARK: Published mean periods

    @Test func solarReturnsAreOneTropicalYearApart() {
        let o = oracle("returns-tropical-year")
        let measured = meanGapDays(.sun, count: 40)
        #expect(o.matches("days", measured), "measured \(measured) d")
    }

    @Test func lunarReturnsAreOneTropicalMonthApart() {
        let o = oracle("returns-tropical-month")
        let measured = meanGapDays(.moon, count: 80)
        #expect(o.matches("meanDays", measured), "measured \(measured) d")
    }

    /// Individual months are nothing like the mean — eccentricity and evection swing them by
    /// hours. Bounding the spread from both sides stops a future "optimization" from replacing
    /// real root-finding with a mean-motion formula, which would still pass the mean test.
    @Test func individualLunarMonthsVaryButStayBounded() {
        let mean = oracle("returns-tropical-month").values["meanDays"]!
        var dates: [Date] = []
        for i in 1...80 { dates.append(Returns.lunarReturn(natal: natal, index: i)!.date) }
        let gaps = zip(dates, dates.dropFirst()).map { $1.timeIntervalSince($0) / 86_400 }
        for g in gaps { #expect(abs(g - mean) < 0.5, "month of \(g) d") }
        #expect((gaps.max()! - gaps.min()!) > 0.1, "no month-length variation at all — suspiciously mean-motion")
    }

    @Test func marsReturnsMatchItsPublishedTropicalPeriod() {
        let o = oracle("returns-mars-tropical-period")
        let measured = meanGapDays(.mars, count: 60)
        #expect(o.matches("meanDays", measured), "measured \(measured) d")
    }

    @Test func jupiterReturnsMatchItsPublishedTropicalPeriod() {
        let o = oracle("returns-jupiter-tropical-period")
        let measured = meanGapDays(.jupiter, count: 25)
        #expect(o.matches("meanDays", measured), "measured \(measured) d")
    }

    @Test func saturnReturnsMatchItsPublishedTropicalPeriod() {
        let o = oracle("returns-saturn-tropical-period")
        let measured = meanGapDays(.saturn, count: 20)
        #expect(o.matches("meanDays", measured), "measured \(measured) d")
    }

    @Test func theFirstSaturnReturnFallsNearAgeThirty() {
        let o = oracle("returns-saturn-first-return-age")
        let c = Returns.saturnReturn(natal: natal)
        #expect(c != nil)
        guard let c else { return }
        let years = c.first.date.timeIntervalSince(natal) / 86_400 / 365.2422
        #expect(o.matches("years", years), "first Saturn return at \(years) yr")
        #expect(c.hits.allSatisfy { $0.residual <= identityTolerance })
    }

    @Test func successiveSolarReturnsAreMonotonicAndOnePeriodApart() {
        var previous = natal
        for age in 1...40 {
            let e = Returns.solarReturn(natal: natal, age: age)!
            let gap = e.date.timeIntervalSince(previous) / 86_400
            #expect(e.date > previous)
            #expect(abs(gap - Returns.meanPeriodDays(.sun)) < 0.01, "gap \(gap) d at age \(age)")
            previous = e.date
        }
    }

    // MARK: Passages

    /// A body that stations inside its own natal degree crosses it three times. The count is
    /// always odd — whatever comes back must first have gone past — and the middle hit of a
    /// triple is the retrograde one.
    @Test func passagesHaveAnOddNumberOfHits() {
        let sweep = DateInterval(start: utc(1995, 1, 1), end: utc(2060, 1, 1))
        var sawTriple = false
        for body in CelestialBody.allCases {
            let cycles = Returns.cycles(of: body, to: Ephemeris.longitude(of: body, at: natal), in: sweep)
            // Drop the edges: a passage straddling the window boundary is clipped, not even.
            for c in cycles.dropFirst().dropLast() {
                #expect(c.hits.count % 2 == 1, "\(body.name) passage with \(c.hits.count) hits")
                if c.hits.count == 3 {
                    sawTriple = true
                    #expect(!c.hits[0].retrograde)
                    #expect(c.hits[1].retrograde)
                    #expect(!c.hits[2].retrograde)
                    #expect(c.span.duration < 86_400 * 365, "triple spread over more than a year")
                }
                #expect(c.hits.allSatisfy { $0.residual <= identityTolerance })
                #expect(c.hits.allSatisfy { $0.natalLongitude == c.natalLongitude })
            }
        }
        #expect(sawTriple, "no triple return anywhere in 65 years — the retrograde path is untested")
    }

    @Test func theSecondSaturnReturnOfThisChartIsATriple() {
        let c = Returns.saturnReturn(natal: natal, ordinal: 2)
        #expect(c != nil)
        guard let c else { return }
        #expect(c.hits.count == 3)
        #expect(c.isTriple)
        #expect(c.hits.map(\.retrograde) == [false, true, false])
        #expect(c.first.date < c.last.date)
        #expect(c.span.duration == c.last.date.timeIntervalSince(c.first.date))
        #expect(c.hits.allSatisfy { $0.residual <= identityTolerance })
        #expect(c.hits.allSatisfy { $0.sign == c.first.sign })
    }

    @Test func cyclesPartitionTheCrossingsWithoutLossOrDuplication() {
        let sweep = DateInterval(start: utc(1990, 1, 1), end: utc(2050, 1, 1))
        for body in CelestialBody.allCases {
            let target = Ephemeris.longitude(of: body, at: natal)
            let hits = Returns.hits(of: body, to: target, in: sweep)
            let grouped = Returns.cycles(of: body, to: target, in: sweep).flatMap(\.hits)
            #expect(grouped.map(\.date) == hits.map(\.date), "\(body.name): grouping lost or reordered a hit")
        }
    }

    // MARK: The 0°/360° wrap

    /// The module hangs on bracketing a `norm180` difference. A raw difference would put a 360°
    /// cliff at the natal degree itself, so a natal longitude beside 0° Aries is exactly where a
    /// wrong convention shows up — as a missed return, or as a "root" found on the cliff.
    @Test func natalDegreesStraddlingZeroAriesBehave() {
        let from = utc(2026, 1, 1)
        var found: [Date] = []
        for target in [359.99, 0.0, 0.01] {
            let e = Returns.next(.sun, to: target, after: from)
            #expect(e != nil, "no Sun return to \(target)°")
            guard let e else { continue }
            #expect(e.residual <= identityTolerance)
            #expect(AstroMath.separation(e.longitude, target) <= identityTolerance)
            found.append(e.date)
        }
        // The Sun crosses 359.99 → 0 → 0.01 in that order, ~14.6 minutes apart at ~1°/day.
        #expect(found.count == 3)
        #expect(found[0] < found[1] && found[1] < found[2])
        #expect(found[2].timeIntervalSince(found[0]) < 3600)
    }

    @Test func targetLongitudeIsNormalizedNotTakenLiterally() {
        let from = utc(2026, 1, 1)
        let zero = Returns.next(.sun, to: 0, after: from)!
        for equivalent in [360.0, 720.0, -360.0] {
            let e = Returns.next(.sun, to: equivalent, after: from)!
            #expect(e.date == zero.date, "\(equivalent)° is the same degree as 0°")
            #expect(e.natalLongitude == 0)
        }
        let minusOne = Returns.next(.sun, to: -1, after: from)!
        #expect(minusOne.natalLongitude == 359)
        #expect(minusOne.date < zero.date)   // 359° comes first, moving forward
    }

    /// `residual` must use the wrap-aware separation: a hit at 359.999999998° against a natal
    /// degree of 0° is a hit, not a 360° miss.
    @Test func residualIsWrapAware() {
        let e = Returns.next(.moon, to: 0, after: utc(2026, 1, 1))!
        #expect(e.residual <= identityTolerance)
        let naive = abs(e.longitude - e.natalLongitude)
        #expect(naive <= identityTolerance || naive > 359, "unexpected raw difference \(naive)")
    }

    // MARK: next / cycle contracts

    @Test func nextIsTheEarliestCrossingAfterTheDate() {
        let from = utc(2026, 3, 1)
        for body in [CelestialBody.sun, .moon, .venus, .mars, .saturn] {
            let target = Ephemeris.longitude(of: body, at: natal)
            let n = Returns.next(body, to: target, after: from)
            #expect(n != nil)
            guard let n else { continue }
            #expect(n.date > from)
            let earlier = DateInterval(start: from, end: n.date.addingTimeInterval(-60))
            #expect(Returns.hits(of: body, to: target, in: earlier).isEmpty,
                    "\(body.name): an earlier crossing exists before \(n.date)")
        }
    }

    /// `cycle` is anchored on the mean period, not counted forward — and this chart shows why.
    /// Natal Saturn is direct but stations within 103 days and re-crosses its own degree, so
    /// "count the crossings" would call that the first Saturn return, at age zero.
    @Test func cycleIsAnchoredOnThePeriodNotCountedForward() {
        let saturn = Ephemeris.longitude(of: .saturn, at: natal)
        let immediate = Returns.next(.saturn, to: saturn, after: natal)!
        #expect(immediate.date.timeIntervalSince(natal) / 86_400 < 200)   // the retrograde re-crossing
        #expect(immediate.residual <= identityTolerance)

        let first = Returns.saturnReturn(natal: natal)!.first
        let years = first.date.timeIntervalSince(natal) / 86_400 / 365.2422
        #expect(years > 28 && years < 31, "first Saturn return at \(years) yr")
        #expect(first.date > immediate.date)
    }

    @Test func cycleRejectsNonPositiveOrdinals() {
        #expect(Returns.cycle(0, of: .sun, natal: natal) == nil)
        #expect(Returns.cycle(-3, of: .saturn, natal: natal) == nil)
    }

    // MARK: Search windows

    /// Mercury and Venus must use the tropical *year*, not their heliocentric periods: seen from
    /// Earth they never leave the Sun's side, so they re-cross a fixed degree about once a year.
    /// An 88-day window for Mercury would size every search wrongly.
    @Test func innerPlanetsUseTheGeocentricPeriod() {
        #expect(Returns.meanPeriodDays(.mercury) == Returns.meanPeriodDays(.sun))
        #expect(Returns.meanPeriodDays(.venus) == Returns.meanPeriodDays(.sun))
        let sweep = DateInterval(start: utc(2000, 1, 1), end: utc(2020, 1, 1))
        for body in [CelestialBody.mercury, .venus] {
            let cycles = Returns.cycles(of: body, to: Ephemeris.longitude(of: body, at: natal), in: sweep)
            #expect(abs(cycles.count - 20) <= 1, "\(body.name): \(cycles.count) passages in 20 years")
        }
    }

    @Test func meanPeriodsIncreaseWithDistance() {
        let ordered: [CelestialBody] = [.moon, .sun, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto]
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            #expect(Returns.meanPeriodDays(a) < Returns.meanPeriodDays(b))
        }
    }

    // MARK: Oracle hygiene (this file's own array, before it is merged)

    @Test func returnsOraclesSatisfyTheCorpusContract() {
        for o in returnsOracles.all {
            #expect(o.id.hasPrefix("returns-"), "oracle '\(o.id)' is not namespaced")
            #expect(!o.source.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(!o.inputs.isEmpty)
            #expect(!o.precision.isEmpty)
            #expect(!o.values.isEmpty)
            for key in o.values.keys { #expect((o.tolerances[key] ?? 0) > 0, "\(o.id).\(key) has no tolerance") }
            for key in o.tolerances.keys { #expect(o.values[key] != nil, "\(o.id).\(key) has no value") }
        }
        let ids = returnsOracles.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
