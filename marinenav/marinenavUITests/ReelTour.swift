import XCTest

/// Reel tour — drives the real app through its five tools for the App Store preview.
///
/// Paced for HUMAN reading speed so `make_reel.sh` does not have to accelerate it:
/// tides gets the longest dwell (it is the product), the rest read as proof of depth.
/// Emits REEL_T0 / REEL_SCENE / REEL_END markers for scene alignment.
final class ReelTour: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    func testReelTour() {
        let app = XCUIApplication()
        app.launch()
        dwell(1.4)
        NSLog("REEL_T0 %.3f", Date().timeIntervalSince1970)

        // ── Scene 1 · Tides — the hero. Curve, now-reading, the high/low table.
        open(app, "tides"); mark("Tides"); dwell(4.2)
        swipeUpGently(app); dwell(3.0)

        // ── Scene 2 · Currents — slack, flood, ebb.
        back(app); open(app, "currents"); mark("Currents"); dwell(3.4)
        swipeUpGently(app); dwell(2.6)

        // ── Scene 3 · Declination — WMM2025 on device.
        back(app); open(app, "declination"); mark("Declination"); dwell(3.6)

        // ── Scene 4 · Distance & bearing — great-circle passage.
        back(app); open(app, "distanceBearing"); mark("Distance"); dwell(3.6)

        // ── Scene 5 · Sight reduction — the credibility feature.
        back(app); open(app, "sightReduction"); mark("Sight"); dwell(2.4)
        swipeUpGently(app); dwell(3.4)

        NSLog("REEL_END %.3f", Date().timeIntervalSince1970)
    }

    // MARK: steps

    /// Tap a catalog row by its accessibility identifier (set in ContentView).
    ///
    /// Queried type-agnostically: SwiftUI publishes the row as a `button` on iOS but not
    /// necessarily on macOS, and the old three-step `buttons` → `otherElements` → `staticTexts`
    /// fallback silently tapped the WRONG thing when the first two missed — which is exactly how
    /// a reel gets captured against the default screen.
    private func open(_ app: XCUIApplication, _ tool: String) {
        let row = toolRow(app, tool)
        if row.waitForExistence(timeout: 4) { row.tap(); return }
        // Last resort only, and now loud about it: a silent fallback produced subtly wrong video.
        NSLog("REEL_WARN row tool.%@ not found by identifier — falling back to its title", tool)
        textElement(app, label(for: tool)).tap()
    }

    private func label(for tool: String) -> String {
        switch tool {
        case "tides": return "Tides"
        case "currents": return "Currents"
        case "declination": return "Declination"
        case "distanceBearing": return "Distance & Bearing"
        default: return "Sight Reduction"
        }
    }

    /// Pop back to the catalog — but ONLY where there is something to pop.
    ///
    /// On iPad and Mac the split view keeps the sidebar on screen permanently, so selecting a
    /// tool swaps the detail pane rather than pushing. There is no back button there, and
    /// `navigationBars.buttons.firstMatch` resolves to the **sidebar toggle** instead — tapping
    /// it collapses the very rows the next `open()` needs, and the rest of the tour lands on
    /// whatever `staticTexts` fallback happens to match. Hittability is the test, not existence:
    /// after an iPhone push the catalog rows are often still in the hierarchy, just off-screen.
    private func back(_ app: XCUIApplication) {
        // Hittability, not existence — after an iPhone push the rows are often still in the
        // hierarchy, just off-screen. Type-agnostic for the same reason as `open`.
        if toolRow(app, "tides").isHittable { dwell(0.4); return }
        let b = app.navigationBars.buttons.firstMatch
        if b.exists { b.tap() }
        dwell(0.7)
    }

    private func swipeUpGently(_ app: XCUIApplication) {
        let s = app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app.tables.firstMatch
        if s.exists {
            s.swipeUp(velocity: .slow)
        } else {
            app.swipeUp(velocity: .slow)
        }
    }

    private func mark(_ key: String) { NSLog("REEL_SCENE %@ %.3f", key, Date().timeIntervalSince1970) }
    private func dwell(_ s: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
}
