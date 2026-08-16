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

#if os(macOS)
    /// A capture launch must not steal the machine's focus.
    ///
    /// `capture_mac_window.sh` and `capture_mac_reel.sh` launch the binary inside the bundle
    /// directly — that is deliberate, because it yields the exact pid to capture and lets several
    /// copies coexist. But a directly-launched `.regular` app *activates*, so every one of the 36
    /// screenshot launches and every reel clip yanked the foreground away from whatever the owner
    /// was doing. Nothing in ScreenCaptureKit needs that: `SCContentFilter(desktopIndependentWindow:)`
    /// composites the window's own content whether or not it is frontmost or even occluded.
    ///
    /// `.accessory` keeps the window — it is drawn, laid out and capturable exactly as before —
    /// while the app never becomes active and takes no Dock slot. This is the same policy
    /// `marketing/tools/CaptureWindow.swift` sets on *itself* for the same reason; the capture tool
    /// was well-behaved and the app being captured was not.
    ///
    /// Gated on `EPHEMERIS_CAPTURE`, which `LaunchOverride` compiles out in Release, so a shipping
    /// build can never launch without a Dock icon.
    init() {
        if LaunchOverride.flag("EPHEMERIS_CAPTURE") {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
#endif

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
