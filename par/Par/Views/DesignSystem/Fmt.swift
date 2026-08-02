import Foundation

/// Every number the user sees goes through here. Views format; they never calculate.
public enum Fmt {

    private static func fixed(_ digits: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        f.usesGroupingSeparator = true
        return f
    }

    /// Money, always two places, grouped. Minus sign, never parentheses, never red.
    public static func money(_ value: Double, digits: Int = 2) -> String {
        fixed(digits).string(from: NSNumber(value: value)) ?? "—"
    }

    /// A rate as a percentage. `digits` follows the convention in force
    /// (bond yields quote to three, APR to two).
    public static func percent(_ value: Double, digits: Int = 3) -> String {
        (fixed(digits).string(from: NSNumber(value: value)) ?? "—") + "%"
    }

    public static func count(_ value: Double) -> String {
        fixed(0).string(from: NSNumber(value: value)) ?? "—"
    }

    public static func price(_ value: Double, digits: Int = 3) -> String {
        fixed(digits).string(from: NSNumber(value: value)) ?? "—"
    }

    /// The direction words that carry sign instead of colour.
    public static func direction(_ value: Double) -> String {
        value < 0 ? "cash out" : value > 0 ? "cash in" : "no flow"
    }

    /// VoiceOver reads meaning, not glyphs: "present value, 420,000 dollars".
    public static func spokenMoney(_ value: Double, label: String, currency: String = "dollars") -> String {
        let magnitude = money(abs(value), digits: 2)
        let sense = value < 0 ? "negative " : ""
        return "\(label), \(sense)\(magnitude) \(currency)"
    }

    /// `digits` must match what the screen displays.
    ///
    /// A combined accessibility card publishes this string as its `label`, and that label is the only
    /// readable text a UI test gets for the number inside it — the value `Text` itself has no
    /// identifier. When the two precisions disagree the test compares "40.00%" against "40.000%" and
    /// fails on a rounding difference that no user could ever see. Default 3 matches `percent`'s own
    /// default, so only the screens that display something else need to say so.
    public static func spokenPercent(_ value: Double, label: String, digits: Int = 3) -> String {
        "\(label), \(percent(value, digits: digits)) percent"
    }
}
