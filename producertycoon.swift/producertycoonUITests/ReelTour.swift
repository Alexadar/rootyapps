import XCTest

/// Scripted reel tour for Producer Tycoon — plays a few real weeks of the
/// game and emits the marker protocol make_reel.sh expects:
///   REEL_T0            content clock start
///   REEL_SCENE <key>   a scene became visible (keys match scenes.json)
///   REEL_END           content clock end
final class ReelTour: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    func testReelTour() {
        let app = XCUIApplication()
        app.activate()
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 8)
        tapTab(app, "Студія")
        dwell(1.0)
        NSLog("REEL_T0 %.3f", Date().timeIntervalSince1970)
        mark("Студія")
        dwell(1.6)                      // candidate cards linger

        // sign both candidates (label tier 0 = exactly 2 slots)
        tapIfPossible(app, "sign0"); dwell(1.2)
        tapIfPossible(app, "sign1"); dwell(1.2)

        // three played weeks: release -> end week (endWeek unlocks on release)
        for _ in 0..<3 {
            releaseAnyone(app)
            dwell(1.4)
            tapIfPossible(app, "endWeek")
            dwell(1.2)
        }
        // a tour if any artist can afford one
        if tapIfPossible(app, "tour0") || tapIfPossible(app, "tour1") { dwell(1.4) }

        // ── label management ──
        tapTab(app, "Лейбл")
        mark("Лейбл")
        dwell(1.6)
        tapIfPossible(app, "hire0")     // hire the manager
        dwell(1.2)
        app.swipeUp(); dwell(1.4)       // reveal the equipment shop
        app.swipeUp(); dwell(1.4)

        // ── world trends ──
        tapTab(app, "Тренди")
        mark("Тренди")
        dwell(2.0)
        app.swipeUp(); dwell(1.6)

        // ── back to the studio: the label has visibly progressed ──
        tapTab(app, "Студія")
        mark("Фінал")
        dwell(1.2)
        releaseAnyone(app)
        dwell(1.4)
        tapIfPossible(app, "endWeek")
        dwell(2.2)

        NSLog("REEL_END %.3f", Date().timeIntervalSince1970)
    }

    // MARK: helpers

    private func releaseAnyone(_ app: XCUIApplication) {
        for slot in 0..<2 where tapIfPossible(app, "release\(slot)") { return }
    }

    /// Tap a button by accessibility id if it exists and is enabled; scroll
    /// once to bring it on-screen when it's below the fold.
    @discardableResult
    private func tapIfPossible(_ app: XCUIApplication, _ id: String) -> Bool {
        let btn = app.buttons[id].firstMatch
        guard btn.waitForExistence(timeout: 2), btn.isEnabled else { return false }
        if !btn.isHittable { app.swipeUp() }
        guard btn.isHittable else { return false }
        btn.tap()
        return true
    }

    private func tapTab(_ app: XCUIApplication, _ label: String) {
        let tab = app.tabBars.buttons[label].firstMatch
        if tab.waitForExistence(timeout: 4) { tab.tap() }
    }

    private func mark(_ key: String) {
        NSLog("REEL_SCENE %@ %.3f", key, Date().timeIntervalSince1970)
    }

    private func dwell(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }
}
