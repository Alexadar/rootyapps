import Foundation

/// Clock and time math for the cockpit: HMS ↔ decimal hours and local ↔ Zulu (UTC).
public enum FlightTime {

    /// Hours-minutes-seconds → decimal hours.
    public static func hmsToDecimalHr(h: Int, m: Int, s: Int) -> Double {
        Double(h) + Double(m) / 60 + Double(s) / 3600
    }

    /// Decimal hours → (h, m, s), seconds rounded to the nearest second.
    public static func decimalHrToHMS(_ hours: Double) -> (h: Int, m: Int, s: Int) {
        let totalSeconds = Int((hours * 3600).rounded())
        return (totalSeconds / 3600, (totalSeconds % 3600) / 60, totalSeconds % 60)
    }

    /// Zulu (UTC) hour-of-day from a local hour and the location's UTC offset.
    /// e.g. local 08:00 at UTC−5 → 13:00 Z.
    public static func zuluHour(localHour: Double, utcOffsetHr: Double) -> Double {
        var z = (localHour - utcOffsetHr).truncatingRemainder(dividingBy: 24)
        if z < 0 { z += 24 }
        return z
    }

    /// Local hour-of-day from a Zulu hour and the location's UTC offset.
    public static func localHour(zuluHour: Double, utcOffsetHr: Double) -> Double {
        var l = (zuluHour + utcOffsetHr).truncatingRemainder(dividingBy: 24)
        if l < 0 { l += 24 }
        return l
    }
}
