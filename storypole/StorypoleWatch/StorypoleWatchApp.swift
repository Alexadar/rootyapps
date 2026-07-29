import SwiftUI

/// Storypole on the wrist — watchOS 26.
///
/// The case for it is physical: your hands are full, the tape is in one of them, and the phone is
/// in your pocket. Read a running total, add a measurement, see the fraction. Layout planning
/// stays on the phone.
///
/// The same `LanguageStore` as phone and Mac, applied the same way. There is no language picker
/// here — it follows the phone's choice through the shared `appLanguage` default, because a 41 mm
/// screen is the wrong place to hunt for a settings list.
@main
struct StorypoleWatchApp: App {
    @StateObject private var language = LanguageStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(language)
                .environment(\.locale, language.locale)
                .tint(SP.accent)
        }
    }
}
