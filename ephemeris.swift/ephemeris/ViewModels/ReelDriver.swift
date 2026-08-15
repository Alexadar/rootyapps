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

    /// Which tour to walk.
    ///
    /// The store allows **three** preview videos per device size, and one reel cannot sell both
    /// halves of this app: the live sky and saved natal charts are different products to a buyer.
    /// So the driver takes a tour id rather than assuming there is only ever one reel — which is
    /// what the whole pipeline used to assume, right down to a single `scenes.json` per locale.
    enum Tour: String {
        case sky, natal
        static var current: Tour {
            Tour(rawValue: LaunchOverride.value("EPHEMERIS_REEL_TOUR") ?? "") ?? .sky
        }
    }

    /// The tab the app is showing. Bound to the platform shell's `TabView` selection.
    @Published var tab: Int

    /// Natal tour position. `0` is the library; `1...` are beats inside an opened chart.
    ///
    /// Published rather than driven by taps for exactly the reason the class exists: finding and
    /// tapping a row is a lookup that can miss silently and still produce a finished video.
    @Published var natalStep: Int = 0
    /// Which lens the natal chart shows, when the natal tour is driving.
    @Published var natalLens: MomentLens = .wheel
    /// Whether the bi-wheel's transiting ring is on.
    @Published var natalTransits: Bool = false
    /// Incremented to ask the open chart to scroll its current reading to the bottom.
    ///
    /// A counter rather than a flag: each beat needs to trigger a *fresh* scroll, and a Bool that is
    /// already true does not change. The lists are the point of those beats — twelve aspects, ten
    /// positions, twelve cusps — and almost all of it sits below the fold, so a static frame shows a
    /// heading and hides the data it is advertising.
    @Published var natalScrollNudge: Int = 0

    /// Seconds each tab is held. The Chart beat is longer because the in-app date/orb demo plays
    /// during it; the rest only need long enough to read the caption.
    private static let dwell: [Int: TimeInterval] = [0: 9.0, 1: 6.0, 2: 6.0, 3: 6.0, 4: 7.0]

    private var task: Task<Void, Never>?

    init() {
        tab = LaunchOverride.int("EPHEMERIS_TAB") ?? 0
    }

    /// Static so the App scene can size its macOS window before any instance exists.
    /// `nonisolated` because it is read from outside the actor — the App scene sizes its macOS
    /// window from it, and `NatalViewModel.live()` chooses a store from it. It reads a launch
    /// variable and touches no state, so there is nothing to isolate.
    nonisolated static var isReelRun: Bool { LaunchOverride.flag("EPHEMERIS_REEL") }
    var isReelRun: Bool { Self.isReelRun }

    /// Walks every tab once, emitting the markers `align_scenes.py` reads. Runs only under
    /// EPHEMERIS_REEL=1, so a normal launch is completely unaffected.
    func start() {
        guard isReelRun, task == nil else { return }
        task = Task { @MainActor in
            // Let the first screen settle so the recording does not open mid-layout.
            try? await Task.sleep(for: .seconds(1.5))
            NSLog("REEL_T0 %.3f", Date().timeIntervalSince1970)
            switch Tour.current {
            case .sky:   await walkSky()
            case .natal: await walkNatal()
            }
            NSLog("REEL_END %.3f", Date().timeIntervalSince1970)
        }
    }

    private func walkSky() async {
        for index in 0...4 {
            tab = index
            // Marker AFTER the switch and one runloop turn later, so it timestamps the moment
            // the new tab is actually on screen rather than the moment it was requested —
            // that gap is what made the captions run a scene ahead of the footage.
            await Task.yield()
            NSLog("REEL_SCENE %@ %.3f", Self.key(index), Date().timeIntervalSince1970)
            try? await Task.sleep(for: .seconds(Self.dwell[index] ?? 6.0))
        }
    }

    /// Chart → transits → positions → houses → library.
    ///
    /// **The chart comes first, and the library last.** The earlier order opened on the library,
    /// which is a file list: a viewer spent the three seconds that decide whether they keep
    /// watching looking at storage, and only then learned what the app computes. Worse, the concept
    /// — that this is a chart for one person's birth moment — was never established before the
    /// feature beats arrived.
    ///
    /// So it now opens on the chart with the birth date and place legible, teaches the idea, shows
    /// what can be done with it, and ends on "and they are yours, in iCloud" as reassurance rather
    /// than as the opening pitch.
    private func walkNatal() async {
        // The library FIRST, briefly, then open a chart. That transition is what teaches the
        // navigation — cutting it and starting inside a chart left no sense of where charts live
        // or how you reach one.
        tab = 5                                  // Charts
        natalStep = 0
        natalLens = .wheel
        natalTransits = false
        await beat("Library", 3.5)

        natalStep = 1                            // open the seeded fixture
        await beat("NatalWheel", 5.0)

        // Then every lens, in the order the segmented control shows them, so a viewer can map each
        // beat onto a control they can see. The earlier cut skipped Aspects entirely — a chart has
        // four readings and the video showed three, which is exactly why "what is inside a chart"
        // did not land.
        //
        // Each data lens is read, not glanced at: a moment at the top, then a slow scroll through
        // the rows. These beats are longer than the wheel's for that reason.
        await readingBeat("NatalAspects", lens: .aspects)
        await readingBeat("NatalPositions", lens: .table)
        await readingBeat("NatalHouses", lens: .houses)

        natalLens = .wheel
        natalTransits = true                     // bi-wheel: natal inside, transiting outside
        await beat("Transits", 4.0)
    }

    /// A lens that holds still long enough to start reading, then scrolls through what is beneath.
    private func readingBeat(_ key: String, lens: MomentLens) async {
        natalLens = lens
        await Task.yield()
        NSLog("REEL_SCENE %@ %.3f", key, Date().timeIntervalSince1970)
        try? await Task.sleep(for: .seconds(1.6))   // read the top of the list
        natalScrollNudge &+= 1                      // then travel down it
        try? await Task.sleep(for: .seconds(4.4))
    }

    private func beat(_ key: String, _ seconds: TimeInterval) async {
        await Task.yield()
        NSLog("REEL_SCENE %@ %.3f", key, Date().timeIntervalSince1970)
        try? await Task.sleep(for: .seconds(seconds))
    }

    func stop() { task?.cancel(); task = nil }

    /// Scene keys, matching `marketing/reels/scenes*.json`.
    private static func key(_ index: Int) -> String {
        ["Chart", "Positions", "Aspects", "Cycle", "Events"][index]
    }

    /// Total content length, for the recorder to size its capture window.
    static var contentLength: TimeInterval { dwell.values.reduce(0, +) }
}
