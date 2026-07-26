import SwiftUI

/// Cross-platform root. Compact (iPhone portrait) → three tabs (Spec · Formulas · Reference).
/// Regular (iPad landscape, Mac, iPhone-landscape "Pro") → NavigationSplitView. Light instrument.
struct ContentView: View {
    @StateObject private var router = Router()
    @StateObject private var favorites = FavoritesStore()
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        Group {
            #if os(macOS)
            RegularRoot(favorites: favorites)
            #else
            if hSize == .regular { RegularRoot(favorites: favorites) } else { tabs }
            #endif
        }
        .environmentObject(router)
        .environmentObject(favorites)
        .tint(KC.textPrimary)              // graphite tab/nav selection, not amber
        .preferredColorScheme(.light)      // KERF is a light instrument
    }

    // MARK: compact — three tabs
    private var tabs: some View {
        TabView(selection: $router.selectedTab) {
            CalcView()
                .tabItem { Label("Spec", systemImage: "square.grid.2x2") }.tag(0)
            ToolsRootView(favorites: favorites)
                .tabItem { Label("Formulas", systemImage: "function") }.tag(1)
            ReferenceView()
                .tabItem { Label("Reference", systemImage: "book") }.tag(2)
        }
    }

}
