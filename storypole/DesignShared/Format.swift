import Foundation

/// Every displayed number goes through here.
///
/// Grouping separators are OFF by default: a measurement is not an amount of money, and "1,234"
/// reads badly beside a fraction. Rounding is pinned so display never disagrees with the Kits.
public enum Fmt {
    /// Follows the app's language choice, set by `LanguageStore`.
    nonisolated(unsafe) public static var locale: Locale = .autoupdatingCurrent

    /// Fixed decimal places.
    public static func f(_ v: Double, _ places: Int = 2) -> String {
        let n = NumberFormatter()
        n.locale = locale
        n.numberStyle = .decimal
        n.usesGroupingSeparator = false
        n.minimumFractionDigits = places
        n.maximumFractionDigits = places
        n.roundingMode = .halfEven          // matches DimensionKit's default RoundingRule
        return n.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    /// Trims trailing zeros — for values that are usually whole.
    public static func trim(_ v: Double, _ places: Int = 2) -> String {
        abs(v - v.rounded()) < 1e-9 ? f(v, 0) : f(v, places)
    }

    /// A count, with grouping — the one place separators help.
    public static func count(_ v: Int) -> String {
        let n = NumberFormatter()
        n.locale = locale
        n.numberStyle = .decimal
        return n.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    /// Degrees.
    public static func deg(_ v: Double, _ places: Int = 2) -> String { f(v, places) + "°" }

    /// A percentage.
    public static func pct(_ v: Double, _ places: Int = 1) -> String { f(v, places) + " %" }
}
