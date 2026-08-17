import SwiftUI
import CoreGraphics

@main
struct PigApp: App {

    init() {
        // The icon pass renders one frame and quits before any window exists. Doing it inside the app
        // rather than in a separate tool is what keeps the icon and the game the same pig.
        if IconExport.runIfRequested() { exit(0) }
    }

    /// The window size, overridable for a capture. Parsed once here rather than read in two places.
    static let windowSize: CGSize = {
        let text = ProcessInfo.processInfo.environment["PIG_DEMO_SIZE"] ?? ""
        let parts = text.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 200, parts[1] > 200 else {
            return CGSize(width: 1280, height: 720)
        }
        return CGSize(width: parts[0], height: parts[1])
    }()

    var body: some Scene {
        WindowGroup {
            GameScreen()
        }
        #if os(macOS)
        // A game window, not a document window: no tabs, and a size that matches the phone framing
        // the controls were laid out for.
        //
        // `PIG_DEMO_SIZE=960x540` pins it for a recording. 960×540 is not arbitrary:
        // `marketing/reels/RecordWindow.swift` captures at `scale = 2`, so that window records at
        // exactly 1920×1080 — the macOS store-preview size — with no rescale and no resampling.
        .defaultSize(width: PigApp.windowSize.width, height: PigApp.windowSize.height)
        .windowResizability(.contentSize)
        #endif
    }
}
