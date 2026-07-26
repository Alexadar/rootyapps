import XCTest

/// Scripted, metronome-timed walkthrough for the App Store app-preview reel. Emits
/// `REEL_T0 / REEL_SCENE <key> / REEL_END` NSLog markers that `align_scenes.py` uses to trim
/// the recording and time the captions. Works in both idioms (iPhone grid + iPad sidebar).
final class ReelTour: XCTestCase {
    let app = XCUIApplication()

    private var regular: Bool { app.windows.firstMatch.frame.width > 700 }

    func testReelTour() {
        app.launchEnvironment["TRUECOURSE_DEMO"] = "1"   // auto-sweeps the wind triangle
        app.launch()
        XCTAssertTrue(app.staticTexts["TrueCourse"].firstMatch.waitForExistence(timeout: 12))
        dwell(1.6)
        NSLog("REEL_T0 %.3f", Date().timeIntervalSince1970)

        // Scene 1 — Wind triangle: show inputs/hero change, then scroll DOWN to the animated
        // vector diagram (on iPhone it sits below the fold) and hold while the wind DIRECTION
        // makes one slow, contiguous sweep (180°→240°) — a single change, at 2× the standard
        // pace, so the vectors rotate and heading/GS travel legibly. Longer hold than the other
        // scenes because the sweep is deliberately half-speed.
        openTool("Wind Triangle"); mark("Wind"); dwell(0.3)
        scrollToDiagram()      // one scroll, first — values held still during the warm-up
        dwell(8.0)             // then the single slow direction sweep plays to completion

        // Scene 2 — Density altitude: OAT sweeps → DA rolls ≈ 4,380 → 8,850 ft
        backToCatalog()
        openTool("Altitude", needsScroll: true); mark("Altitude"); dwell(6.5)

        // Scene 3 — Weight & Balance: CG point travels the envelope (IN → OUT → IN)
        backToCatalog()
        openTool("Weight & Balance"); mark("WB"); dwell(0.5)
        tapText("Envelope")    // open the chart during the warm-up hold…
        dwell(6.5)

        // Scene 4 — Convert: values roll (0…100 °C → 32…212 °F)
        backToCatalog()
        openTool("Convert", needsScroll: true); mark("Convert"); dwell(6.5)

        NSLog("REEL_END %.3f", Date().timeIntervalSince1970)
        dwell(0.4)
    }

    // MARK: helpers

    private func dwell(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }
    private func mark(_ key: String) { NSLog("REEL_SCENE %@ %.3f", key, Date().timeIntervalSince1970) }

    /// `needsScroll`: tiles below the fold in the catalog (avoids a costly `isHittable` snapshot).
    private func openTool(_ title: String, needsScroll: Bool = false) {
        if needsScroll { app.swipeUp(); dwell(0.3) }
        let el = app.staticTexts[title].firstMatch
        guard el.waitForExistence(timeout: 6) else { return }
        el.tap()
        dwell(0.5)
    }

    private func backToCatalog() {
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap(); dwell(0.4) }      // no isHittable — it forces a snapshot
    }

    /// Tap a sub-screen pill. It carries a button trait, so try buttons first, then the label.
    private func tapText(_ t: String) {
        let b = app.buttons[t].firstMatch
        if b.waitForExistence(timeout: 3), b.isHittable { b.tap(); return }
        let s = app.staticTexts[t].firstMatch
        if s.waitForExistence(timeout: 3) {
            if s.isHittable { s.tap() }
            else { s.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        }
    }

    private func setField(_ id: String, _ text: String) {
        let f = app.textFields[id].firstMatch
        guard f.waitForExistence(timeout: 4) else { return }
        f.tap()
        f.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        if let cur = f.value as? String, !cur.isEmpty {
            f.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: cur.count + 3))
        }
        f.typeText(text)
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
    }

    /// At most one swipe to reach an off-screen catalog tile — no repeated scrolling.
    private func scrollToHittable(_ el: XCUIElement) {
        if !el.isHittable { app.swipeUp(); dwell(0.4) }
    }

    /// Scroll the detail view down to bring the wind-triangle diagram into frame.
    /// Only needed on compact width (stacked); on iPad it's already beside the inputs.
    /// One decisive scroll to the diagram, once, at the start of the scene. No scrolling after.
    private func scrollToDiagram() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
        let end   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        start.press(forDuration: 0.7, thenDragTo: end)
    }
}
