import Foundation

/// "Today" as the STATION reckons it.
///
/// Both tide and current screens carry a picked calendar date whose year/month/day is
/// reinterpreted at the station (`windowStart`), and whose `DatePicker` displays it through
/// the *device* calendar. So the picked date is a Y/M/D carrier, and the only correct
/// default is the station's current date expressed in that same carrier form.
///
/// Seeding it from `Calendar.current.startOfDay(for: Date())` — the device's date — was a
/// real, user-visible bug. With the device in UTC+3 and San Francisco in UTC-7 the device is
/// already on tomorrow's date for about ten hours of every day, and the screen then opened on
/// a 24 h window that did not contain `now`: the curve, the extremes table and the countdown
/// all described the following day while the hero height, computed at the true instant,
/// stayed correct — and `nowFraction` returned nil so the now-line silently vanished. An
/// internally inconsistent tide table is worse than an obviously broken one.
enum StationDay {

    /// The station's current calendar date, carried as a device-calendar `Date` with the same
    /// year/month/day — the form `windowStart` and the `DatePicker` both expect.
    static func today(in zone: TimeZone) -> Date {
        var stationCalendar = Calendar(identifier: .gregorian)
        stationCalendar.timeZone = zone
        let ymd = stationCalendar.dateComponents([.year, .month, .day], from: Date())
        return Calendar.current.date(from: DateComponents(year: ymd.year,
                                                          month: ymd.month,
                                                          day: ymd.day))
            ?? Calendar.current.startOfDay(for: Date())
    }
}
