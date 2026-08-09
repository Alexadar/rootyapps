import Testing
import Foundation
import EphemerisKit

@Suite("Progressions")
struct ProgressionsTests {

    /// A late-Pisces Sun (≈354°) on purpose: 30 years of solar arc pushes it through 0° Aries,
    /// so every wrap bug in this module shows up in the same fixture the identities use.
    private let birth = utc(1990, 3, 15, 12, 0)
    private let kyiv = GeoLocation(latitude: 50.45, longitude: 30.52, name: "Kyiv")

    private func target(age: Double) -> Date {
        birth.addingTimeInterval(age * Progressions.tropicalYearDays * 86_400)
    }

    private func oracle(_ id: String) -> Oracle { progressionsOracles.require(id) }

    // MARK: Constants

    @Test func tropicalYearMatchesTheOracle() {
        let o = oracle("progressions-tropical-year")
        #expect(o.matches("days", Progressions.tropicalYearDays))
    }

    @Test func meanSolarMotionMatchesTheOracle() {
        let o = oracle("progressions-mean-solar-motion")
        #expect(o.matches("degPerDay", Progressions.meanSolarMotion))
    }

    // MARK: The date map (tested on its own, before any chart exists)

    @Test func fortyYearsOfLifeIsFortyDaysOfSky() {
        let o = oracle("progressions-day-for-a-year-at-40")
        let t = target(age: 40)
        let p = Progressions.progressedDate(birth: birth, on: t)
        #expect(o.matches("progressedOffsetDays", p.timeIntervalSince(birth) / 86_400))
        #expect(o.matches("calendarOffsetDays", t.timeIntervalSince(birth) / 86_400))
        #expect(abs(Progressions.age(birth: birth, on: t) - 40) < 1e-12)
    }

    @Test func ageZeroLeavesTheChartAtBirth() {
        #expect(Progressions.age(birth: birth, on: birth) == 0)
        #expect(Progressions.progressedDate(birth: birth, age: 0) == birth)
        #expect(abs(Progressions.solarArc(birth: birth, on: birth)) < 1e-12)
    }

    @Test func theMapRoundTrips() {
        for age in stride(from: -50.0, through: 120.0, by: 7.5) {
            let t = target(age: age)
            let p = Progressions.progressedDate(birth: birth, on: t)
            let back = Progressions.calendarDate(birth: birth, progressedDate: p)
            #expect(abs(back.timeIntervalSince(t)) < 1e-6, "round trip failed at age \(age)")
        }
    }

    @Test func theMapIsLinearInAge() {
        // Two ages a day apart in the sky must be a tropical year apart on the calendar —
        // no calendar arithmetic, so no leap-day step anywhere.
        for age in stride(from: 0.0, through: 100.0, by: 10.0) {
            let a = Progressions.progressedDate(birth: birth, age: age)
            let b = Progressions.progressedDate(birth: birth, age: age + 1)
            #expect(abs(b.timeIntervalSince(a) - 86_400) < 1e-6)
        }
    }

    // MARK: The defining identity

    @Test func progressedChartIsTheNatalComputationAtTheProgressedDate() {
        let o = oracle("progressions-chart-is-natal-at-progressed-date")
        var maxLon = 0.0, maxSpeed = 0.0
        for age in stride(from: 0.0, through: 80.0, by: 5.0) {
            let chart = Progressions.secondary(birth: birth, on: target(age: age))
            let direct = Progressions.positions(at: birth.addingTimeInterval(age * 86_400))
            #expect(chart.positions.count == CelestialBody.allCases.count)
            for (c, d) in zip(chart.positions, direct) {
                #expect(c.body == d.body)
                maxLon = max(maxLon, abs(AstroMath.norm180(c.longitude - d.longitude)))
                maxSpeed = max(maxSpeed, abs(c.speed - d.speed))
            }
        }
        #expect(o.matches("maxLongitudeDiffDeg", maxLon))
        #expect(o.matches("maxSpeedDiffDegPerDay", maxSpeed))
    }

