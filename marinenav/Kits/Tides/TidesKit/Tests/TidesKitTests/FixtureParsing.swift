import Foundation
@testable import TidesKit

/// Parsers for the verbatim NOAA fixtures in `Fixtures.swift`.
/// No expected values live here — only the shape of NOAA's own output.
enum Parse {

    static func utc(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        guard let d = f.date(from: s) else { fatalError("bad fixture date '\(s)'") }
        return d
    }

    /// `name,amplitude,phase_GMT` — skips constituents this Kit does not define.
    static func constituents(_ csv: String) -> [Constituent] {
        csv.split(separator: "\n").compactMap { line in
            let p = line.split(separator: ",", omittingEmptySubsequences: false)
            guard p.count == 3,
                  let amp = Double(p[1]), let ph = Double(p[2]) else { return nil }
            return Constituent(name: String(p[0]), amplitude: amp, greenwichPhaseDeg: ph)
        }
    }

    /// `MSL,x` / `MLLW,y` → Z₀ = MSL − MLLW.
    static func datums(_ csv: String) -> (msl: Double, mllw: Double, z0: Double) {
        var d: [String: Double] = [:]
        for line in csv.split(separator: "\n") {
            let p = line.split(separator: ",")
            if p.count == 2, let v = Double(p[1]) { d[String(p[0])] = v }
        }
        guard let msl = d["MSL"], let mllw = d["MLLW"] else {
            fatalError("fixture datums missing MSL/MLLW")
        }
        return (msl, mllw, msl - mllw)
    }

    /// `yyyy-MM-dd HH:mm,value`
    static func series(_ csv: String) -> [(date: Date, value: Double)] {
        csv.split(separator: "\n").compactMap { line in
            let p = line.split(separator: ",")
            guard p.count >= 2, let v = Double(p[1]) else { return nil }
            return (utc(String(p[0])), v)
        }
    }

    /// `yyyy-MM-dd HH:mm,velocity,slack|flood|ebb`
    static func currentEvents(_ csv: String) -> [(date: Date, value: Double, phase: CurrentPhase)] {
        csv.split(separator: "\n").compactMap { line in
            let p = line.split(separator: ",")
            guard p.count >= 3, let v = Double(p[1]) else { return nil }
            let phase: CurrentPhase
            switch p[2] {
            case "slack": phase = .slack
            case "flood": phase = .flood
            case "ebb":   phase = .ebb
            default:      return nil
            }
            return (utc(String(p[0])), v, phase)
        }
    }

    /// `yyyy-MM-dd HH:mm,value,H|L`
    static func hilo(_ csv: String) -> [(date: Date, value: Double, kind: TideKind)] {
        csv.split(separator: "\n").compactMap { line in
            let p = line.split(separator: ",")
            guard p.count >= 3, let v = Double(p[1]) else { return nil }
            return (utc(String(p[0])), v, p[2] == "H" ? .high : .low)
        }
    }
}

/// Stations assembled from the embedded NOAA fixtures.
enum FixtureStations {

    static func station(id: String, name: String, unit: TideUnit,
                        harcon: String, datums: String) -> Station {
        let d = Parse.datums(datums)
        return Station(id: id, name: name, unit: unit, meanWaterLevel: d.z0,
                       constituents: Parse.constituents(harcon))
    }

    static var sanFranciscoMetric: Station {
        station(id: "9414290", name: "San Francisco, CA", unit: .meters,
                harcon: Fixtures.sfHarconMetric, datums: Fixtures.sfDatumsMetric)
    }

    static var sanFranciscoFeet: Station {
        station(id: "9414290", name: "San Francisco, CA", unit: .feet,
                harcon: Fixtures.sfHarconEnglish, datums: Fixtures.sfDatumsEnglish)
    }

    static var galvestonMetric: Station {
        station(id: "8771450", name: "Galveston Pier 21, TX", unit: .meters,
                harcon: Fixtures.galvestonHarconMetric, datums: Fixtures.galvestonDatumsMetric)
    }

    /// The station's non-tidal mean flow comes from NOAA's **published**
    /// `majorMeanSpeed`, not from the mean of NOAA's own predictions — deriving it
    /// from the answer would make this test partly self-referential.
    static var pollockRip: CurrentStation {
        let mean = Double(Fixtures.currentMeanFlowCMS.trimmingCharacters(in: .whitespacesAndNewlines))!
        return CurrentStation(id: "ACT1616", name: "Pollock Rip Channel (Butler Hole)", bin: 1,
                              meanFloodDirectionDeg: 37, meanEbbDirectionDeg: 226,
                              meanFlowCMS: mean,
                              constituents: Parse.constituents(Fixtures.currentHarcon))
    }
}
