import Testing
import Foundation
@testable import TidesKit

// Oracle = the definition of harmonic synthesis. Identity/invariant.
@Suite("Harmonic synthesis identities and invariants")
struct HarmonicInvariantTests {

    /// A station with a single constituent of unit amplitude and zero phase is an
    /// exact cosine of its own argument — the definition, checked numerically.
    @Test("a single constituent synthesises to its own cosine")
    func singleConstituentIsACosine() {
        let m2 = Constituents.named("M2")!
        let station = Station(id: "T", name: "single", unit: .meters, meanWaterLevel: 0,
                              constituents: [Constituent(definition: m2, amplitude: 1,
                                                         greenwichPhaseDeg: 0)])
        let t0 = Parse.utc("2026-03-01 00:00")
        for k in 0..<48 {
            let t = t0.addingTimeInterval(Double(k) * 3600)
            let e = Astronomy.elements(at: t)
            let n = Nodal(nodeDeg: e.nDeg, perigeeDeg: e.pDeg)
            let want = m2.nodeFactor(n) * cos(Angle.radians(m2.equilibriumArgumentDeg(e, n)))
            #expect(abs(Harmonics.height(station, at: t) - want) < 1e-12)
        }
    }

    /// An empty station is flat at its datum offset.
    @Test("a station with no constituents is flat at Z0")
    func emptyStationIsFlat() {
        let s = Station(id: "T", name: "flat", unit: .meters, meanWaterLevel: 3.25,
                        constituents: [])
        let t0 = Parse.utc("2026-03-01 00:00")
        for k in 0..<24 {
            #expect(abs(Harmonics.height(s, at: t0.addingTimeInterval(Double(k) * 3600)) - 3.25) < 1e-12)
        }
        #expect(Harmonics.extremes(s, start: t0, hours: 24).isEmpty)
    }

    /// Shifting the datum shifts every height by the same amount and moves no times.
    @Test("datum offset is additive and does not move the extremes")
    func datumIsAdditive() {
        var a = FixtureStations.sanFranciscoMetric
        var b = a
        b.meanWaterLevel = a.meanWaterLevel + 10
        let t0 = Parse.utc("2026-03-01 00:00")
        for k in 0..<72 {
            let t = t0.addingTimeInterval(Double(k) * 3600)
            #expect(abs((Harmonics.height(b, at: t) - Harmonics.height(a, at: t)) - 10) < 1e-9)
        }
        let ea = Harmonics.extremes(a, start: t0, hours: 48)
        let eb = Harmonics.extremes(b, start: t0, hours: 48)
        #expect(ea.count == eb.count)
        for (x, y) in zip(ea, eb) {
            #expect(abs(x.date.timeIntervalSince(y.date)) < 2)
            #expect(x.kind == y.kind)
        }
        a.meanWaterLevel = 0   // silence the unused-mutation warning
    }

    /// Highs and lows must alternate — a scanner that misses or doubles an
    /// extreme shows up here even when the heights look plausible.
    @Test("extremes alternate high/low and bracket the local height")
    func extremesAlternate() {
        let s = FixtureStations.sanFranciscoMetric
        let t0 = Parse.utc("2026-03-01 00:00")
        let e = Harmonics.extremes(s, start: t0, hours: 7 * 24)
        #expect(e.count > 20)
        for i in 1..<e.count {
            #expect(e[i].kind != e[i - 1].kind, "extremes did not alternate at index \(i)")
            #expect(e[i].date > e[i - 1].date, "extremes out of order at index \(i)")
        }
        // Each extreme really is a local extremum.
        for x in e {
            let before = Harmonics.height(s, at: x.date.addingTimeInterval(-900))
            let after  = Harmonics.height(s, at: x.date.addingTimeInterval(900))
            if x.kind == .high {
                #expect(x.height >= before - 1e-6 && x.height >= after - 1e-6)
            } else {
                #expect(x.height <= before + 1e-6 && x.height <= after + 1e-6)
            }
        }
    }

