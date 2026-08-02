import Testing
import Foundation
@testable import TidesKit

// Oracle = NOAA CO-OPS published current predictions, synthesised from NOAA's own
// published current harmonic constants. https://api.tidesandcurrents.noaa.gov
// -- oracle-backed.
@Suite("Tidal currents vs NOAA published predictions")
struct CurrentsOracleTests {

    @Test("Pollock Rip major-axis velocity reproduces NOAA")
    func pollockRipVelocity() {
        let o = Oracles.require("noaa-ACT1616-currents")
        let station = FixtureStations.pollockRip
        let published = Parse.series(Fixtures.currentPredictions)
        #expect(published.count >= 300)

        let r = Residuals(published.map { (Currents.velocity(station, at: $0.date), $0.value) })
        #expect(r.rms <= o.tolerance("rms_cms"),
                "rms \(r.rms) cm/s exceeds \(o.tolerance("rms_cms"))")
        #expect(r.maxAbs <= o.tolerance("max_cms"),
                "max \(r.maxAbs) cm/s exceeds \(o.tolerance("max_cms"))")
    }

    @Test("mean flood and ebb directions match NOAA")
    func meanAxes() {
        let o = Oracles.require("noaa-ACT1616-axes")
        let s = FixtureStations.pollockRip
        #expect(o.matches("mean_flood_dir_deg", s.meanFloodDirectionDeg))
        #expect(o.matches("mean_ebb_dir_deg", s.meanEbbDirectionDeg))
    }

    /// Slack water and maximum flood/ebb are what a mariner actually reads, so
    /// they get their own Class-A check against NOAA's published MAX_SLACK
    /// product rather than being inferred from the sampled series.
    @Test("slack and maximum events match NOAA's published MAX_SLACK product")
    func eventsMatchPublishedMaxSlack() {
        let o = Oracles.require("noaa-ACT1616-events")
        let station = FixtureStations.pollockRip
        let published = Parse.currentEvents(Fixtures.currentEvents)
        #expect(published.count >= 50, "expected ~55 published events, got \(published.count)")

        let start = Parse.utc("2026-03-01 00:00")
        let ours = Currents.events(station, start: start, hours: 7 * 24)

        var worstTime = 0.0, worstVelocity = 0.0, matched = 0
        for p in published {
            guard let m = ours.filter({ $0.phase == p.phase })
                .min(by: { abs($0.date.timeIntervalSince(p.date))
                         < abs($1.date.timeIntervalSince(p.date)) }) else { continue }
            let dt = abs(m.date.timeIntervalSince(p.date)) / 60.0
            guard dt < 60 else { continue }        // not the same event
            matched += 1
            worstTime = max(worstTime, dt)
            worstVelocity = max(worstVelocity, abs(m.velocityCMS - p.value))
        }
        #expect(matched >= published.count - 2,
                "only matched \(matched) of \(published.count) published events")
        #expect(worstTime <= o.tolerance("max_time_error_min"),
                "worst event time error \(worstTime) min exceeds \(o.tolerance("max_time_error_min"))")
        #expect(worstVelocity <= o.tolerance("max_velocity_error_cms"),
                "worst event velocity error \(worstVelocity) cm/s exceeds \(o.tolerance("max_velocity_error_cms"))")
    }
}

// Oracle = definitions of slack/flood/ebb. Invariant.
@Suite("Current invariants")
struct CurrentInvariantTests {

    @Test("events alternate slack and maximum, and are time-ordered")
    func eventsAlternate() {
        let s = FixtureStations.pollockRip
        let start = Parse.utc("2026-03-01 00:00")
        let e = Currents.events(s, start: start, hours: 72)
        #expect(e.count > 15)
        for i in 1..<e.count {
            #expect(e[i].date > e[i - 1].date, "events out of order at \(i)")
            let wasSlack = e[i - 1].phase == .slack
            let isSlack = e[i].phase == .slack
            #expect(wasSlack != isSlack,
                    "slack and maximum should alternate; got \(e[i-1].phase) then \(e[i].phase)")
        }
    }

    /// Sign convention: NOAA's Velocity_Major is positive on the flood.
    @Test("flood is positive and ebb is negative")
    func floodEbbSigns() {
        let s = FixtureStations.pollockRip
        let e = Currents.events(s, start: Parse.utc("2026-03-01 00:00"), hours: 7 * 24)
        for x in e {
            switch x.phase {
            case .flood: #expect(x.velocityCMS > 0, "flood should be positive")
            case .ebb:   #expect(x.velocityCMS < 0, "ebb should be negative")
            case .slack: #expect(abs(x.velocityCMS) < 1.0, "slack should be ~0")
            }
        }
        #expect(e.contains { $0.phase == .flood })
        #expect(e.contains { $0.phase == .ebb })
    }

    @Test("direction is reported for maxima and withheld at slack")
    func directionReporting() {
        let s = FixtureStations.pollockRip
        let e = Currents.events(s, start: Parse.utc("2026-03-01 00:00"), hours: 48)
        for x in e {
            switch x.phase {
            case .slack: #expect(x.directionDeg(s) == nil)
            case .flood: #expect(x.directionDeg(s) == s.meanFloodDirectionDeg)
            case .ebb:   #expect(x.directionDeg(s) == s.meanEbbDirectionDeg)
            }
        }
    }

    @Test("acceleration vanishes at a maximum")
    func accelerationAtMaxima() {
        let s = FixtureStations.pollockRip
        let e = Currents.events(s, start: Parse.utc("2026-03-01 00:00"), hours: 48)
            .filter { $0.phase != .slack }
        for x in e {
            let accel = Currents.acceleration(s, at: x.date)
            #expect(abs(accel) < 2.0,
                    "acceleration at a \(x.phase) should be ~0, got \(accel) cm/s/h")
        }
    }

    @Test("zero-length windows produce no events")
    func zeroWindow() {
        let s = FixtureStations.pollockRip
        #expect(Currents.events(s, start: Parse.utc("2026-03-01 00:00"), hours: 0).isEmpty)
    }
}
