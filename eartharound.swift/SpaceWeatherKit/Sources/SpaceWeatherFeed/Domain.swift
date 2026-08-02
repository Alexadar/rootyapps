import Foundation
import GeomagKit
import FlareKit
import SolarWindKit
import AuroraKit
import HpoKit
import SolarIndexKit

// The UI-facing snapshot. Every classification here is computed by a SpaceWeatherKit
// function that is oracle-tested against the published NOAA/GFZ definition — the app
// renders nothing the Kits can't validate.
//
// Everything is Codable: the last-good snapshot is persisted to the app group so the
// widget, watch app, and background task share one source of truth.

// MARK: - Planetary Kp (NOAA)

public struct KpSample: Identifiable, Equatable, Codable {
    public let time: Date
    public let kp: Double
    /// False only for NOAA's `observed` rows — the definitive measured index. Everything else,
    /// including the rows NOAA labels `estimated`, is a forecast. See `NOAAService.parseKp`.
    public let predicted: Bool
    public var id: Date { time }
    public var gScale: Int { Geomag.gScale(forKp: kp) }
    public var symbol: String { Geomag.step(forKp: kp).symbol }
    public init(time: Date, kp: Double, predicted: Bool) {
        self.time = time; self.kp = kp; self.predicted = predicted
    }
}

public struct KpPanel: Equatable, Codable {
    public let series: [KpSample]
    public let observedAt: Date?
    /// The newest MEASURED sample: never a forecast, and never future-dated.
    ///
    /// The time bound is not redundant with the `predicted` check. NOAA shipped forecast rows
    /// labelled in a way this code read as measurement, and with no clock comparison the app
    /// happily presented a 21:00 number at 10:35 as the current reading. The flag now maps
    /// correctly (`NOAAService.parseKp`), and this bound means the next source to blur that
    /// vocabulary still cannot put a future value under "now".
    public func nowSample(asOf date: Date = Date()) -> KpSample? {
        series.last { !$0.predicted && $0.time <= date }
    }
    /// Deliberately has no "else show a forecast" fallback: with no measurement there is no
    /// current value, and substituting a prediction is the very bug above in miniature.
    public var now: Double { nowSample()?.kp ?? 0 }
    public var gScale: Int { Geomag.gScale(forKp: now) }
    public var activity: String { Geomag.activity(forKp: now) }
    public var ap: Int { Geomag.ap(forKp: now) }

    /// Highest MEASURED Kp of the 24 h ending at the newest measurement — a peak is something
    /// that happened, so both ends of the window are bounded. Only the lower end used to be,
    /// which is how this reported 5.67 from a row that had not occurred yet.
    ///
    /// Anchored to the newest measured sample rather than to `date` itself, so the same series
    /// always yields the same peak — that determinism is what keeps the widget from flickering
    /// between timeline renders.
    public func peak24h(asOf date: Date = Date()) -> Double? {
        guard let end = nowSample(asOf: date)?.time else { return nil }
        let cutoff = end.addingTimeInterval(-24 * 3600)
        return series.filter { !$0.predicted && $0.time >= cutoff && $0.time <= end }.map(\.kp).max()
    }
    public init(series: [KpSample], observedAt: Date?) {
        self.series = series; self.observedAt = observedAt
    }
}

// MARK: - Solar flares & X-ray flux (NOAA GOES)

public struct FluxSample: Identifiable, Equatable, Codable {
    public let time: Date
    public let flux: Double            // W/m², 0.1–0.8 nm long band
    public var id: Date { time }
    public var label: String { Flare.classify(fluxWm2: flux).label }
    public init(time: Date, flux: Double) { self.time = time; self.flux = flux }
}

public struct FlareEvent: Equatable, Codable {
    public let maxClass: String
    public let maxTime: Date?
    public let beginTime: Date?
    public var rScale: Int { Flare.rScale(forClass: maxClass) }
    public var meaning: String { Flare.meaning(forClass: maxClass) }
    public init(maxClass: String, maxTime: Date?, beginTime: Date?) {
        self.maxClass = maxClass; self.maxTime = maxTime; self.beginTime = beginTime
    }
}

public struct FlarePanel: Equatable, Codable {
    public let fluxSeries: [FluxSample]
    public let latestFlare: FlareEvent?
    /// Flares that peaked in the last 24 hours, newest first.
    ///
    /// Optional, and that is deliberate: synthesized `Codable` THROWS on a missing key for a
    /// non-optional property, so adding one would make every snapshot already persisted in the
    /// app group fail to decode — on upgrade the app would look like it had lost its data.
    /// An optional decodes to nil instead.
    public let recentFlares: [FlareEvent]?
    public let observedAt: Date?
    public var currentFlux: Double { fluxSeries.last?.flux ?? 0 }
    public var currentClass: String { Flare.classify(fluxWm2: currentFlux).label }
    public var rScale: Int { Flare.rScale(fluxWm2: currentFlux) }

