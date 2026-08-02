import SwiftUI

@main
struct KerfCalcApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: macWindowSize.width, height: macWindowSize.height)
        .windowResizability(.automatic)
        #endif
    }
}

#if os(macOS)
/// Default macOS window size; `KERFCALC_WIN=WxH` overrides it. The App Store macOS preview must be
/// 1920×1080 **full-bleed** — letterboxing a 1.41:1 window to 16:9 would itself be "framing" under
/// Guideline 2.3.4 — so the reel records with a natively 16:9 window. Normal launches use 1100×780.
let macWindowSize: CGSize = {
    let parts = (LaunchOverride.value("KERFCALC_WIN") ?? "").split(separator: "x")
    if parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]) {
        return CGSize(width: w, height: h)
    }
    return CGSize(width: 1100, height: 780)
}()
#endif
