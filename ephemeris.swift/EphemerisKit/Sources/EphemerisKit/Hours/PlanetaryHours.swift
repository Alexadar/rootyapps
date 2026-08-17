import Foundation

/// The planetary hours — twelve unequal hours of day, twelve of night, each ruled by a planet.
///
/// ## What makes this worth computing rather than tabulating
///
/// An "hour" here is a twelfth of the daylight, not sixty minutes. At high latitude in summer a day
/// hour can run past ninety minutes while the matching night hour falls under thirty, and the two
/// only coincide at the equinox on the geometric horizon. An implementation that divides the clock
/// into 60-minute blocks is not an approximation of this — it is a different, wrong system.
///
/// The **25th hour does not exist**: day and night each get exactly twelve and the sequence resets
/// at sunrise, never at midnight.
///
/// ## The two rules
///
/// Rulers cycle in **Chaldean order** — Saturn, Jupiter, Mars, Sun, Venus, Mercury, Moon — outward
/// through the classical spheres by decreasing period. The first hour of a day is ruled by that
/// weekday's planet, and from there the sequence simply advances, without a break at sunset.
///
/// Those two rules together are self-checking, which is what the oracle exploits: 24 hours advanced
/// through a 7-planet cycle lands 24 mod 7 = 3 places on, and stepping three places in Chaldean
/// order is exactly one weekday. Sunday→Monday, Monday→Tuesday, and so on all the way round. That
/// closure is why the weekday names are in this order in the first place, and an implementation that
/// assigns by clock hour cannot satisfy it.
public enum PlanetaryHours {

    /// Chaldean order: slowest apparent motion first. Saturn, Jupiter, Mars, Sun, Venus, Mercury,
    /// Moon — the classical planetary spheres, outermost inward.
    public static let chaldean: [CelestialBody] = [.saturn, .jupiter, .mars, .sun, .venus, .mercury, .moon]

    /// The planet ruling each weekday, indexed by `Calendar`'s weekday convention (1 = Sunday).
    ///
    /// This is not an independent table — it *is* the Chaldean cycle sampled every 24 hours, and the
    /// oracle asserts that rather than trusting the transcription.
    public static func weekdayRuler(_ weekday: Int) -> CelestialBody {
        switch weekday {
        case 1: .sun        // Sunday
        case 2: .moon       // Monday
        case 3: .mars       // Tuesday    — mardi, martes
        case 4: .mercury    // Wednesday  — mercredi, miércoles
        case 5: .jupiter    // Thursday   — jeudi, jueves
        case 6: .venus      // Friday     — vendredi, viernes
        default: .saturn    // Saturday
        }
    }

    /// One planetary hour.
    public struct Hour: Identifiable, Hashable, Sendable {
        /// 1...24. Hours 1–12 are daytime, 13–24 night.
        public let index: Int
        public let ruler: CelestialBody
        public let start: Date
        public let end: Date

        public var isDay: Bool { index <= 12 }
        public var duration: TimeInterval { end.timeIntervalSince(start) }
        public var id: String { "\(index)-\(start.timeIntervalSince1970)" }

        public func contains(_ date: Date) -> Bool { date >= start && date < end }
    }

    /// The twenty-four hours of the planetary day beginning at the sunrise of `date`.
    ///
    /// Returns nil when the division is undefined: no sunrise, no sunset, or no following sunrise
    /// at this latitude. Above the polar circles that is the honest answer — there is no daylight
    /// interval to divide into twelve, and inventing one would produce a confident, meaningless
    /// ruler for every hour of a day that has no dawn.
    ///
    /// The day runs **sunrise to sunrise**, so the caller's `date` selects the civil day whose
    /// sunrise opens the sequence; times before that sunrise belong to the previous planetary day.
    public static func hours(startingOn date: Date,
                             at location: GeoLocation,
                             timeZone: TimeZone) -> [Hour]? {
        guard let sunrise = RiseSet.time(of: .rise, body: .sun, on: date,
                                         at: location, timeZone: timeZone),
              let sunset = RiseSet.time(of: .set, body: .sun, on: date,
                                        at: location, timeZone: timeZone),
              sunset > sunrise
        else { return nil }

        // The night ends at the NEXT day's sunrise, which is a separate solve — using
        // sunrise + 24h would smear the night hours by the daily change in day length.
        let nextDay = date.addingTimeInterval(86_400)
        guard let nextSunrise = RiseSet.time(of: .rise, body: .sun, on: nextDay,
                                             at: location, timeZone: timeZone),
              nextSunrise > sunset
        else { return nil }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        // The weekday of the SUNRISE, not of `date`: they differ when the caller passes an instant
        // before dawn, and taking the wrong one shifts every ruler by a whole day.
        let weekday = cal.component(.weekday, from: sunrise)
        let firstRuler = weekdayRuler(weekday)
        guard let offset = chaldean.firstIndex(of: firstRuler) else { return nil }

        let dayHour = sunset.timeIntervalSince(sunrise) / 12.0
        let nightHour = nextSunrise.timeIntervalSince(sunset) / 12.0

        return (0..<24).map { i in
            let ruler = chaldean[(offset + i) % chaldean.count]
            let start: Date, end: Date
            if i < 12 {
                start = sunrise.addingTimeInterval(dayHour * Double(i))
                end   = sunrise.addingTimeInterval(dayHour * Double(i + 1))
            } else {
                start = sunset.addingTimeInterval(nightHour * Double(i - 12))
                end   = sunset.addingTimeInterval(nightHour * Double(i - 11))
            }
            return Hour(index: i + 1, ruler: ruler, start: start, end: end)
        }
    }

    /// The hour containing `date`, searching the planetary day that `date` falls in.
    ///
    /// Checks the previous civil day too, because an instant between midnight and sunrise belongs
    /// to the planetary day that began at *yesterday's* sunrise. Looking only at today is the
    /// "resets at midnight" bug the function documentation names.
    public static func current(at date: Date,
                               location: GeoLocation,
                               timeZone: TimeZone) -> Hour? {
        for dayOffset in [0.0, -86_400.0] {
            let probe = date.addingTimeInterval(dayOffset)
            if let hs = hours(startingOn: probe, at: location, timeZone: timeZone),
               let hit = hs.first(where: { $0.contains(date) }) {
                return hit
            }
        }
        return nil
    }
}
