import Foundation
import SwiftUI
import SpaceWeatherFeed

/// Marketing self-drive for the watch, mirroring the phone's `DemoDriver`: static flags
/// freeze one page for a screenshot, `EARTHAROUND_DEMO=1` walks all three for the video.
/// Beats are logged as `REEL_SCENE <key> <epoch>` so the same align/frame tooling applies.
///
///   EARTHAROUND_WATCH_PAGE=0|1|2   EARTHAROUND_THEME=dark|night   EARTHAROUND_DEMO=1
///
/// Note: watchOS previews do not exist on the App Store — the video this drives is for the
/// site and social only. The screenshots it freezes are the uploadable asset.
@MainActor
enum WatchDemo {
    static var enabled: Bool { LaunchOverride.flag("EARTHAROUND_DEMO") }
    static func env(_ k: String) -> String? { LaunchOverride.value(k) }

    /// One-shot page + theme freeze for screenshots. The theme has to be pinned because it
    /// persists in the app group — whatever the phone last synced over (or a previous night
    /// beat left behind) would otherwise silently recolour the whole capture set.
    static func applyInitialState(_ page: inout Int) {
        if let p = env("EARTHAROUND_WATCH_PAGE"), let i = Int(p), (0...2).contains(i) {
            page = i
        }
        if let t = env("EARTHAROUND_THEME") {
            SharedStore().themeRaw = (t == "night" ? SWThemeChoice.night : .dark).rawValue
        }
    }

    /// Three beats, ~15s. Settle before T0 for the same reason the phone does: the marker is
    /// what the capture trims to, so emitting it at launch opens on an empty screen.
    static func run(page: @escaping (Int) -> Void) async {
        page(0)
        try? await sleep(1.5)
        mark("REEL_T0")

        scene("Now")                                    // hero Kp + G chip
        try? await sleep(4.5)

        scene("Hpo")                                    // Hp30 24h + G/R/S
        withAnimation(.easeInOut(duration: 0.5)) { page(1) }
        try? await sleep(4.5)

        scene("Wind")                                   // solar wind + aurora line
        withAnimation(.easeInOut(duration: 0.5)) { page(2) }
        try? await sleep(4.5)

        mark("REEL_END")
    }

    private static func mark(_ tag: String) {
        NSLog("%@ %.3f", tag, Date().timeIntervalSince1970)
    }

    private static func scene(_ key: String) {
        NSLog("REEL_SCENE %@ %.3f", key, Date().timeIntervalSince1970)
    }

    private static func sleep(_ s: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }
}
