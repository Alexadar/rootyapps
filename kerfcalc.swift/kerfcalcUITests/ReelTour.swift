import XCTest

/// Reel tour — two focused scenes so the whole thing fits ~30s at HUMAN typing speed (no speed-up):
///   1. Spec   — a worker punches a full cut-list tape: 8'4½" × 3 − 2'6" ÷ 2 = 11'3¾" (×, −, ÷, =)
///   2. Rafter — nudge the pitch stepper, watch the common length recompute live; the cited formula
/// Keys are pressed (held) with human gaps so the press animation reads; the tour is kept short so
/// make_reel.sh does NOT accelerate it. Emits REEL_T0 / REEL_SCENE / REEL_END markers.
final class ReelTour: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    func testReelTour() {
        let app = XCUIApplication()
        app.launch()
        dwell(1.2)
        NSLog("REEL_T0 %.3f", Date().timeIntervalSince1970)

        // ── Scene 1 · Spec — punch the cut-list FAST (~3× quicker) ──
        mark("Spec"); dwell(0.5)
        let fast: TimeInterval = 0.05, hold: TimeInterval = 0.05
        for k in ["digit8", "feet", "digit4", "inch", "digit1", "fraction", "digit2"] { pressKey(app, k, gap: fast, hold: hold) }
        pressKey(app, "op.mul", gap: fast, hold: hold); pressKey(app, "digit3", gap: fast, hold: hold)
        pressKey(app, "op.sub", gap: fast, hold: hold); for k in ["digit2", "feet", "digit6", "inch"] { pressKey(app, k, gap: fast, hold: hold) }
        pressKey(app, "op.div", gap: fast, hold: hold); pressKey(app, "digit2", gap: fast, hold: hold)
        pressKey(app, "equals", gap: fast, hold: hold); dwell(1.0)                     // = 11'3¾"

        // ── Scene 2 · Rafter — live recompute on the stepper + the cited formula ──
        tabTap(app, "Formulas"); dwell(0.8)
        openTile(app, "rafter"); mark("Rafter"); dwell(1.0)
        for _ in 0..<2 { pressId(app, "input.rafter.pitch.inc"); dwell(0.5) }                 // pitch 6→8/12, hero updates live
        dwell(1.0)

        // ── Scene 3 · Stairs — the diagram + live IRC code checks ──
        tabTap(app, "Formulas"); dwell(0.6)
        openTile(app, "stairs"); mark("Stairs"); dwell(2.6)

        // ── Scene 4 · Concrete — the takeoff (yards + bags) ──
        tabTap(app, "Formulas"); dwell(0.6)
        openTile(app, "concrete"); mark("Concrete"); dwell(2.6)

        // ── Scene 5 · Roofing — squares, pitch-adjusted ──
        tabTap(app, "Formulas"); dwell(0.6)
        openTile(app, "roofing"); mark("Roofing"); dwell(3.4)

        NSLog("REEL_END %.3f", Date().timeIntervalSince1970)
    }

    // MARK: steps
    /// Press a Spec keypad key by its `key.<name>` identifier — the labels are glyphs (U+2212 MINUS,
    /// U+2044 FRACTION SLASH) and the ids are derived from `SpecKeypad.KeyID`, so they cannot drift.
    private func pressKey(_ app: XCUIApplication, _ name: String, gap: TimeInterval = 0.16, hold: TimeInterval = 0.12) {
        let b = app.descendants(matching: .any).matching(identifier: "key." + name).firstMatch
        if b.waitForExistence(timeout: 2), b.isHittable { b.press(forDuration: hold) }
        dwell(gap)
    }
    private func pressId(_ app: XCUIApplication, _ id: String) {
        let b = app.descendants(matching: .any).matching(identifier: id).firstMatch
        if b.waitForExistence(timeout: 2), b.isHittable { b.press(forDuration: 0.12) }
    }
    private func tabTap(_ app: XCUIApplication, _ label: String) {
        let t = app.tabBars.buttons[label].firstMatch      // compact: tab bar
        if t.waitForExistence(timeout: 2) { t.tap(); return }
        let r = app.buttons[label].firstMatch              // regular: the 78pt rail
        if r.waitForExistence(timeout: 2) { r.tap() }
    }
    private func openTile(_ app: XCUIApplication, _ title: String) {
        // Regular layout: opening a tool pins the sidebar to its trade, which filters the grid — clear
        // it back to "All formulas" so a tool in any other section is reachable. No-op on compact.
        let all = app.descendants(matching: .any).matching(identifier: "category.all").firstMatch
        if all.exists { all.tap(); dwell(0.3) }
        let tile = app.descendants(matching: .any).matching(identifier: "tool." + title).firstMatch
        var tries = 0
        while !tile.isHittable && tries < 8 { app.swipeUp(velocity: .init(rawValue: 480)); dwell(0.25); tries += 1 }
        if tile.exists { tile.tap() }
    }
    private func mark(_ key: String) { NSLog("REEL_SCENE %@ %.3f", key, Date().timeIntervalSince1970) }
    private func dwell(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }
}
