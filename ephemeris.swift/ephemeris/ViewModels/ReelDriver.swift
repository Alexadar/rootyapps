import Foundation
import SwiftUI
import EphemerisKit   // LaunchOverride — DEBUG-gated EPHEMERIS_* reads

/// Drives the App Store preview tour from *inside* the app, and publishes the markers the
/// compositor times its captions against.
///
/// This exists because driving it from outside does not work. A `ReelTour` XCUITest has to find
/// the tab bar, and three separate strategies each failed in a way that produced a plausible,
/// silently wrong reel:
///
///   • `buttons["Positions"]` — the label is translated, so it matched nothing in de/fr/ja and
///     the reel sat on one screen for 30s under five different captions.
///   • `tabBar.buttons.element(boundBy:)` — iPad's iOS 26 floating tab bar nests each button in a
///     cell, so the index is not the visual position and taps landed on the wrong tabs.
///   • filtering hittable buttons by row — on iPad `app.tabBars` resolves to nothing at all, and
///     the fallback picked whichever row had the most buttons, which on the Chart tab is the sign
///     chips rather than the tab bar.
///
/// None of those errored. Each produced a finished video, a clean log and a successful exit.
///
/// Selecting a tab by index in-process cannot miss: there is no lookup, no localisation and no
/// platform difference. The markers are emitted from the same place that performs the switch, so
/// a caption can never be timed against a tab change that did not happen.
@MainActor
final class ReelDriver: ObservableObject {
    /// The tab the app is showing. Bound to the platform shell's `TabView` selection.
    @Published var tab: Int

    /// Seconds each tab is held. The Chart beat is longer because the in-app date/orb demo plays
    /// during it; the rest only need long enough to read the caption.
    private static let dwell: [Int: TimeInterval] = [0: 9.0, 1: 6.0, 2: 6.0, 3: 6.0, 4: 7.0]

    private var task: Task<Void, Never>?

    init() {
        tab = LaunchOverride.int("EPHEMERIS_TAB") ?? 0
    }

    /// Static so the App scene can size its macOS window before any instance exists.
    static var isReelRun: Bool { LaunchOverride.flag("EPHEMERIS_REEL") }
    var isReelRun: Bool { Self.isReelRun }

    /// Walks every tab once, emitting the markers `align_scenes.py` reads. Runs only under
    /// EPHEMERIS_REEL=1, so a normal launch is completely unaffected.
    func start() {
        guard isReelRun, task == nil else { return }
        task = Task { @MainActor in
            // Let the first screen settle so the recording does not open mid-layout.
            try? await Task.sleep(for: .seconds(1.5))
            NSLog("REEL_T0 %.3f", Date().timeIntervalSince1970)
            for index in 0...4 {
                tab = index
                // Marker AFTER the switch and one runloop turn later, so it timestamps the moment
                // the new tab is actually on screen rather than the moment it was requested —
                // that gap is what made the captions run a scene ahead of the footage.
                await Task.yield()
                NSLog("REEL_SCENE %@ %.3f", Self.key(index), Date().timeIntervalSince1970)
                try? await Task.sleep(for: .seconds(Self.dwell[index] ?? 6.0))
            }
            NSLog("REEL_END %.3f", Date().timeIntervalSince1970)
        }
    }

    func stop() { task?.cancel(); task = nil }

    /// Scene keys, matching `marketing/reels/scenes*.json`.
    private static func key(_ index: Int) -> String {
        ["Chart", "Positions", "Aspects", "Cycle", "Events"][index]
    }

    /// Total content length, for the recorder to size its capture window.
    static var contentLength: TimeInterval { dwell.values.reduce(0, +) }
}
