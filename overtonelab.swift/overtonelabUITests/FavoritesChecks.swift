import XCTest

/// Favorites CRUD + persistence, exercised through the iPhone (compact) catalog grid.
/// The tile star exposes `accessibilityIdentifier "fav.<rawValue>"` and `accessibilityValue`
/// "on"/"off", so we can drive and read favorite state deterministically.
/// Defaults are Partch + Benchmark, so Butterworth starts unfavorited — a clean subject.
///
/// ## Why this whole class is compact-only
///
/// The star tile exists in `CatalogGrid`, which is the **compact** root. At regular width — an iPad in
/// landscape, or macOS, where the split view is the only layout — there is no grid and no tile: the
/// sidebar offers favouriting through a swipe action instead. So on an iPad this would fail looking
/// exactly like a missing control, when the control was never meant to be there. Skipped rather than
/// deleted, because the compact path is the one most users are on.
final class FavoritesChecks: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// True where `CatalogGrid` is the root. `XCUIDevice.current.userInterfaceIdiom` is not enough —
    /// an iPad in landscape is `.pad` and regular, an iPad in a narrow split is `.pad` and compact —
    /// so the layout is detected by what the app actually published: the grid's stars.
    private func isCompactCatalog(_ app: XCUIApplication) -> Bool {
        any(app, "fav.butterworth").waitForExistence(timeout: 8)
            || any(app, "fav.partch").waitForExistence(timeout: 2)
    }

    func testFavoritesCRUDAndPersistence() throws {
        let app = XCUIApplication()
        app.launch()
        // The skip comes FIRST, and readiness is judged by the grid's own stars rather than by a
        // navigation bar: macOS has no `NavigationBar` element at all, so waiting for one there
        // failed with "catalog missing" — a message that reads like the app not launching, when the
        // truth is that this screen does not exist on that platform.
        try XCTSkipUnless(isCompactCatalog(app),
                          "regular layout: the catalog is a sidebar, and favouriting is a swipe action")

        // READ: whatever state Butterworth is in RIGHT NOW.
        //
        // Not "it starts off". Favourites are persisted, so a rerun on a simulator that was kept
        // alive for a fix loop starts from the state the previous run left — and asserting the
        // default made this test pass once and then fail on every rerun, which reads like a bug in
        // favouriting rather than a bug in the test. Toggling is what is being tested; the starting
        // side of the toggle is not.
        let star = firstStar(app, "butterworth")
        scrollToHittable(app, star)
        XCTAssertTrue(star.waitForExistence(timeout: 5), "Butterworth star not found")
        let initial = star.value as? String
        XCTAssertTrue(initial == "on" || initial == "off",
                      "the star must publish its state, got \(initial ?? "nil")")
        let flipped = initial == "on" ? "off" : "on"

        // CREATE/DELETE: flip it → the tapped control reports the other state.
        star.tap()
        let afterFlip = firstStar(app, "butterworth")
        scrollToHittable(app, afterFlip)
        XCTAssertEqual(afterFlip.value as? String, flipped, "the star did not change state")

        // PERSIST: relaunch — the new state survives.
        app.terminate()
        app.launch()
        XCTAssertTrue(isCompactCatalog(app), "the catalog did not come back after a relaunch")
        let restored = firstStar(app, "butterworth")
        scrollToHittable(app, restored)
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        XCTAssertEqual(restored.value as? String, flipped, "favourite state did not survive a relaunch")

        // RETURN: flip back, so the test leaves the app as it found it and the next run is unaffected.
        restored.tap()
        let final = firstStar(app, "butterworth")
        scrollToHittable(app, final)
        XCTAssertEqual(final.value as? String, initial, "flipping back did not restore the state")
    }

    // MARK: helpers

    /// By identifier, not by type: SwiftUI publishes this star as a `button` on iOS but there is no
    /// guarantee across platforms or across a modifier change, and a type mismatch fails with a
    /// message indistinguishable from the tile never rendering.
    private func firstStar(_ app: XCUIApplication, _ raw: String) -> XCUIElement {
        any(app, "fav.\(raw)")
    }

    /// ⚠ `.exists` must be checked before `.isHittable`.
    ///
    /// `any(...)` builds `descendants(matching: .any).matching(identifier:).firstMatch`, and asking a
    /// `firstMatch` with no matches for `.isHittable` **raises** "Failed to get matching snapshot"
    /// instead of returning false. The old typed subscript (`app.buttons["…"]`) resolved lazily and
    /// quietly returned false, so this loop worked by accident — and swapping in the cross-platform
    /// query turned a scroll into a hard failure that read like a missing tile.
    private func scrollToHittable(_ app: XCUIApplication, _ el: XCUIElement) {
        var n = 0
        while !(el.exists && el.isHittable) && n < 14 {
            app.swipeUp(velocity: .init(rawValue: 500))
            n += 1
        }
    }
}
