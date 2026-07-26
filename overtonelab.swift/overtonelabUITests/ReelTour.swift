import XCTest

/// Scripted "reel tour" — fewer, longer scenes that actually *demonstrate* the app:
///   1. Tempo    — type a new tempo and watch every value recompute live (the hero moment)
///   2. Sabine   — a full calculator with multiple screens
///   3. Discover — "Discover more": a montage of reference formulas, simple → very hard → other
/// Emits REEL_T0 / REEL_SCENE <key> / REEL_END markers so make_reel.sh aligns captions.
final class ReelTour: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    func testReelTour() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Overtone Lab"].waitForExistence(timeout: 10), "catalog missing")
        dwell(1.4)
        NSLog("REEL_T0 %.3f", Date().timeIntervalSince1970)

        // ── Scene 1 · EASY — Tempo: select the value and rewrite it; everything recomputes live ──
        openTool(app, "Tempo"); mark("Tempo"); dwell(1.8)
        typeBPM(app, "90");  dwell(3.0)
        typeBPM(app, "160"); dwell(3.0)
        dismissKeyboard(app); dwell(1.8)

        // ── Scene 2 · MEDIUM — Sabine: a full room-acoustics calculator (linger a bit longer) ──
        openTool(app, "Sabine"); mark("Sabine"); dwell(3.0)
        tapPill(app, "Modes");     dwell(3.0)
        tapPill(app, "Reference"); dwell(2.6)

        // ── Scene 3 · HARDEST — Benchmark: real ITU-R BS.1770 LUFS (paywalled in the rival app) ──
        openTool(app, "Benchmark"); mark("Benchmark"); dwell(2.8)
        tapPill(app, "Target");    dwell(3.0)
        tapPill(app, "Reference"); dwell(3.0)

        NSLog("REEL_END %.3f", Date().timeIntervalSince1970)
    }

    // MARK: steps

    /// Replace the first (BPM) field's value, digit by digit, so the recompute is visible.
    /// Double-tap selects the current number; the first typed digit replaces the selection,
    /// the rest append — so the field reads cleanly (e.g. "90") rather than accumulating.
    private func typeBPM(_ app: XCUIApplication, _ value: String) {
        let field = app.textFields.firstMatch
        guard field.waitForExistence(timeout: 3) else { return }
        field.tap(); dwell(0.3)
        field.doubleTap(); dwell(0.4)          // select the whole current value
        for ch in value { field.typeText(String(ch)); dwell(0.6) }
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        // Tapping the nav bar resigns the field without navigating.
        app.navigationBars.firstMatch.tap()
    }

    private func tapPill(_ app: XCUIApplication, _ label: String) {
        let pill = app.staticTexts[label].firstMatch
        if pill.waitForExistence(timeout: 2) { pill.tap() }
    }

    /// Works in both idioms: compact (grid pushes to a detail — pop back first) and
    /// regular (sidebar always visible — just tap the row).
    private func openTool(_ app: XCUIApplication, _ title: String) {
        let tile = app.staticTexts[title].firstMatch
        // Compact: if the tile isn't reachable we're inside a pushed detail — pop back.
        if !(tile.exists && tile.isHittable) {
            let backBtn = app.navigationBars.buttons.firstMatch
            if backBtn.exists { backBtn.tap(); dwell(0.5) }
        }
        var tries = 0
        while !tile.isHittable && tries < 10 { app.swipeUp(velocity: .init(rawValue: 500)); dwell(0.3); tries += 1 }
        XCTAssertTrue(tile.exists, "tile '\(title)' not found")
        tile.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "detail '\(title)' did not load")
    }

    private func back(_ app: XCUIApplication) {
        let b = app.navigationBars.buttons.firstMatch
        if b.exists { b.tap() }
    }

    private func mark(_ key: String) { NSLog("REEL_SCENE %@ %.3f", key, Date().timeIntervalSince1970) }
    private func dwell(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }
}
