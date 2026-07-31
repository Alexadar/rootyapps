import SwiftUI

/// The languages Overtone Lab ships. Ukrainian is included deliberately; Russian is not.
/// `es` serves both the Spain and Mexico storefronts — the UI wording is the same, only the
/// App Store metadata is split per region (and es-MX carries English keyword atoms, not a
/// translation — see marketing/ASO_AUDIT_2026-07-26.md).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case en, uk, de, fr, es, it, pl, cs, hu, ro, el, tr, nl, sv, ja, ko
    case ptBR = "pt-BR"

    var id: String { rawValue }

    /// Shown in its own language, never translated: someone hunting for this menu may not read
    /// the language the app is currently displaying. "System" is the one exception — it is a
    /// word about the device, not a language name, so it goes through the catalog.
    var endonym: String? {
        switch self {
        case .system: return nil
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

/// Holds the chosen language and persists it.
///
/// Applied by handing `locale` to `.environment(\.locale,)` at the app root: SwiftUI resolves
/// every `Text(LocalizedStringKey)` against the environment locale, so changing this re-renders
/// the whole tree in the new language **with no relaunch**. It also drives `.number` parsing in
/// `NumberField`, and `Fmt.locale` is kept in step so a printed result and a typed input never
/// disagree about the decimal separator.
///
/// First launch needs no detection: the default is `.system`, which is `.autoupdatingCurrent`.
///
/// The corollary is a rule the rest of the app must follow: user-facing text goes through
/// `LocalizedStringKey`, never `String(localized:)` or `NSLocalizedString` — those resolve
/// against `Bundle.main`'s system language and would silently ignore this override.
@MainActor
final class LanguageStore: ObservableObject {
    private static let key = "appLanguage"

    @Published var selected: AppLanguage {
        didSet {
            UserDefaults.standard.set(selected.rawValue, forKey: Self.key)
            Fmt.locale = locale
        }
    }

    init() {
        // OVERTONELAB_LANG pins the language for screenshots and reels without persisting it,
        // matching the OVERTONELAB_TOOL / OVERTONELAB_SCREEN capture convention.
        let env = LaunchOverride.value("OVERTONELAB_LANG")
        let saved = UserDefaults.standard.string(forKey: Self.key)
        selected = AppLanguage(rawValue: env ?? saved ?? "") ?? .system
        Fmt.locale = selected.locale ?? .autoupdatingCurrent
    }

    var locale: Locale { selected.locale ?? .autoupdatingCurrent }
}

/// Turns an English `String` that is already a catalog key into a catalog lookup.
///
/// Needed where the text arrives as a `String` rather than a literal — `ToolSection.rawValue`
/// ("Acoustics", "Timing") and the "Favorites" group title. `Text(someString)` renders verbatim
/// and would silently ship English, so those call sites use `Text(L.loc(title))` instead.
/// A missing key falls back to the English, so a partial catalog degrades rather than breaks.
enum L {
    static func loc(_ english: String) -> LocalizedStringKey { LocalizedStringKey(english) }
}
