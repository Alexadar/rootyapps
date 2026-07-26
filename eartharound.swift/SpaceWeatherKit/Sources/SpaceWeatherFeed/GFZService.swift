import Foundation
import HpoKit

/// Fetches the GFZ Potsdam Hp30 high-cadence geomagnetic index — the 30-minute
/// storm resolution that drives the hero chart.
public enum GFZService {

    private struct HpoResponse: Decodable {
        let Hp30: [Double?]?
        let datetime: [String]?
    }

    /// Last `hours` of Hp30 as time-ordered readings (null slots dropped). Fetches a
    /// week so the view can scroll back through recent storms without refetching.
    public static func hp30(hours: Double = 168, now: Date = Date()) async throws -> HpoPanel {
        let url = API.gfzHpo(index: "Hp30", start: now.addingTimeInterval(-hours * 3600), end: now)
        let r = try await Net.json(url, as: HpoResponse.self)
        guard let values = r.Hp30, let times = r.datetime else {
            return HpoPanel(readings: [], observedAt: nil)
        }
        var readings: [Hpo.Reading] = []
        for (t, v) in zip(times, values) {
            guard let v, let d = DateFmt.parseUTC(t) else { continue }
            readings.append(Hpo.Reading(time: d, value: v))
        }
        readings.sort { $0.time < $1.time }
        return HpoPanel(readings: readings, observedAt: readings.last?.time)
    }
}
