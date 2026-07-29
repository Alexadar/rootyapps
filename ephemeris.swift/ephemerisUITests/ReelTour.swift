import XCTest

/// Scripted "reel tour" — drives Ephemeris through every tab and emits markers so the
/// compositor knows exactly when each scene appears:
///   REEL_T0            content clock start
///   REEL_SCENE <tab>   the moment that tab becomes visible
///   REEL_END           content clock end
/// make_reel.sh reads these from the sim log and hands frame_reel.py the MEASURED scene
/// windows — so ad captions line up with the footage no matter how long UI actions take.
///
/// Scrolling uses fixed per-tab swipe counts (not auto-detection, which is slow on long
/// lists); tabs whose content fits get 0 swipes so nothing rubber-bands.
final class ReelTour: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    func testReelTour() {
        let app = XCUIApplication()
        app.activate()
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 8)
        // The app pre-launched on Chart, so its one-pass demo already played off-camera during
        // the recording head. Bounce to another tab and back so re-entering Chart restarts the
        // demo (onAppear) and it plays INSIDE the recorded window.
        tapTab(app, "Positions"); dwell(1.0)
        tapTab(app, "Chart")
        dwell(1.2)
        NSLog("REEL_T0 %.3f", Date().timeIntervalSince1970)
        mark("Chart")

        // ── Chart: EPHEMERIS_DEMO drives the on-screen actions itself — three ► day-taps then
        //    an orb sweep, each lighting its control. The tour must NOT touch the slider here
        //    (that fought the in-app demo and failed the run); just linger while it plays. ──
        dwell(5.4)
        // Scroll unconditionally: the Chart tab now ends with the Houses card (cusp table +
        // system picker), which is the headline feature and must appear in the reel.
        swipeOnce(app); dwell(1.0)
        swipeOnce(app); dwell(1.8)

        // ── The rest of the app ──
        // .auto = swipe only while content overflows (cheap check); .fixed for the known-long
        // Events list, whose element count makes even a cheap query cost a second.
        visit(app, tab: "Positions", mode: .auto)
        visit(app, tab: "Aspects",   mode: .auto)
        visit(app, tab: "Cycle",     mode: .auto)
        visit(app, tab: "Events",    mode: .fixed(1))

        NSLog("REEL_END %.3f", Date().timeIntervalSince1970)
    }

    private enum ScrollMode { case auto, fixed(Int) }

    private func visit(_ app: XCUIApplication, tab: String, mode: ScrollMode) {
        tapTab(app, tab)
        mark(tab)                 // caption starts the instant the tab is visible
        dwell(1.0)
        switch mode {
        case .auto:            autoScroll(app, max: 1)   // one calm swipe — less footage to speed-fit
        case .fixed(let k):    for _ in 0..<k { swipeOnce(app); dwell(0.8) }
        }
        dwell(1.0)                // linger so the caption is readable
    }

    /// Open the compact date picker and jump the date forward ~two months so the planets
    /// visibly sweep around the wheel — demonstrates the live recompute. Fully guarded; ends
    /// by dismissing the popover so the rest of the tour isn't blocked.
    /// Swipe only while the scroll view actually has content past its bottom edge — so tabs
    /// that fit on screen don't rubber-band.
    private func autoScroll(_ app: XCUIApplication, max: Int) {
        var n = 0
        while n < max, canScroll(app) { swipeOnce(app); dwell(0.6); n += 1 }
    }

    /// Cheap overflow check: one `.count` snapshot + one `.frame` — never iterate frames over
    /// the whole list (that hangs the run for minutes on a long list).
    private func canScroll(_ app: XCUIApplication) -> Bool {
        let s = app.scrollViews.firstMatch
        guard s.exists else { return false }
        let texts = s.staticTexts
        let n = texts.count
        guard n > 0 else { return false }
        let last = texts.element(boundBy: n - 1)
        return last.exists && last.frame.maxY > s.frame.maxY + 12
    }

    private func swipeOnce(_ app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        (scroll.exists ? scroll : app).swipeUp(velocity: .init(rawValue: 520))
    }

    /// Tab order, which is fixed by `IOSContentView`. Position is the only locale-independent
    /// handle we have: the visible label is translated, so `buttons["Positions"]` matches
    /// nothing once the app runs in German or Japanese.
    private static let tabIndex = ["Chart": 0, "Positions": 1, "Aspects": 2, "Cycle": 3, "Events": 4]

    /// The five tab buttons, in visual order, however this OS chooses to expose them.
    ///
    /// iPhone puts them in a `tabBar`. iPad's iOS 26 floating tab bar does **not** publish a
    /// `tabBar` element at all — `app.tabBars.firstMatch` never resolves, which silently left the
    /// whole iPad reel on its launch tab while the captions advanced through all five scenes.
    /// So each container is tried in turn and the first that yields exactly five hittable buttons
    /// wins. `REEL_TABS` records which one, because the answer differs per OS and per device and
    /// is the first thing worth knowing when this breaks again.
    private func tabButtons(_ app: XCUIApplication) -> [XCUIElement] {
        let candidates: [(String, XCUIElementQuery)] = [
            ("tabBar",   app.tabBars.buttons),
            ("toolbar",  app.toolbars.buttons),
            ("segment",  app.segmentedControls.buttons),
            ("window",   app.windows.buttons),
        ]
        for (name, query) in candidates {
            let hittable = query.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
            NSLog("REEL_TABS container=%@ hittable=%d", name, hittable.count)
            if hittable.count >= Self.tabIndex.count {
                // Tab bars sit at one edge; anything else hittable (a settings gear, a stepper)
                // is elsewhere. Taking the five that share the dominant edge coordinate keeps
                // stray buttons out without depending on any label.
                let byY = Dictionary(grouping: hittable) { Int($0.frame.midY / 40) }
                if let row = byY.values.filter({ $0.count >= Self.tabIndex.count })
                                      .max(by: { $0.count < $1.count }) {
                    return row.sorted { $0.frame.minX < $1.frame.minX }
                }
            }
        }
        return []
    }

    private func tapTab(_ app: XCUIApplication, _ key: String) {
        guard let idx = Self.tabIndex[key] else { return }
        let tabs = tabButtons(app)
        if idx < tabs.count {
            tabs[idx].tap()
            // Selection is the only locale-independent evidence the tap landed — the label is
            // translated, so there is nothing else to assert against.
            if tabs[idx].isSelected { return }
        }
        // An English run can still match by label; also a genuine fallback if selection state
        // stops being exposed.
        for q in [app.tabBars.buttons[key], app.buttons[key]] where q.firstMatch.exists {
            if q.firstMatch.isHittable { q.firstMatch.tap(); return }
        }
        XCTFail("could not reach tab '\(key)' (resolved \(tabs.count) tab buttons) — "
                + "reel would show the wrong screen under the right caption")
    }

    private func mark(_ key: String) { NSLog("REEL_SCENE %@ %.3f", key, Date().timeIntervalSince1970) }
    private func dwell(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }
}
