import SwiftUI
import EphemerisKit
#if os(macOS)
import AppKit
#endif

@main
struct EphemerisApp: App {
    // No global UINavigationBarAppearance override on purpose. Setting one (especially
    // `configureWithTransparentBackground()` on standard + scrollEdge) opts the bar OUT of
    // iOS 26 Liquid Glass and forces it fully see-through always. Letting the system manage it
    // gives the modern top bar: transparent at the scroll edge, translucent Liquid Glass that
    // frosts content as it scrolls under. Titles are white via `.preferredColorScheme(.dark)`.
    @StateObject private var language = LanguageStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(language)
                // Drives BOTH string lookup and number/date formatting: SwiftUI resolves every
                // Text(LocalizedStringKey) against this, so changing it re-renders the whole
                // tree in the new language with no relaunch.
                .environment(\.locale, language.locale)
                .tint(NebulaPalette.accent)
                #if os(iOS)
                // The watch cannot read the phone's app group — app groups do not cross devices —
                // so the place and language are pushed over WatchConnectivity instead.
                .onAppear { WatchBridge.shared.start() }
                #endif
                .preferredColorScheme(.dark)   // Nebula is a single fully-dark theme
        }
        #if os(macOS)
        // A preview-reel run opens a 16:9 window. The App Store's macOS preview canvas is
        // 1920x1080, and the normal 900x1010 window is portrait — scaling it into that canvas
        // leaves ~480px of black down each side, which is "framing" under Guideline 2.3.4 just
        // as much as a device bezel is. A 16:9 window fills the frame with the app's own
        // starfield instead. Normal launches are untouched.
        .defaultSize(width: 900, height: 1010)
        .windowResizability(.contentSize)
        #endif
    }
}
