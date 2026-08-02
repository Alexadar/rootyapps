import SwiftUI

@main
struct StorypoleApp: App {
#if os(macOS)
    static var windowSize: CGSize {
        let raw = LaunchOverride.value("STORYPOLE_WIN") ?? ""
        let parts = raw.split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? CGSize(width: parts[0], height: parts[1])
                                : CGSize(width: 980, height: 720)
    }
#endif
    @StateObject private var language = LanguageStore()
    @StateObject private var router = Router()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(language)
                .environmentObject(router)
                .environment(\.locale, language.locale)
                .tint(SP.accent)
        }
#if os(macOS)
        // STORYPOLE_WIN=<w>x<h> in POINTS. Capture uses 960x540 so a 2x display records exactly
        // 1920x1080 — Apple's macOS preview size — with no letterbox. A letterboxed preview is
        // framing, and framing is a 2.3.4 rejection.
        .defaultSize(width: Self.windowSize.width, height: Self.windowSize.height)
#endif
    }
}
