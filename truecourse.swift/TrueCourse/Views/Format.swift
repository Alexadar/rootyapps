import Foundation

/// Number formatting helpers. Aviation readouts are monospaced, tabular figures.
enum Fmt {
    static func f(_ x: Double, _ places: Int = 2) -> String { String(format: "%.\(places)f", x) }
    static func i(_ x: Double) -> String { String(format: "%.0f", x.rounded()) }
    static func signed(_ x: Double, _ places: Int = 0) -> String { String(format: "%+.\(places)f", x) }

    /// A compass heading padded to three digits with a degree sign, e.g. `007°`.
    static func heading(_ deg: Double) -> String {
        var d = deg.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return String(format: "%03d°", Int(d.rounded()) % 360)
    }

    /// Hours-minutes from decimal hours, e.g. `1:15`.
    static func hoursMinutes(_ hours: Double) -> String {
        let total = Int((hours * 60).rounded())
        return String(format: "%d:%02d", total / 60, abs(total % 60))
    }

    /// Minutes-seconds from a minute count, e.g. `12:30`.
    static func minutesSeconds(_ minutes: Double) -> String {
        let total = Int((minutes * 60).rounded())
        return String(format: "%d:%02d", total / 60, abs(total % 60))
    }
}
