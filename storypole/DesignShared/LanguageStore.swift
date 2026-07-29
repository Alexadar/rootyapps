import SwiftUI

/// The app's language, shared by phone, Mac and watch through one `UserDefaults` key.
///
/// All user-facing text goes through `LocalizedStringKey`, never `String(localized:)` or
/// `NSLocalizedString` — those resolve against `Bundle.main`'s system language and ignore an
/// in-app override. Where text arrives as a `String` (a section's `rawValue`), call sites use
/// `Text(L.loc(title))`.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system = ""
    case en, de, fr, es, it, pt, nl, sv, pl, uk, ja, ko

    public var id: String { rawValue }

    /// Never translated — a language is listed in its own language.
    public var endonym: String? {
        switch self {
        case .system: return nil
        case .en: return "English"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .es: return "Español"
        case .it: return "Italiano"
        case .pt: return "Português"
        case .nl: return "Nederlands"
        case .sv: return "Svenska"
        case .pl: return "Polski"
        case .uk: return "Українська"
        case .ja: return "日本語"
        case .ko: return "한국어"
        }
    }

    public var locale: Locale? { self == .system ? nil : Locale(identifier: rawValue) }
}

@MainActor
public final class LanguageStore: ObservableObject {
    private static let key = "appLanguage"

    @Published public var selected: AppLanguage {
        didSet {
            UserDefaults.standard.set(selected.rawValue, forKey: Self.key)
            Fmt.locale = locale
        }
    }

    public init() {
        let env = LaunchOverride.value("STORYPOLE_LANG")
        let stored = UserDefaults.standard.string(forKey: Self.key)
        selected = AppLanguage(rawValue: env ?? stored ?? "") ?? .system
        Fmt.locale = locale
    }

    public var locale: Locale { selected.locale ?? .autoupdatingCurrent }
}

/// Wraps a runtime `String` as a `LocalizedStringKey` so it still honours the override.
public enum L {
    public static func loc(_ english: String) -> LocalizedStringKey { LocalizedStringKey(english) }
}
