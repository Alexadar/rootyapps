import Foundation
import AuroraKit

/// Fetches NOAA SWPC feeds, decodes raw records, and hands the numbers to the Kits.
/// Each method returns a Kit-classified panel; the views never see a raw JSON field.
public enum NOAAService {

    // MARK: Planetary Kp (observed + 3-day forecast)

    private struct KpRow: Decodable {
        let time_tag: String
        let kp: Double
        let observed: String?
    }
    public static func kp() async throws -> KpPanel {
        let rows = try await Net.json(API.kpForecast, as: [KpRow].self)
        let samples: [KpSample] = rows.compactMap { r in
            guard let t = DateFmt.parseUTC(r.time_tag) else { return nil }
            return KpSample(time: t, kp: r.kp, predicted: (r.observed ?? "") != "observed")
        }
        let lastObserved = samples.last(where: { !$0.predicted })?.time
        return KpPanel(series: samples, observedAt: lastObserved)
    }

    // MARK: X-ray flux + latest flare

    private struct XRay: Decodable { let time_tag: String; let flux: Double; let energy: String }
    private struct FlareLatest: Decodable {
        let max_class: String?; let max_time: String?; let begin_time: String?
    }
    public static func flares() async throws -> FlarePanel {
        async let xrayData = Net.json(API.xrays1Day, as: [XRay].self)
        async let flareData = Net.json(API.flaresLatest, as: [FlareLatest].self)

        let series: [FluxSample] = try await xrayData
            .filter { $0.energy == "0.1-0.8nm" }
            .compactMap { x in DateFmt.parseUTC(x.time_tag).map { FluxSample(time: $0, flux: x.flux) } }

        let latest = try await flareData.first { $0.max_class != nil }
        let event = latest.flatMap { l -> FlareEvent? in
            guard let cls = l.max_class else { return nil }
            return FlareEvent(maxClass: cls,
                              maxTime: l.max_time.flatMap(DateFmt.parseUTC),
                              beginTime: l.begin_time.flatMap(DateFmt.parseUTC))
        }
        return FlarePanel(fluxSeries: series, latestFlare: event, observedAt: series.last?.time)
    }

    // MARK: Solar wind (freshest summary values + latest density)

    private struct MagSummary: Decodable { let bt: Double?; let bz_gsm: Double?; let time_tag: String }
    private struct SpeedSummary: Decodable { let proton_speed: Double?; let time_tag: String }
    private struct WindRow: Decodable { let proton_density: Double? }
    public static func solarWind() async throws -> SolarWindPanel {
        async let magData = Net.json(API.magSummary, as: [MagSummary].self)
        async let speedData = Net.json(API.speedSummary, as: [SpeedSummary].self)
        async let windData = Net.json(API.windRTSW, as: [WindRow].self)

        let mag = try await magData.first
        let speed = try await speedData.first
        let density = try await windData.last(where: { $0.proton_density != nil })?.proton_density

        let at = [mag?.time_tag, speed?.time_tag].compactMap { $0 }.compactMap(DateFmt.parseUTC).max()
        return SolarWindPanel(speed: speed?.proton_speed, density: density,
                              bt: mag?.bt, bz: mag?.bz_gsm, observedAt: at)
    }

    // MARK: NOAA scales (G/R/S) — key "0" is the current level

    private struct ScaleLevel: Decodable { let Scale: String? }
    private struct ScaleDay: Decodable { let R: ScaleLevel?; let S: ScaleLevel?; let G: ScaleLevel?; let TimeStamp: String?; let DateStamp: String? }
    public static func scales() async throws -> ScalesPanel {
        let days = try await Net.json(API.scales, as: [String: ScaleDay].self)
        let now = days["0"]
        func lvl(_ s: ScaleLevel?) -> Int { Int(s?.Scale ?? "0") ?? 0 }
        let at = [now?.DateStamp, now?.TimeStamp].compactMap { $0 }
        let stamp = at.count == 2 ? DateFmt.parseUTC("\(at[0])T\(at[1])") : nil
        return ScalesPanel(g: lvl(now?.G), r: lvl(now?.R), s: lvl(now?.S), observedAt: stamp)
    }

    // MARK: Aurora (OVATION max probability)

    private struct Ovation: Decodable {
        let coordinates: [[Double]]
        let observationTime: String?
        enum CodingKeys: String, CodingKey { case coordinates; case observationTime = "Observation Time" }
    }
    /// Returns max aurora probability and the observation time. Kp view-line is composed
    /// at the store level (needs the Kp panel).
    public static func auroraProbability() async throws -> (max: Int, at: Date?) {
        let o = try await Net.json(API.ovation, as: Ovation.self)
        let cells = o.coordinates.compactMap { c -> Aurora.OvationCell? in
            guard c.count == 3 else { return nil }
            return Aurora.OvationCell(longitude: c[0], latitude: c[1], probability: Int(c[2]))
        }
        return (Aurora.maxProbability(in: cells), o.observationTime.flatMap(DateFmt.parseUTC))
    }

    // MARK: Solar activity (F10.7 + sunspot regions → Wolf number)

    private struct F107Row: Decodable { let time_tag: String; let flux: Double? }
    private struct Region: Decodable { let observed_date: String?; let number_spots: Int? }
    public static func solarActivity() async throws -> SolarPanel {
        async let f107Data = Net.json(API.f107, as: [F107Row].self)
        async let regionData = Net.json(API.solarRegions, as: [Region].self)

        let f107 = try await f107Data.first?.flux

        // Current sunspot number: Wolf R = 10·g + s over the regions of the latest observed date.
        let regions = try await regionData
        var sunspot: Int? = nil, count: Int? = nil
        if let latestDate = regions.compactMap({ $0.observed_date }).max() {
            let today = regions.filter { $0.observed_date == latestDate }
            let g = today.count
            let s = today.compactMap { $0.number_spots }.reduce(0, +)
            sunspot = 10 * g + s
            count = g
        }
        let at = (try await f107Data.first?.time_tag).flatMap(DateFmt.parseUTC)
        return SolarPanel(sunspotNumber: sunspot, f107: f107, regionCount: count, observedAt: at)
    }
}
