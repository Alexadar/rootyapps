import SwiftUI

/// Value + data-age formatting. Staleness is shown honestly everywhere.
///
/// Every displayed QUANTITY is formatted for the reader's locale — a German or Ukrainian reader
/// expects "1,7", and `String(format:)` is POSIX, so it always produced "1.7". The locale comes
/// from the app group rather than `Locale.current`, because the in-app language picker must move
/// the numbers too, and the widget/complication have no `\.locale` environment to read.
///
/// Identifiers deliberately stay POSIX and are NOT routed through here: flare class magnitudes
/// (M3.2), Bartels symbols (5+), scale codes (G1) and the network date parsers. Those are codes
/// that happen to look like numbers, and localizing them would corrupt them.
enum Fmt {
    private static var locale: Locale { SWLanguage.sharedLocale }

    private static var rel: RelativeDateTimeFormatter {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.locale = locale
        return f
    }

    static func age(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return SWText.str("no data") }
        // Under a minute the relative formatter says "in 0 sec" — future tense for data we
        // already have. NOAA/GFZ stamps can also sit a few seconds ahead of the device clock,
        // which pushes it further into the future. Both read as broken; say "just now".
        guard now.timeIntervalSince(date) >= 60 else { return SWText.str("just now") }
        return rel.localizedString(for: date, relativeTo: now)
    }

    /// True when the observation is older than `maxAge` (default 2 h) — flag it in the UI.
    static func isStale(_ date: Date?, maxAge: TimeInterval = 7200, now: Date = Date()) -> Bool {
        guard let date else { return true }
        return now.timeIntervalSince(date) > maxAge
    }

    static func num(_ v: Double?, _ decimals: Int = 1, dash: String = "—") -> String {
        guard let v else { return dash }
        return v.formatted(.number.precision(.fractionLength(decimals)).locale(locale))
    }

    static func int(_ v: Int?, dash: String = "—") -> String {
        guard let v else { return dash }
        return v.formatted(.number.locale(locale))
    }

    /// Scientific X-ray flux, e.g. 3.1e-6. The mantissa is a quantity and takes the locale's
    /// decimal separator; the exponent notation itself is universal.
    static func flux(_ v: Double) -> String {
        v.formatted(.number.notation(.scientific).precision(.fractionLength(1)).locale(locale))
    }
}