    /// Strongest flare of the last 24 h, ordered by peak flux — so M9.9 beats M1.0 and X1.0
    /// beats both. `Flare.flux(forClass:)` is the same parser the Kit already oracle-tests.
    public var peak24h: FlareEvent? {
        (recentFlares ?? []).max {
            (Flare.flux(forClass: $0.maxClass) ?? 0) < (Flare.flux(forClass: $1.maxClass) ?? 0)
        }
    }
    public var count24h: Int { (recentFlares ?? []).count }

    public init(fluxSeries: [FluxSample], latestFlare: FlareEvent?,
                recentFlares: [FlareEvent]? = nil, observedAt: Date?) {
        self.fluxSeries = fluxSeries; self.latestFlare = latestFlare
        self.recentFlares = recentFlares; self.observedAt = observedAt
    }
}

// MARK: - Solar wind (NOAA DSCOVR/ACE)

public struct SolarWindPanel: Equatable, Codable {
    public let speed: Double?
    public let density: Double?
    public let bt: Double?
    public let bz: Double?
    public let observedAt: Date?

    public var pressure: Double? {
        guard let n = density, let v = speed else { return nil }
        return SolarWind.dynamicPressure(density: n, speed: v)
    }
    public var electricField: Double? {
        guard let v = speed, let b = bz else { return nil }
        return SolarWind.southwardField(speed: v, bz: b)
    }
    public var level: SolarWind.Level { SolarWind.level(bz: bz ?? 0, speed: speed ?? 0) }
    public var coupling: SolarWind.Coupling {
        SolarWind.coupling(.init(bt: bt, bz: bz, speed: speed, density: density))
    }
    public var speedDescription: String? { speed.map { SolarWind.speedDescription($0) } }
    public init(speed: Double?, density: Double?, bt: Double?, bz: Double?, observedAt: Date?) {
        self.speed = speed; self.density = density; self.bt = bt; self.bz = bz; self.observedAt = observedAt
    }
}

// MARK: - Aurora (NOAA OVATION + Kp view line)

public struct AuroraPanel: Equatable, Codable {
    public let maxProbability: Int
    public let kp: Double
    public let observedAt: Date?
    public var viewLineLatitude: Double { Aurora.equatorwardGeomagLatitude(kp: kp) }
    public var viewLine: String { Aurora.viewLineDescription(kp: kp) }
    public init(maxProbability: Int, kp: Double, observedAt: Date?) {
        self.maxProbability = maxProbability; self.kp = kp; self.observedAt = observedAt
    }
}

// MARK: - NOAA scales (G/R/S)

public struct ScalesPanel: Equatable, Codable {
    public let g: Int
    public let r: Int
    public let s: Int
    public let observedAt: Date?
    public var gLabel: String { Geomag.gLabel(g) }
    public var rLabel: String { Flare.rLabel(r) }
    public init(g: Int, r: Int, s: Int, observedAt: Date?) {
        self.g = g; self.r = r; self.s = s; self.observedAt = observedAt
    }
}

// MARK: - Solar activity (NOAA sunspot regions + F10.7)

public struct SolarPanel: Equatable, Codable {
    public let sunspotNumber: Int?
    public let f107: Double?
    public let regionCount: Int?
    public let observedAt: Date?
    public var activity: String? { sunspotNumber.map { SolarIndex.activity(sunspotNumber: Double($0)) } }
    public var f107Level: String? { f107.map { SolarIndex.f107Level($0) } }
    public init(sunspotNumber: Int?, f107: Double?, regionCount: Int?, observedAt: Date?) {
        self.sunspotNumber = sunspotNumber; self.f107 = f107; self.regionCount = regionCount; self.observedAt = observedAt
    }
}

// MARK: - Hp30 high-cadence (GFZ) — the hero

public struct HpoPanel: Equatable, Codable {
    public let readings: [Hpo.Reading]
    public let observedAt: Date?
    public var latest: Double? { readings.last?.value }
    public var latestGScale: Int? { latest.map { Hpo.gScale(forHp: $0) } }
    public var exceedsCeiling: Bool { latest.map { Hpo.exceedsKpCeiling($0) } ?? false }
    public init(readings: [Hpo.Reading], observedAt: Date?) {
        self.readings = readings; self.observedAt = observedAt
    }
}

// MARK: - Aggregate snapshot

public struct SpaceWeatherSnapshot: Equatable, Codable {
    public var kp: KpPanel?
    public var flare: FlarePanel?
    public var wind: SolarWindPanel?
    public var aurora: AuroraPanel?
    public var scales: ScalesPanel?
    public var solar: SolarPanel?
    public var hpo: HpoPanel?
    public init() {}
}
