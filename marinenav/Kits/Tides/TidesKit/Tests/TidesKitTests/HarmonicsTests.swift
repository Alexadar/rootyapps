import Testing
import Foundation
@testable import TidesKit

/// Residual statistics of a synthesis against a published series.
struct Residuals {
    var rms = 0.0, maxAbs = 0.0, bias = 0.0, n = 0

    init(_ pairs: [(ours: Double, theirs: Double)]) {
        n = pairs.count
        guard n > 0 else { return }
        var sum = 0.0, sumSq = 0.0
        for p in pairs {
            let d = p.ours - p.theirs
            sum += d; sumSq += d * d
            maxAbs = Swift.max(maxAbs, abs(d))
        }
        bias = sum / Double(n)
        rms = (sumSq / Double(n)).squareRoot()
    }
}

// Oracle = NOAA CO-OPS published tide predictions, synthesised from NOAA's own
// published harmonic constants. https://api.tidesandcurrents.noaa.gov -- oracle-backed.
//
// This is the Class-A test the whole app rests on: NOAA publishes both the inputs
// (constituents, datums) and the answer (predictions) for the same station, so the
// synthesis is checked against an external authority rather than against itself.
@Suite("Tide heights vs NOAA published predictions")
struct HarmonicsOracleTests {

    @Test("San Francisco hourly, metric, reproduces NOAA")
    func sanFranciscoHourlyMetric() {
        let o = Oracles.require("noaa-9414290-hourly-metric")
        let station = FixtureStations.sanFranciscoMetric
        let published = Parse.series(Fixtures.sfHourlyMetric)
        #expect(published.count == 168)

        let r = Residuals(published.map { (Harmonics.height(station, at: $0.date), $0.value) })
        #expect(r.rms <= o.tolerance("rms_m"), "rms \(r.rms) m exceeds \(o.tolerance("rms_m"))")
        #expect(r.maxAbs <= o.tolerance("max_m"), "max \(r.maxAbs) m exceeds \(o.tolerance("max_m"))")
        #expect(abs(r.bias) <= o.tolerance("bias_m"), "bias \(r.bias) m exceeds \(o.tolerance("bias_m"))")
    }

    @Test("San Francisco hourly, FEET, reproduces NOAA's own English-unit output")
    func sanFranciscoHourlyEnglish() {
        let o = Oracles.require("noaa-9414290-hourly-english")
        let station = FixtureStations.sanFranciscoFeet
        let published = Parse.series(Fixtures.sfHourlyEnglish)
        #expect(published.count == 168)

        let r = Residuals(published.map { (Harmonics.height(station, at: $0.date), $0.value) })
        #expect(r.rms <= o.tolerance("rms_ft"), "rms \(r.rms) ft exceeds \(o.tolerance("rms_ft"))")
        #expect(r.maxAbs <= o.tolerance("max_ft"), "max \(r.maxAbs) ft exceeds \(o.tolerance("max_ft"))")
    }

    @Test("Galveston hourly, a diurnal regime, reproduces NOAA")
    func galvestonHourlyMetric() {
        let o = Oracles.require("noaa-8771450-hourly-metric")
        let station = FixtureStations.galvestonMetric
        let published = Parse.series(Fixtures.galvestonHourlyMetric)

        let r = Residuals(published.map { (Harmonics.height(station, at: $0.date), $0.value) })
        #expect(r.rms <= o.tolerance("rms_m"), "rms \(r.rms) m exceeds \(o.tolerance("rms_m"))")
        #expect(r.maxAbs <= o.tolerance("max_m"), "max \(r.maxAbs) m exceeds \(o.tolerance("max_m"))")
    }

    @Test("Z0 is MSL - MLLW at the published datums")
    func datumOffset() {
        let o = Oracles.require("noaa-9414290-z0-metric")
        let d = Parse.datums(Fixtures.sfDatumsMetric)
        #expect(o.matches("msl_m", d.msl))
        #expect(o.matches("mllw_m", d.mllw))
        #expect(o.matches("z0_m", d.z0))
    }