    @Test func progressedAnglesAreTheNatalAnglesAtTheProgressedDate() {
        let chart = Progressions.secondary(birth: birth, on: target(age: 33), location: kyiv)
        let expected = Houses.angles(at: chart.progressedDate, location: kyiv)
        #expect(chart.angles == expected)
        // Angles are opt-in: no place, no angles (rather than a silently wrong 0° Asc).
        #expect(Progressions.secondary(birth: birth, on: target(age: 33)).angles == nil)
    }

    @Test func theProgressedMoonMovesAboutOneSignPerTwoAndAHalfYears() {
        // Sanity check that the map really is a day per year: the Moon's daily motion is
        // 11.76–15.4°/d, so the progressed Moon covers that many degrees per year of life.
        for age in stride(from: 0.0, through: 60.0, by: 6.0) {
            let now = Progressions.secondary(birth: birth, on: target(age: age), bodies: [.moon])
            let next = Progressions.secondary(birth: birth, on: target(age: age + 1), bodies: [.moon])
            let moved = AstroMath.norm360(next.positions[0].longitude - now.positions[0].longitude)
            #expect((11.0...15.5).contains(moved), "progressed Moon moved \(moved)°/yr at age \(age)")
        }
    }

    // MARK: Solar arc

    @Test func theArcIsTheProgressedSunMinusTheNatalSun() {
        let o = oracle("progressions-arc-is-progressed-minus-natal-sun")
        let natalSun = Ephemeris.longitude(of: .sun, at: birth)
        var worst = 0.0
        for age in stride(from: 0.0, through: 80.0, by: 5.0) {
            let arc = Progressions.solarArc(birth: birth, on: target(age: age))
            let progSun = Ephemeris.longitude(of: .sun, at: birth.addingTimeInterval(age * 86_400))
            // Under 180° of arc the signed difference is the arc outright.
            worst = max(worst, abs(arc - AstroMath.norm180(progSun - natalSun)))
        }
        #expect(o.matches("maxResidualDeg", worst))
    }

    @Test func theArcAppliedToTheNatalSunReproducesTheProgressedSun() {
        let o = oracle("progressions-arc-reproduces-progressed-sun")
        let natalSun = Ephemeris.longitude(of: .sun, at: birth)
        var worst = 0.0
        for age in stride(from: 0.0, through: 400.0, by: 13.0) {
            let arc = Progressions.solarArc(birth: birth, on: target(age: age))
            let progSun = Ephemeris.longitude(of: .sun, at: birth.addingTimeInterval(age * 86_400))
            let directed = Progressions.directed(longitude: natalSun, arc: arc)
            worst = max(worst, abs(AstroMath.norm180(directed - progSun)))
        }
        #expect(o.matches("maxResidualDeg", worst))
    }

    @Test func everyDirectedBodyCarriesTheSameArc() {
        let chart = Progressions.solarArcDirected(birth: birth, on: target(age: 42))
        #expect(chart.positions.count == CelestialBody.allCases.count)
        for (n, d) in zip(chart.natalPositions, chart.positions) {
            #expect(n.body == d.body)
            #expect(abs(AstroMath.norm180(d.longitude - n.longitude - chart.arc)) < 1e-9)
            #expect(d.longitude >= 0 && d.longitude < 360)      // normalized, always
        }
        // The Sun is the fixed point of the two techniques: directed == progressed.
        let progressedSun = Progressions.secondary(birth: birth, on: target(age: 42)).position(.sun)!
        #expect(abs(AstroMath.norm180(chart.position(.sun)!.longitude - progressedSun.longitude)) < 1e-9)
    }

    @Test func directedBodiesMoveAtTheSolarRateNotTheirOwn() {
        // A directed Mercury cannot retrograde: its longitude is natal + arc, and only the arc
        // moves. Mercury is natally retrograde in this chart's neighbourhood often enough that
        // copying the natal speed would be visible.
        let chart = Progressions.solarArcDirected(birth: birth, on: target(age: 42))
        let sunRate = Ephemeris.dailyMotion(of: .sun,
                                            at: Progressions.progressedDate(birth: birth, age: 42))
        for p in chart.positions {
            #expect(abs(p.speed - sunRate) < 1e-12)
            #expect(p.speed > 0)
        }
    }

    // MARK: The 0°/360° wrap

