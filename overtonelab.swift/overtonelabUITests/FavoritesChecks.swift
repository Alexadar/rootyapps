import XCTest

/// Favorites CRUD + persistence, exercised through the iPhone (compact) catalog grid.
/// The tile star exposes `accessibilityIdentifier "fav.<rawValue>"` and `accessibilityValue`
/// "on"/"off", so we can drive and read favorite state deterministically.
/// Defaults are Partch + Benchmark, so Butterworth starts unfavorited — a clean subject.
final class FavoritesChecks: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testFavoritesCRUDAndPersistence() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Overtone Lab"].waitForExistence(timeout: 10), "catalog missing")

        // READ (initial): Butterworth is not a default favorite.
        let star = firstStar(app, "butterworth")
        scrollToHittable(app, star)
        XCTAssertTrue(star.waitForExistence(timeout: 5), "Butterworth star not found")
        XCTAssertEqual(star.value as? String, "off", "Butterworth should start unfavorited")

        // CREATE: star it → the tapped control reports 'on'.
        star.tap()
        XCTAssertEqual(firstStar(app, "butterworth").value as? String, "on", "favoriting failed")

        // PERSIST: relaunch — the favorite survives (Favorites group is pinned at the top, so the
        // first star is on-screen immediately, no scrolling needed).
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Overtone Lab"].waitForExistence(timeout: 10))
        let restored = firstStar(app, "butterworth")
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        XCTAssertEqual(restored.value as? String, "on", "favorite did not persist across launch")

        // DELETE: un-star it. This removes the pinned Favorites copy at the top, leaving only the
        // Signal-section tile — scroll down to it and confirm it now reads 'off'.
        restored.tap()
        let signalStar = firstStar(app, "butterworth")
        scrollToHittable(app, signalStar)
        XCTAssertTrue(signalStar.waitForExistence(timeout: 5), "Butterworth tile missing after un-favorite")
        XCTAssertEqual(signalStar.value as? String, "off", "un-favoriting failed")
    }

    // MARK: helpers

    private func firstStar(_ app: XCUIApplication, _ raw: String) -> XCUIElement {
        app.buttons["fav.\(raw)"].firstMatch
    }

    private func scrollToHittable(_ app: XCUIApplication, _ el: XCUIElement) {
        var n = 0
        while !el.isHittable && n < 14 { app.swipeUp(velocity: .init(rawValue: 500)); n += 1 }
    }
}