    @Test("high and low waters match NOAA's published times and heights")
    func highLowWaters() {
        let o = Oracles.require("noaa-9414290-hilo-metric")
        let station = FixtureStations.sanFranciscoMetric
        let published = Parse.hilo(Fixtures.sfHiLoMetric)
        #expect(published.count >= 24)

        let start = Parse.utc("2026-03-01 00:00")
        let ours = Harmonics.extremes(station, start: start, hours: 7 * 24)

        var worstTime = 0.0, worstHeight = 0.0
        for p in published {
            // Match by nearest predicted extreme of the same kind.
            guard let m = ours.filter({ $0.kind == p.kind })
                .min(by: { abs($0.date.timeIntervalSince(p.date))
                         < abs($1.date.timeIntervalSince(p.date)) })
            else {
                Issue.record("no predicted \(p.kind) near \(p.date)"); continue
            }
            worstTime = max(worstTime, abs(m.date.timeIntervalSince(p.date)) / 60.0)
            worstHeight = max(worstHeight, abs(m.height - p.value))
        }
        #expect(worstTime <= o.tolerance("max_time_error_min"),
                "worst extreme time error \(worstTime) min exceeds \(o.tolerance("max_time_error_min"))")
        #expect(worstHeight <= o.tolerance("max_height_error_m"),
                "worst extreme height error \(worstHeight) m exceeds \(o.tolerance("max_height_error_m"))")
        #expect(ours.count == published.count,
                "found \(ours.count) extremes, NOAA published \(published.count)")
    }
}

// Oracle = NOAA published constituent speeds + Parker eq. 3.2. Oracle-backed.
@Suite("Constituent table vs NOAA")
struct ConstituentTableTests {