    @Test func theArcWrapsThroughZeroAries() {
        let o = oracle("progressions-arc-wraps-through-aries")
        let natalSun = Ephemeris.longitude(of: .sun, at: birth)
        let arc = Progressions.solarArc(birth: birth, on: target(age: 30))
        let progSun = Progressions.secondary(birth: birth, on: target(age: 30),
                                             bodies: [.sun]).positions[0].longitude

        // The fixture must actually exercise the wrap, or this test proves nothing.
        #expect(natalSun > 330 && natalSun < 360, "natal Sun \(natalSun)° is not in late Pisces")
        #expect(progSun < natalSun, "progressed Sun \(progSun)° did not cross 0° Aries")
        #expect(ZodiacSign.from(longitude: natalSun) == .pisces)
        #expect(ZodiacSign.from(longitude: progSun) == .aries)

        #expect(arc > 0, "the arc went backwards across the wrap: \(arc)°")
        #expect(o.matches("arcDeg", arc))
        #expect(o.matches("wrapResidualDeg",
                          abs(AstroMath.norm180(Progressions.directed(longitude: natalSun, arc: arc) - progSun))))
    }

    @Test func directedLongitudesStayNormalizedAcrossTheWrap() {
        // Sweep an arc right across the seam, one natal degree at a time.
        for natal in stride(from: 0.0, to: 360.0, by: 1.0) {
            for arc in [-359.5, -0.5, 0.0, 0.5, 45.0, 359.5, 720.25] {
                let d = Progressions.directed(longitude: natal, arc: arc)
                #expect(d >= 0 && d < 360, "directed(\(natal), \(arc)) = \(d)")
                #expect(abs(AstroMath.norm180(d - natal - arc)) < 1e-9)
            }
        }
    }

    @Test func theArcDoesNotFoldBackPastAFullTurn() {
        let o = oracle("progressions-arc-unwraps-past-full-turn")
        let arc = Progressions.solarArc(birth: birth, on: target(age: 400))
        #expect(arc > 360, "arc \(arc)° folded back — 400 years is more than one turn of the Sun")
        #expect(o.matches("arcDeg", arc))
    }

    @Test func converseDirectionsRunBackwards() {
        let o = oracle("progressions-converse-arc-is-negative")
        let arc = Progressions.solarArc(birth: birth, on: target(age: -30))
        #expect(arc < 0, "converse arc \(arc)° came back positive — norm360 swallowed the sign")
        #expect(o.matches("arcDeg", arc))
        // And the converse progressed date is genuinely before birth.
        #expect(Progressions.progressedDate(birth: birth, on: target(age: -30)) < birth)
    }

    @Test func theArcGrowsMonotonicallyWithAge() {
        // ~1°/year, never stalling or reversing: the unwrapping must not introduce a step.
        var previous = -Double.infinity
        for age in stride(from: -40.0, through: 400.0, by: 2.5) {
            let arc = Progressions.solarArc(birth: birth, on: target(age: age))
            #expect(arc > previous, "arc went backwards at age \(age)")
            // True minus mean solar longitude is the equation of the centre (±1.92°), and it
            // enters the arc twice — once at the natal end, once at the progressed end.
            #expect(abs(arc - age * Progressions.meanSolarMotion) < 4.0,
                    "arc \(arc)° is not near the mean at age \(age)")
            previous = arc
        }
    }

    // MARK: Oracle hygiene (this file's own corpus — Oracles.all is guarded separately)

    @Test func everyProgressionOracleIsWellFormed() {
        for o in progressionsOracles.all {
            #expect(o.id.hasPrefix("progressions-"), "oracle '\(o.id)' is not namespaced")
            #expect(!o.source.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(!o.inputs.isEmpty)
            #expect(!o.precision.isEmpty)
            #expect(!o.values.isEmpty)
            for key in o.values.keys { #expect((o.tolerances[key] ?? 0) > 0, "\(o.id).\(key)") }
            for key in o.tolerances.keys { #expect(o.values[key] != nil, "\(o.id).\(key)") }
        }
        let ids = progressionsOracles.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        // Merged into the shared corpus by the integration pass: each id must appear there
        // EXACTLY once — zero means the merge dropped them, two means a collision.
        for id in ids {
            #expect(Oracles.all.filter { $0.id == id }.count == 1,
                    "'\(id)' is not present exactly once in the shared corpus")
        }
    }
}
