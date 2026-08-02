import SwiftUI
import EphemerisKit

@main
struct EphemerisWatchApp: App {
    /// The chosen language, republished when the phone's context lands.
    ///
    /// The watch had no locale wiring at all — it rendered English in every language, and the bug
    /// was invisible until a Japanese screenshot came back entirely in English. The phone applies
    /// `.environment(\.locale,)` at its root; the watch simply never did.
    ///
    /// The source differs from the phone's, though. `LanguageStore` reads `UserDefaults.standard`,
    /// which on the watch is its own empty container — the language arrives from the phone over
    /// WatchConnectivity and lands in the **app group**. So this reads `SharedStore`, with
    /// EPHEMERIS_LANG honoured first for screenshot tooling.
    @State private var locale: Locale = EphemerisWatchApp.resolveLocale()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(\.locale, locale)
                .onReceive(NotificationCenter.default.publisher(for: .ephemerisSharedStoreChanged)) { _ in
                    locale = Self.resolveLocale()
                }
        }
    }

    static func resolveLocale() -> Locale {
        let code = LaunchOverride.value("EPHEMERIS_LANG") ?? SharedStore().languageCode ?? ""
        return code.isEmpty ? .autoupdatingCurrent : Locale(identifier: code)
    }
}
