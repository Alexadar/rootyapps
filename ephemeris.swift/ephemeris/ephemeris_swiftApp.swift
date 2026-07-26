import SwiftUI

@main
struct ephemeris_swiftApp: App {
    // No global UINavigationBarAppearance override on purpose. Setting one (especially
    // `configureWithTransparentBackground()` on standard + scrollEdge) opts the bar OUT of
    // iOS 26 Liquid Glass and forces it fully see-through always. Letting the system manage it
    // gives the modern top bar: transparent at the scroll edge, translucent Liquid Glass that
    // frosts content as it scrolls under. Titles are white via `.preferredColorScheme(.dark)`.
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(NebulaPalette.accent)
                .preferredColorScheme(.dark)   // Nebula is a single fully-dark theme
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 1010)
        .windowResizability(.contentSize)
        #endif
    }
}
