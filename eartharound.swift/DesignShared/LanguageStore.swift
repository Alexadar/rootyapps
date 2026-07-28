import SwiftUI
import Combine
import SpaceWeatherFeed

/// The 18 shipped languages plus "follow the system". Ukrainian is in; Russian is deliberately not.
///
/// Each case carries its own endonym — a language picker that lists "German" to a German speaker is
/// useless, since the person who needs to change it may not read the current language at all.
enum SWLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case en, uk, de, fr, es, it
    case ptBR = "pt-BR"
    case nl, sv, nb, da, fi, pl, cs, tr, ja, ko
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"

    var id: String { rawValue }

    /// Shown in its own language, never translated.
    var endonym: String {
        switch self {
        case .system: return "System"
        case .en:     return "English"
        case .uk:     return "Українська"
        case .de:     return "Deutsch"
        case .fr:     return "Français"
        case .es:     return "Español"
        case .it:     return "Italiano"
        case .ptBR:   return "Português (Brasil)"
        case .nl:     return "Nederlands"
        case .sv:     return "Svenska"
        case .nb:     return "Norsk bokmål"
        case .da:     return "Dansk"
        case .fi:     return "Suomi"
        case .pl:     return "Polski"
        case .cs:     return "Čeština"
        case .tr:     return "Türkçe"
        case .ja:     return "日本語"
        case .ko:     return "한국어"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        }
    }

    /// nil for `.system` — the app then resolves whatever iOS picked.
    nonisolated var locale: Locale? { self == .system ? nil : Locale(identifier: rawValue) }
}

@MainActor
final class LanguageStore: ObservableObject {
    @AppStorage(SharedStore.Key.language, store: AppGroup.defaults)
    private var raw: String = ""

    var selected: SWLanguage {
        get { SWLanguage(rawValue: raw) ?? .system }
        set { objectWillChange.send(); raw = newValue.rawValue }
    }

    /// What the UI should actually render in. Autodetect is the default and needs no stored value.
    var locale: Locale { selected.locale ?? .autoupdatingCurrent }
}

/// Language access for processes with no view hierarchy or observation — the widget's timeline
/// render, the complication, and notification text built in the background task.
extension SWLanguage {
    nonisolated static var shared: SWLanguage {
        SharedStore().languageCode.flatMap(SWLanguage.init(rawValue:)) ?? .system
    }
    nonisolated static var sharedLocale: Locale { shared.locale ?? .autoupdatingCurrent }

    /// The bundle whose compiled catalog `String(localized:)` should read.
    ///
    /// This is not a detail: `locale:` formats INTERPOLATED VALUES; the BUNDLE chooses the
    /// localization. Passing only a locale returns the system language's text with the chosen
    /// language's numbers — English words beside "1,0" — and nothing errors.
    ///
    /// SwiftUI is NOT exempt. `.environment(\.locale,)` does not redirect a `LocalizedStringKey`
    /// either; that was measured, not assumed (system English + picker German rendered English
    /// text and German numbers). So every user-facing string in the app, the widget, the watch
    /// and the notifications resolves through here via `SWText.str`.
    nonisolated static var sharedBundle: Bundle {
        guard let code = shared.locale?.identifier,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }               // .system, or a locale we don't ship
        return bundle
    }
}
