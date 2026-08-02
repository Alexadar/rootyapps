import SwiftUI
import AuroraKit

/// Bridging Kit prose into localized UI text, and resolving EVERY user-facing string against the
/// language the user actually picked.
///
/// The Kits deliberately still return English — that wording is oracle-tested against NOAA's
/// published scales and is the reference rendering. Rather than duplicate a mapping table, the
/// English string IS the String Catalog key, so `str(k.activity)` looks up "Quiet" and hands back
/// "Ruhig" / "Спокійно" / "静穏". If a key is ever missing the catalog falls back to the English,
/// which is the honest failure mode: the user sees a validated word, just not in their language.
///
/// WHY NOTHING HERE RETURNS `LocalizedStringKey`
///
/// It is tempting to hand SwiftUI a `LocalizedStringKey` and set `.environment(\.locale,)` at the
/// root. That does not work, and it fails in the most misleading way possible: `\.locale` decides
/// how INTERPOLATED VALUES are formatted, while the BUNDLE decides which localization is loaded.
/// With only the environment set, the app renders system-language text containing
/// chosen-language numbers — English words next to "1,0" — and nothing errors.
///
/// So every string is resolved here, explicitly, against `SWLanguage.sharedBundle`. `str` takes a
/// `String.LocalizationValue`, which is expressible by string interpolation, so call sites keep
/// reading like ordinary literals: `Panel(title: "Storm Right Now")`, `MeaningLine("Kp \(v) — …")`.
enum SWText {

    /// Resolve a catalog key — literal or interpolated — in the user's chosen language.
    nonisolated static func str(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: SWLanguage.sharedBundle, locale: SWLanguage.sharedLocale)
    }

    /// Kit prose (a runtime `String`) resolved immediately — for notification text and for
    /// values substituted into another format.
    nonisolated static func loc(_ english: String) -> String {
        str(String.LocalizationValue(english))
    }

    /// Kit prose wrapped as a KEY, for the component APIs that take a `String.LocalizationValue`
    /// and resolve it themselves. Resolving here instead would hand a component a finished
    /// sentence it would then try to look up again.
    nonisolated static func key(_ english: String) -> String.LocalizationValue {
        String.LocalizationValue(english)
    }

    /// Optional Kit prose with a localized fallback caption.
    nonisolated static func key(_ english: String?, fallback: String.LocalizationValue) -> String.LocalizationValue {
        english.map { String.LocalizationValue($0) } ?? fallback
    }

    /// The aurora view line, rebuilt from the latitude so the number is formatted for the reader's
    /// locale rather than baked into an English sentence by the Kit.
    nonisolated static func auroraViewLine(kp: Double) -> String.LocalizationValue {
        let lat = Int(Aurora.equatorwardGeomagLatitude(kp: kp).rounded())
        return "Aurora may be visible down to \(lat)° geomagnetic latitude."
    }

    /// The Kp meaning line. The forecast clause is a WHOLE alternative sentence rather than an
    /// English fragment interpolated into the middle — the old version spliced a raw `String`,
    /// which no catalog can reach, so that clause stayed English in every language.
    nonisolated static func kpMeaning(kp: String, activity: String, forecast: Bool) -> String.LocalizationValue {
        let word = loc(activity)          // resolved first: it is substituted INTO the sentence
        return forecast
            ? "Kp \(kp) — \(word). Faded bars are the NOAA 3-day forecast."
            : "Kp \(kp) — \(word)."
    }

    /// F10.7 caption. The level word is Kit prose, so it is resolved before substitution — a bare
    /// interpolation would have pasted the English word into a translated caption.
    nonisolated static func f107(_ level: String?) -> String.LocalizationValue {
        level.map { "F10.7 · \(loc($0))" } ?? "F10.7"
    }
}
