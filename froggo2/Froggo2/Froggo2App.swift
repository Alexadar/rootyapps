import SwiftUI

@main
struct Froggo2App: App {
#if os(macOS)
    /// Window size in POINTS, overridable with FROGGO2_WIN=<w>x<h>.
    ///
    /// Reel capture uses 960x540 so a 2x display records exactly 1920x1080 — Apple's macOS preview
    /// size — with no letterbox. A letterboxed preview reads as framing, and framing is a 2.3.4
    /// rejection, which this repo has already collected once.
    static var windowSize: CGSize {
        let raw = LaunchOverride.value("FROGGO2_WIN") ?? ""
        let parts = raw.split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? CGSize(width: parts[0], height: parts[1])
                                : CGSize(width: 1000, height: 640)
    }
#endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
#if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: Self.windowSize.width, height: Self.windowSize.height)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
#endif
    }
}
