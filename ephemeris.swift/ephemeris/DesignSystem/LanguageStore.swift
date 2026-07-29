import SwiftUI

/// The languages the app ships. `es` serves both the Spain and Mexico storefronts — the UI
/// wording is the same; only App Store metadata is split per region.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case en, uk, de, fr, es, it, pl, cs, hu, ro, el, tr, nl, sv, ja, ko
    case ptBR = "pt-BR"

    var id: String { rawValue }

    /// Shown in its own language, never translated: someone hunting for this menu may not read
    /// the language the app is currently displaying.
    var endonym: String {
        switch self {
        case .system: return "System"
        case .en:     return "English"
        case .uk:     return "Українська"
        case .de:     return "Deutsch"
        case .fr:     return "Français"
        case .es:     return "Español"
        case .it:     return "Italiano"
        case .pl:     return "Polski"
        case .cs:     return "Čeština"
        case .hu:     return "Magyar"
        case .ro:     return "Română"
        case .el:     return "Ελληνικά"
        case .tr:     return "Türkçe"
        case .nl:     return "Nederlands"
        case .sv:     return "Svenska"
        case .ja:     return "日本語"
        case .ko:     return "한국어"
        case .ptBR:   return "Português (Brasil)"
        }
    }

    /// nil = follow the device.
    var locale: Locale? { self == .system ? nil : Locale(identifier: rawValue) }
}

/// Holds the chosen language and persists it, following the `houseSystem` idiom in
/// `ChartViewModel` (raw string in `UserDefaults`, read back on init).
///
/// Applied by handing `locale` to `.environment(\.locale,)` at the app root: SwiftUI resolves
/// every `Text(LocalizedStringKey)` against the environment locale, so changing this re-renders
/// the whole tree in the new language **with no relaunch**.
///
/// The corollary is a rule the rest of the app must follow: user-facing text goes through
/// `LocalizedStringKey`, never `String(localized:)` or `NSLocalizedString` — those resolve
/// against `Bundle.main`'s system language and would silently ignore the override.
@MainActor
final class LanguageStore: ObservableObject {
    private static let key = "appLanguage"

    @Published var selected: AppLanguage {
        didSet { UserDefaults.standard.set(selected.rawValue, forKey: Self.key) }
    }

    init() {
        // EPHEMERIS_LANG pins the language for screenshots/reels without persisting —
        // matching the EPHEMERIS_TZ / EPHEMERIS_LAT / EPHEMERIS_PLACE convention.
        let env = ProcessInfo.processInfo.environment["EPHEMERIS_LANG"]
        let saved = UserDefaults.standard.string(forKey: Self.key)
        selected = AppLanguage(rawValue: env ?? saved ?? "") ?? .system
    }

    var locale: Locale { selected.locale ?? .autoupdatingCurrent }
}

/// Turns English text that came out of EphemerisKit into a String Catalog lookup.
///
/// The Kit deliberately keeps returning English: its strings double as dictionary keys, as
/// `Identifiable.id`s, as the `AspectColor` switch key and as the CSV/JSON export contract, so
/// translating them in place would break colours, event codes and saved data. Instead the English
/// string *is* the catalog key, and translation happens here at the view boundary.
///
///     Text(L.loc(sign.name))   // "Aries" → "Widder" / "Овен" / "牡羊座"
///
/// A missing key falls back to the English, so a partial catalog degrades rather than breaks.
enum L {
    static func loc(_ english: String) -> LocalizedStringKey { LocalizedStringKey(english) }

    /// Resolves a key to a plain `String` in a specific language.
    ///
    /// Needed only where the text must be *transformed* before display — the uppercased card
    /// headers — because `Text(LocalizedStringKey)` renders but can't be case-mapped, and
    /// `.textCase(.uppercase)` is ignored outside `List`/`Form`.
    ///
    /// `String(localized:locale:)` is the trap here and does **not** work: its `locale` argument
    /// only formats interpolations, it does not choose which `.lproj` to read, so it returns the
    /// system language and the override is silently lost. Selecting the language means loading
    /// that language's bundle explicitly, which is what this does.
    static func string(_ key: String, locale: Locale) -> String {
        guard let bundle = languageBundle(for: locale) else {
            return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// `Bundle(path:)` hits the filesystem, and headers re-resolve on every redraw — so cache.
    private static var bundles: [String: Bundle] = [:]

    private static func languageBundle(for locale: Locale) -> Bundle? {
        let id = locale.identifier
        if let cached = bundles[id] { return cached }
        // "pt_BR" (what Locale normalises to) has to be tried as "pt-BR", the .lproj spelling.
        var candidates = [id, id.replacingOccurrences(of: "_", with: "-")]
        if let base = locale.language.languageCode?.identifier { candidates.append(base) }
        for name in candidates {
            if let path = Bundle.main.path(forResource: name, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                bundles[id] = bundle
                return bundle
            }
        }
        return nil
    }
}