    /// The Doodson coefficients are the part of Schureman's Table 2 that OCR
    /// cannot be trusted for, so they are validated against NOAA's own `speed`
    /// field rather than a transcription.
    @Test("every Doodson coefficient set reproduces NOAA's published speed")
    func speedsMatchNOAA() {
        let o = Oracles.require("noaa-constituent-speeds")
        // NOAA speeds, verbatim from the harcon response for 9414290.
        let noaa: [String: Double] = [
            "M2": 28.984104, "S2": 30.0, "N2": 28.43973, "K1": 15.041069, "M4": 57.96821,
            "O1": 13.943035, "M6": 86.95232, "MK3": 44.025173, "S4": 60.0, "MN4": 57.423832,
            "NU2": 28.512583, "S6": 90.0, "MU2": 27.968208, "2N2": 27.895355, "OO1": 16.139101,
            "LAM2": 29.455626, "S1": 15.0, "M1": 14.496694, "J1": 15.5854435, "MM": 0.5443747,
            "SSA": 0.0821373, "SA": 0.0410686, "MSF": 1.0158958, "MF": 1.0980331,
            "RHO": 13.471515, "Q1": 13.398661, "T2": 29.958933, "R2": 30.041067,
            "2Q1": 12.854286, "P1": 14.958931, "2SM2": 31.015896, "M3": 43.47616,
            "L2": 29.528479, "2MK3": 42.92714, "K2": 30.082138, "M8": 115.93642,
            "MS4": 58.984104,
        ]
        #expect(noaa.count == 37)
        var worst = 0.0, worstName = ""
        for def in Constituents.all {
            guard let want = noaa[def.id.rawValue] else {
                Issue.record("no NOAA speed for \(def.id.rawValue)"); continue
            }
            let e = abs(def.speedDegPerHour - want)
            if e > worst { worst = e; worstName = def.id.rawValue }
        }
        #expect(o.matches("max_abs_error_deg_per_hour", worst),
                "worst speed error \(worst) deg/hr at \(worstName)")
    }

    /// Parker eq. 3.2 relates the Greenwich and local-meridian epochs. NOAA
    /// publishes both for every constituent, so this is a free Class-A check.
    @Test("Parker eq. 3.2 reproduces NOAA's published phase_local from phase_GMT")
    func epochConversionMatchesNOAA() {
        let o = Oracles.require("parker-eq32-epoch-9414290")
        // name, phase_GMT, phase_local -- verbatim from NOAA harcon for 9414290.
        let published: [(String, Double, Double)] = [
            ("M2", 208.2, 336.4), ("S2", 216.2, 336.2), ("N2", 183.2, 315.7),
            ("K1", 225.4, 105.1), ("M4", 136.8, 33.0), ("O1", 208.4, 96.8),
            ("M6", 7.3, 31.7), ("MK3", 124.1, 131.9), ("MN4", 112.0, 12.7),
            ("NU2", 189.9, 321.8), ("MU2", 100.2, 236.4), ("2N2", 153.3, 290.1),
            ("OO1", 260.0, 130.9), ("LAM2", 214.3, 338.6), ("S1", 282.6, 162.6),
            ("M1", 237.5, 121.5), ("J1", 244.3, 119.6), ("SSA", 272.3, 271.7),
            ("SA", 200.2, 199.9), ("MF", 153.1, 144.3), ("RHO", 200.0, 92.3),
            ("Q1", 202.4, 95.2), ("T2", 204.6, 325.0), ("R2", 126.8, 246.5),
            ("2Q1", 208.6, 105.7), ("P1", 222.1, 102.4), ("2SM2", 37.3, 149.1),
            ("M3", 37.6, 49.8), ("L2", 229.6, 353.4), ("2MK3", 92.2, 108.8),
            ("K2", 206.0, 325.3), ("M8", 108.5, 261.0), ("MS4", 149.0, 37.1),
        ]
        let timeMeridian = 120.0   // Pacific Standard Time meridian, deg west
        var worst = 0.0, worstName = ""
        for (name, gmt, local) in published {
            guard let def = Constituents.named(name) else {
                Issue.record("Kit does not define \(name)"); continue
            }
            let got = Epoch.localFromGreenwich(greenwichDeg: gmt,
                                               speedDegPerHour: def.speedDegPerHour,
                                               timeMeridianWestDeg: timeMeridian)
            let e = abs(Angle.normalizeSigned(got - local))
            if e > worst { worst = e; worstName = name }
        }
        #expect(o.matches("max_abs_error_deg", worst),
                "worst epoch-conversion error \(worst) deg at \(worstName)")
    }

    @Test("epoch conversions round-trip")
    func epochRoundTrip() {
        for def in Constituents.all {
            for g in stride(from: 0.0, to: 360.0, by: 37.0) {
                let local = Epoch.localFromGreenwich(greenwichDeg: g,
                                                     speedDegPerHour: def.speedDegPerHour,
                                                     timeMeridianWestDeg: 75)
                let back = Epoch.greenwichFromLocal(localDeg: local,
                                                    speedDegPerHour: def.speedDegPerHour,
                                                    timeMeridianWestDeg: 75)
                #expect(abs(Angle.normalizeSigned(back - g)) < 1e-9)
            }
        }
    }

    /// East longitude is the classic sign trap in eq. 3.2 (L is *west* longitude,
    /// so an eastern station carries a negative L).
    @Test("station/Greenwich epoch conversion handles east longitude")
    func eastLongitudeSignConvention() {
        let m2 = Constituents.named("M2")!
        let p = Epoch.species(m2)
        #expect(p == 2)
        // A station at 15 deg EAST => L = -15.
        let kappa = 100.0
        let G = Epoch.greenwichFromStation(stationDeg: kappa, species: p,
                                           stationWestLongitudeDeg: -15)
        #expect(abs(Angle.normalizeSigned(G - (kappa - 30))) < 1e-9)
        let back = Epoch.stationFromGreenwich(greenwichDeg: G, species: p,
                                              stationWestLongitudeDeg: -15)
        #expect(abs(Angle.normalizeSigned(back - kappa)) < 1e-9)
    }

    @Test("species matches each constituent's diurnal character")
    func speciesValues() {
        #expect(Epoch.species(Constituents.named("SA")!) == 0)
        #expect(Epoch.species(Constituents.named("MF")!) == 0)
        #expect(Epoch.species(Constituents.named("K1")!) == 1)
        #expect(Epoch.species(Constituents.named("O1")!) == 1)
        #expect(Epoch.species(Constituents.named("M2")!) == 2)
        #expect(Epoch.species(Constituents.named("M3")!) == 3)
        #expect(Epoch.species(Constituents.named("M4")!) == 4)
        #expect(Epoch.species(Constituents.named("M6")!) == 6)
        #expect(Epoch.species(Constituents.named("M8")!) == 8)
    }
}
