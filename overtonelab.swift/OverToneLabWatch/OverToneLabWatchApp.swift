import SwiftUI

/// Overtone Lab on the wrist — watchOS 26, dark only.
///
/// The same `LanguageStore` as phone and Mac, applied the same way: `.environment(\.locale,)`
/// drives both string lookup and number formatting, so a German user reads AND enters `0,81`
/// here too. There is no language picker on the watch — it follows the phone's choice through
/// the shared `appLanguage` default, because a 41 mm screen is the wrong place to hunt for a
/// settings list.
@main
struct OverToneLabWatchApp: App {
    @StateObject private var language = LanguageStore()
    @StateObject private var crownFocus = CrownFocus()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(language)
                .environmentObject(crownFocus)
                .environment(\.locale, language.locale)
        }
    }
}
