import SwiftUI
import Combine

/// Marketing self-drive. When launched with `EARTHAROUND_DEMO=1`, the app auto-tours
/// its functions on a fixed timeline that matches `marketing/reels/scenes.json`, so the
/// simulator recording lines up with the ad captions — no UITest target needed.
///
/// Static launch flags (for App Store screenshots) freeze a single state:
///   EARTHAROUND_TAB=dashboard|geomagnetic   EARTHAROUND_THEME=dark|night
/// All of them are DEBUG-only — see `LaunchOverride`.
@MainActor
final class DemoDriver: ObservableObject {
    @Published var tabIndex: Int = 0
    @Published var rangeHours: Double? = nil     // nil = view controls its own range
    @Published var scrollTarget: SWPanel? = nil
    @Published var scrollAnchor: UnitPoint = .top

    static var enabled: Bool { LaunchOverride.flag("EARTHAROUND_DEMO") }
    /// Debug-only: `LaunchOverride` compiles to nil in Release, so a shipped app cannot have its
    /// navigation driven from outside it. See LaunchOverride.swift.
    static func env(_ k: String) -> String? { LaunchOverride.value(k) }

    /// One-shot initial state from static flags (screenshots).
    func applyInitialState(theme: ThemeStore, mode: ModeStore) {
        if let t = Self.env("EARTHAROUND_TAB") {
            tabIndex = (t.hasPrefix("geo")) ? 1 : 0
        }
        if let th = Self.env("EARTHAROUND_THEME") {
            theme.selected = (th == "night") ? .night : .dark
        }
        // EARTHAROUND_MODE is gone, not merely unused: SpaceWeatherRootView's own `.task`
        // unconditionally forces `.extended` ("Full view always"), and the two are racing siblings
        // with no ordering guarantee. The hook could not be relied on, so keeping it was a trap.
    }

    /// The walkthrough — six beats, ~27s at natural speed (the preview budget is
    /// `preview_maxlen - outro_dur` = 27.4s, so nothing gets sped up).
    ///
    /// The beats follow the questions a user actually asks, in order: is a storm hitting
    /// now → what's driving it → what did the Sun do → will I see aurora → the Hp30 detail
    /// no competitor shows → and it works in the dark. Boundaries are logged as
    /// `REEL_SCENE <key> <epoch>` so `align_scenes.py` lands each caption on its footage.
    func run(theme: ThemeStore, mode: ModeStore) async {
        // Deterministic opening state, set BEFORE the marker: the previous run ends on the
        // night-mode beat and that choice persists, so without this the reel opens red.
        // Mode is pinned for the same reason and one more: the tour scrolls to Wind/Flare/Hpo
        // panels that only exist in Extended, so a Simple carry-over would record a broken reel.
        theme.selected = .dark
        mode.selected = .extended
        tabIndex = 0

        // Settle BEFORE the marker too: T0 is what the capture trims to, so emitting it at
        // launch opens the reel on the launch screen / empty panels. Marking after the
        // settle drops that dead second and keeps every caption on its own footage.
        try? await sleep(1.5)                              // first frame drawn + live data in
        mark("REEL_T0")

        // 1 — Storm state now: the NOAA scoreline + planetary Kp.
        scene("Now")
        try? await sleep(4.5)

        // 2 — Cause: the solar-wind coupling driving it.
        scene("Wind")
        scrollTo(.wind)
        try? await sleep(4.5)

        // 3 — Source: flares and the live GOES X-ray flux. Anchored centre, not top: the
        // list has only Aurora + Solar below Flare, so a top-anchored scroll would already
        // hit the bottom clamp and leave beat 4 with nowhere to travel.
        scene("Flare")
        scrollTo(.flare, anchor: .center)
        try? await sleep(3.5)

        // 4 — Payoff: aurora probability and the view line (this one rides to the bottom).
        scene("Aurora")
        scrollTo(.aurora)
        try? await sleep(3.5)

        // 5 — The differentiator: Hp30 at 30-minute cadence, scrubbed across ranges.
        scene("Hpo")
        withAnimation(.easeInOut(duration: 0.5)) { tabIndex = 1; scrollTarget = nil }
        try? await sleep(1.3)
        for r in [72.0, 24.0, 168.0] {
            withAnimation(.easeInOut(duration: 0.5)) { rangeHours = r }
            try? await sleep(1.1)
        }

        // 6 — Field-ready: the red-shift Night theme.
        scene("Night")
        withAnimation(.easeInOut(duration: 0.8)) { theme.selected = .night }
        try? await sleep(3.5)

        mark("REEL_END")
    }

    /// Re-assigning the same target must still scroll (a beat may revisit a panel), so
    /// clear it first — the root view scrolls on every non-nil change.
    private func scrollTo(_ panel: SWPanel, anchor: UnitPoint = .top) {
        scrollAnchor = anchor
        scrollTarget = nil
        scrollTarget = panel
    }

    /// Marker timestamps are epoch seconds — `align_scenes.py` diffs them against REEL_T0.
    private func mark(_ tag: String) {
        NSLog("%@ %.3f", tag, Date().timeIntervalSince1970)
    }

    private func scene(_ key: String) {
        NSLog("REEL_SCENE %@ %.3f", key, Date().timeIntervalSince1970)
    }

    private func sleep(_ s: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }
}
