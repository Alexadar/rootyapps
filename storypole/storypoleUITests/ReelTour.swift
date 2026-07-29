import XCTest

/// Scripted reel tour — four scenes that *demonstrate* the app rather than tour its menus:
///   1. Tape      — key a mixed fraction, watch the blade place the mark (the hero moment)
///   2. Blade     — drag the tape itself to set a measurement (nobody else does this)
///   3. Layout    — divide a span and get every mark, not a spacing number
///   4. Reference — the citations, because "provable" is the whole pitch
///
/// Emits `REEL_T0` / `REEL_SCENE <key>` / `REEL_END` NSLog markers so `align_scenes.py` can turn
/// them into measured caption windows. This test only navigates and lingers; it asserts nothing,
/// because a failed assertion mid-recording would truncate the capture.
final class ReelTour: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    func testReelTour() {
        let app = XCUIApplication()
        // Localized reels have to be recorded with the app IN that language. xcodebuild passes
        // TEST_RUNNER_STORYPOLE_LANG in with the prefix stripped; forward it to the app.
        if let lang = ProcessInfo.processInfo.environment["STORYPOLE_LANG"], !lang.isEmpty {
            app.launchEnvironment["STORYPOLE_LANG"] = lang
        }
        app.launch()
        _ = app.buttons["key.digit6"].waitForExistence(timeout: 15)
        dwell(1.2)
        NSLog("REEL_T0 %.3f", Date().timeIntervalSince1970)

        // ── Scene 1 — the hero: 6' 2 1/2" + 2' 7 3/4" = 8' 10 1/4", drawn on the blade ──────────
        mark("Tape")
        key(app, "digit6"); key(app, "feet")
        key(app, "digit2"); key(app, "inch")
        key(app, "digit1"); key(app, "fraction"); key(app, "digit2")
        dwell(1.5)
        key(app, "op.add"); dwell(0.6)
        key(app, "digit2"); key(app, "feet")
        key(app, "digit7"); key(app, "inch")
        key(app, "digit3"); key(app, "fraction"); key(app, "digit4")
        dwell(1.2)
        key(app, "equals"); dwell(3.4)

        // ── Scene 2 — the blade is an input: drag it, watch the fraction follow ────────────────
        mark("Blade")
        let blade = app.descendants(matching: .any).matching(identifier: "tape.blade.surface").firstMatch
        if blade.waitForExistence(timeout: 3) {
            let mid = blade.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
            // Slow, deliberate drags — a fast flick reads as a glitch at 30fps.
            mid.press(forDuration: 0.15,
                      thenDragTo: blade.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.5)))
            dwell(1.2)
            mid.press(forDuration: 0.15,
                      thenDragTo: blade.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.5)))
            dwell(1.6)
        }
        dwell(1.0)

        // ── Scene 3 — the differentiator: every mark, not just the spacing ─────────────────────
        mark("Layout")
        openTool(app, tab: 1, tool: "Equal Spacing"); dwell(3.6)

        // ── Scene 4 — the moat made visible ───────────────────────────────────────────────────
        mark("Reference")
        openTab(app, 2); dwell(3.6)

        NSLog("REEL_END %.3f", Date().timeIntervalSince1970)
    }

    // MARK: - Steps

    private func key(_ app: XCUIApplication, _ id: String) {
        let b = app.buttons["key.\(id)"]
        if b.waitForExistence(timeout: 3) { b.tap(); dwell(0.34) }
    }

    private func openTab(_ app: XCUIApplication, _ index: Int) {
        let bars = app.tabBars.firstMatch
        if bars.waitForExistence(timeout: 2), bars.buttons.count > index {
            bars.buttons.element(boundBy: index).tap(); dwell(0.8)
            return
        }
        // Regular width (iPad / Mac): no tab bar, the sidebar row is the way in.
        let names = ["Calc", "Tools", "Reference"]
        let row = app.staticTexts[names[index]].firstMatch
        if row.exists { row.tap(); dwell(0.8) }
    }

    private func openTool(_ app: XCUIApplication, tab: Int, tool: String) {
        openTab(app, tab)
        let tile = app.staticTexts[tool].firstMatch
        var tries = 0
        while !tile.isHittable && tries < 8 {
            app.swipeUp(velocity: .init(rawValue: 420)); dwell(0.25); tries += 1
        }
        if tile.exists { tile.tap(); dwell(0.9) }
    }

    private func mark(_ key: String) { NSLog("REEL_SCENE %@ %.3f", key, Date().timeIntervalSince1970) }
    private func dwell(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }
}