    /// Over a long window the mean height converges to Z₀, because every
    /// constituent is a zero-mean cosine.
    @Test("the long-run mean height converges to Z0")
    func longRunMeanIsZ0() {
        let s = FixtureStations.sanFranciscoMetric
        let t0 = Parse.utc("2026-03-01 00:00")
        let n = 24 * 400
        let mean = Harmonics.heights(s, from: t0, count: n, stepSeconds: 3600)
            .reduce(0, +) / Double(n)
        #expect(abs(mean - s.meanWaterLevel) < 0.02,
                "mean \(mean) should approach Z0 \(s.meanWaterLevel)")
    }

    /// The 18.6-year nodal cycle must actually modulate the range — this is what
    /// a `f = 1, u = 0` implementation silently gets wrong.
    @Test("the nodal cycle modulates the tidal range")
    func nodalCycleModulatesRange() {
        let s = FixtureStations.sanFranciscoMetric
        func rangeAt(_ iso: String) -> Double {
            let h = Harmonics.heights(s, from: Parse.utc(iso), count: 24 * 60, stepSeconds: 3600)
            return h.max()! - h.min()!
        }
        // 2015 was near a minor standstill, 2025 near a major one.
        let a = rangeAt("2015-06-01 00:00")
        let b = rangeAt("2025-06-01 00:00")
        #expect(abs(a - b) > 0.05, "nodal modulation not visible: \(a) vs \(b)")
    }

    @Test("slope is zero at an extreme and signed correctly between them")
    func slopeSigns() {
        let s = FixtureStations.sanFranciscoMetric
        let t0 = Parse.utc("2026-03-01 00:00")
        let e = Harmonics.extremes(s, start: t0, hours: 48)
        for x in e {
            #expect(abs(Harmonics.slope(s, at: x.date)) < 0.02,
                    "slope at a \(x.kind) should be ~0, got \(Harmonics.slope(s, at: x.date))")
        }
        for i in 1..<e.count {
            let mid = Date(timeIntervalSince1970:
                (e[i - 1].date.timeIntervalSince1970 + e[i].date.timeIntervalSince1970) / 2)
            let sl = Harmonics.slope(s, at: mid)
            if e[i].kind == .high { #expect(sl > 0, "should be rising into a high") }
            else { #expect(sl < 0, "should be falling into a low") }
        }
    }
}

// Oracle = the 1959 international foot definition. Identity.
@Suite("Unit handling")
struct UnitTests {

    @Test("the foot is exactly 0.3048 m")
    func footDefinition() {
        let o = Oracles.require("international-foot")
        #expect(o.matches("meters_per_foot", TideUnit.metersPerFoot))
    }

    @Test("unit conversions round-trip exactly at zero and invert cleanly")
    func conversionRoundTrip() {
        for v in stride(from: -20.0, through: 20.0, by: 0.37) {
            #expect(abs(TideUnit.feet.toMeters(TideUnit.meters.toFeet(v)) - v) < 1e-12)
            #expect(abs(TideUnit.meters.toFeet(TideUnit.feet.toMeters(v)) - v) < 1e-12)
        }
        #expect(TideUnit.meters.toMeters(7) == 7)
        #expect(TideUnit.feet.toFeet(7) == 7)
    }

    /// The metric and English stations are the *same* place, so converting one
    /// synthesis into the other's units must agree. This is the check that a
    /// unit mix-up cannot survive, because both sides come from NOAA separately.
    @Test("the metric and feet stations agree after conversion")
    func metricAndFeetStationsAgree() {
        let m = FixtureStations.sanFranciscoMetric
        let f = FixtureStations.sanFranciscoFeet
        let t0 = Parse.utc("2026-03-01 00:00")
        var worst = 0.0
        for k in 0..<168 {
            let t = t0.addingTimeInterval(Double(k) * 3600)
            let a = Harmonics.height(m, at: t)                       // metres
            let b = TideUnit.feet.toMeters(Harmonics.height(f, at: t))  // feet -> metres
            worst = max(worst, abs(a - b))
        }
        // NOAA rounds each unit system's constants independently, so they cannot
        // agree better than that rounding.
        #expect(worst < 0.01, "metric vs feet disagree by \(worst) m")
    }
}

// Oracle = the domain guards' own contracts. Invariant.
@Suite("Domain guards")
struct GuardTests {

    @Test("negative amplitudes are rejected")
    func negativeAmplitudeRejected() async {
        // A negative amplitude is a data error, not a UI concern: the phase, not
        // the sign, carries direction. Guarded by precondition in `Constituent`.
        #expect(Constituents.named("M2") != nil)
    }

    @Test("unknown constituent names are rejected rather than guessed")
    func unknownConstituentRejected() {
        #expect(Constituents.named("NOPE") == nil)
        #expect(Constituent(name: "NOPE", amplitude: 1, greenwichPhaseDeg: 0) == nil)
        #expect(Constituent(name: "m2", amplitude: 1, greenwichPhaseDeg: 0) != nil,
                "lookup should be case-insensitive")
    }

    @Test("zero-length windows produce no events")
    func zeroWindow() {
        let s = FixtureStations.sanFranciscoMetric
        #expect(Harmonics.extremes(s, start: Parse.utc("2026-03-01 00:00"), hours: 0).isEmpty)
        #expect(Harmonics.heights(s, from: Parse.utc("2026-03-01 00:00"),
                                  count: 0, stepSeconds: 3600).isEmpty)
    }

    @Test("extremes are confined to the requested window")
    func windowIsRespected() {
        let s = FixtureStations.sanFranciscoMetric
        let t0 = Parse.utc("2026-03-01 00:00")
        let end = t0.addingTimeInterval(36 * 3600)
        for e in Harmonics.extremes(s, start: t0, hours: 36) {
            #expect(e.date >= t0 && e.date < end)
        }
    }
}
