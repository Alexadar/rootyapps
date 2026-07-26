import SwiftUI

@main
struct OverToneLabApp: App {
    @StateObject private var language = LanguageStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(language)
                // Drives BOTH string lookup and number parsing/formatting: SwiftUI resolves every
                // Text(LocalizedStringKey) against this, and NumberField's `.number` parses with
                // it, so switching language re-renders the whole tree with no relaunch.
                .environment(\.locale, language.locale)
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 820)
        .windowResizability(.automatic)
        #endif

        // A separate #if: the block above attaches modifiers to WindowGroup, so declaring a
        // second scene inside it is a parse error.
        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(language)
                .environment(\.locale, language.locale)
                .frame(width: 420)
        }
        #endif
    }
}
