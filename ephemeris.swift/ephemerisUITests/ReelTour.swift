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
        autoScroll(app, max: 1); dwell(1.2)       // reveal chart wheel only if it overflows

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

    private func tapTab(_ app: XCUIApplication, _ label: String) {
        // iPhone: bottom tabBar. iPad (iOS 26) renders the tab bar differently — fall back to
        // a plain button match so the same tour drives both.
        // .firstMatch: iPad's iOS 26 floating tab bar nests buttons inside cells, so a plain
        // query resolves to multiple elements and .tap() throws.
        let tabBtn = app.tabBars.buttons[label].firstMatch
        if tabBtn.waitForExistence(timeout: 3) { tabBtn.tap(); return }
        let btn = app.buttons[label].firstMatch
        if btn.waitForExistence(timeout: 3) { btn.tap() }
    }

    private func mark(_ key: String) { NSLog("REEL_SCENE %@ %.3f", key, Date().timeIntervalSince1970) }
    private func dwell(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }
}
