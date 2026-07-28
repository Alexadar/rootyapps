import Foundation
import Observation
import TidesKit

/// View state for the watch Tides screen.
///
/// All math stays in TidesKit — this only chooses inputs, memoises, and formats. The one
/// derived quantity here is the countdown, which is plain calendar arithmetic on a Date the
/// Kit produced, not a physical prediction.
@Observable
final class WatchTidesModel {

    /// Persisted across launches so the watch opens on the station you actually use.
    /// `@Observable` doesn't wrap `@AppStorage`, so this reads/writes `UserDefaults` directly.
    var stationID: String {
        didSet {
            UserDefaults.standard.set(stationID, forKey: Self.stationKey)
            snapshot = nil
        }
    }

    var unit: TideUnit {
        didSet {
            UserDefaults.standard.set(unit.rawValue, forKey: Self.unitKey)
            snapshot = nil
        }
    }

    private static let stationKey = "marine.watch.station"
    private static let unitKey    = "marine.watch.unit"

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.stationKey)
        stationID = saved.flatMap { id in
            StationCatalog.tideStations.first { $0.id == id }?.id
        } ?? StationCatalog.tideStations[0].id
        unit = UserDefaults.standard.string(forKey: Self.unitKey)
            .flatMap(TideUnit.init(rawValue:)) ?? .feet
    }

    var record: TideStationRecord {
        StationCatalog.tideStations.first { $0.id == stationID } ?? StationCatalog.tideStations[0]
    }

    // MARK: Memoised prediction
    //
    // `Harmonics.extremes` over a day is ~370 height evaluations and `record.station(unit:)`
    // re-parses the station's constituent CSV on every call — both far too expensive to sit in
    // a computed property that a SwiftUI body touches several times per pass. The phone app hit
    // exactly this and fixed it the same way. One `Date()` is captured per snapshot so the
    // height, the trend and the countdown can never sample three different instants.

    struct Snapshot {
        let key: String
        let now: Date
        let height: Double
        let slope: Double
        let events: [TideEvent]

        /// The next high or low after `now`, or nil if the window somehow held none.
        var next: TideEvent? { events.first { $0.date > now } }
        var isRising: Bool { slope > 0 }
    }

    private var snapshot: Snapshot?

    /// Rebuild when the station, unit, or the minute changes — a watch face updates at most
    /// once a minute, so a finer key would recompute for no visible difference.
    func prediction(at now: Date = Date()) -> Snapshot {
        let minute = Int(now.timeIntervalSince1970 / 60)
        let key = "\(stationID)|\(unit.rawValue)|\(minute)"
        if let s = snapshot, s.key == key { return s }

        let station = record.station(unit: unit)
        // Start the search 6 h back so a turn that has just passed is still in the list, and
        // run 30 h forward so there is always a "next" even late in the day.
        let start = now.addingTimeInterval(-6 * 3600)
        let s = Snapshot(key: key,
                         now: now,
                         height: Harmonics.height(station, at: now),
                         slope: Harmonics.slope(station, at: now),
                         events: Harmonics.extremes(station, start: start, hours: 36))
        snapshot = s
        return s
    }

    // MARK: Formatting
    //
    // Tide times are ALWAYS rendered in the STATION's zone, never the watch's. Showing San
    // Francisco tides on a watch set to UTC is a navigational error, not a display preference.

    func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = record.timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// Short zone label for the station, e.g. "PDT" — always shown next to a time.
    var zoneLabel: String {
        let f = DateFormatter()
        f.timeZone = record.timeZone
        f.dateFormat = "zzz"
        return f.string(from: Date())
    }

    var unitLabel: String { unit == .feet ? "ft" : "m" }

    func countdown(to date: Date, from now: Date) -> String {
        let total = max(0, Int(date.timeIntervalSince(now)))
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
