import Foundation
import GeomagKit

/// GFZ Hpo high-cadence geomagnetic indices (Hp30 / Hp60) — the 30-minute storm
/// resolution the competition lacks.
///
/// Hpo is an open-ended sibling of Kp on the same amplitude scale, sampled every
/// 30 or 60 minutes. Unlike Kp it is NOT capped at 9 (extreme storms exceed it).
/// This Kit fixes the UT-day structure (48 half-hour slots/day for Hp30, 24/day for
/// Hp60), buckets and windows the stream for the chart, and classifies each value
/// via the shared Bartels/NOAA definitions. Pure, deterministic, oracle-tested.
public enum Hpo {

    public enum Cadence: Sendable {
        case hp30, hp60
        public var minutes: Int { self == .hp30 ? 30 : 60 }
        /// Number of intervals in one UT day (48 for Hp30, 24 for Hp60).
        public var slotsPerDay: Int { 24 * 60 / minutes }
    }

    /// One high-cadence reading: its UT timestamp and open-scale value.
    public struct Reading: Equatable, Sendable, Codable {
        public let time: Date
        public let value: Double
        public init(time: Date, value: Double) { self.time = time; self.value = value }
    }

    /// One UT day's worth of readings, slotted into a fixed-length array (nil = gap).
    public struct DayBucket: Equatable, Sendable {
        public let utDayStart: Date
        public let values: [Double?]
    }

    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Start of the UT day (00:00 UTC) containing `date`.
    public static func utDayStart(for date: Date) -> Date { utc.startOfDay(for: date) }

    /// Slot index within the UT day for `date` (0…slotsPerDay-1).
    public static func slotIndex(for date: Date, cadence: Cadence) -> Int {
        let secs = date.timeIntervalSince(utDayStart(for: date))
        return min(cadence.slotsPerDay - 1, Int(secs / Double(cadence.minutes * 60)))
    }

    /// Bucket readings into fixed-length UT days, honoring the 00:00 UTC boundary.
    public static func groupByUTDay(_ readings: [Reading], cadence: Cadence) -> [DayBucket] {
        var days: [Date: [Double?]] = [:]
        for r in readings {
            let start = utDayStart(for: r.time)
            var slots = days[start] ?? Array(repeating: nil, count: cadence.slotsPerDay)
            slots[slotIndex(for: r.time, cadence: cadence)] = r.value
            days[start] = slots
        }
        return days.keys.sorted().map { DayBucket(utDayStart: $0, values: days[$0]!) }
    }

    /// Rolling window: readings in (`endingAt` − `hours`, `endingAt`], time-sorted.
    /// This is what feeds the 30-minute chart.
    public static func window(_ readings: [Reading], hours: Double, endingAt end: Date) -> [Reading] {
        let start = end.addingTimeInterval(-hours * 3600)
        return readings.filter { $0.time > start && $0.time <= end }
            .sorted { $0.time < $1.time }
    }

    // MARK: - Classification (shared Bartels / NOAA definitions)

    /// NOAA G-scale for an Hpo value. Hpo is open-ended but the G-scale saturates at G5 (Kp≥9).
    public static func gScale(forHp hp: Double) -> Int { Geomag.gScale(forKp: hp) }

    /// Bartels ap-equivalent within the published 0…9 range, via the shared 28-step table.
    /// Returns nil above 9, which lies beyond the standard published table (don't fabricate).
    public static func apEquivalent(forHp hp: Double) -> Int? {
        guard hp <= 9.0 else { return nil }
        return Geomag.ap(forKp: hp)
    }

    /// True when the value exceeds the standard Kp ceiling — Hpo's reason to exist.
    public static func exceedsKpCeiling(_ hp: Double) -> Bool { hp > 9.0 }
}
