import SwiftUI

struct ContentView: View {
    // Theme is owned here so `.swTheme` sets the palette for the WHOLE root subtree
    // (including the root's own header) — a `.swTheme` applied inside the root would
    // only reach its children, not the root view's own `@Environment(\.sw)`.
    @StateObject private var theme = ThemeStore()
    @StateObject private var mode = ModeStore()
    @StateObject private var language = LanguageStore()
    @StateObject private var demo = DemoDriver()

    var body: some View {
        SpaceWeatherRootView()
            .environmentObject(theme)
            .environmentObject(mode)
            .environmentObject(language)
            .environment(\.locale, language.locale)
            .environmentObject(demo)
            .swTheme(theme.selected)
            .task {
                // Seed the deterministic snapshot BEFORE anything reads the store, so the
                // first paint is already the fixture rather than yesterday's cache.
                LaunchOverride.installFixtureIfRequested()
                demo.applyInitialState(theme: theme, mode: mode)   // static flags (screenshots)
                if DemoDriver.enabled { await demo.run(theme: theme, mode: mode) }
            }
    }
}

#Preview {
    ContentView()
}
