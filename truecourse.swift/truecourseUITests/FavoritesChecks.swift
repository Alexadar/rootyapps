import XCTest

/// Favourites CRUD + persistence across the compact instrument grid.
final class FavoritesChecks: XCTestCase {

    func testFavoritesCRUDAndPersistence() throws {
        let app = XCUIApplication()
        app.launch()

        // READ — "airspeed" is not a default favourite.
        let star = app.buttons["fav.airspeed"].firstMatch
        guard star.waitForExistence(timeout: 8) else {
            // Regular width (iPad/Mac) uses the sidebar instead of the grid — skip there.
            throw XCTSkip("Compact catalog grid not present on this size class")
        }
        XCTAssertEqual(star.value as? String, "off")

        // CREATE — star it.
        star.tap()
        XCTAssertEqual(app.buttons["fav.airspeed"].firstMatch.value as? String, "on")

        // PERSIST — relaunch; the favourite survives.
        app.terminate()
        app.launch()
        XCTAssertEqual(app.buttons["fav.airspeed"].firstMatch.value as? String, "on")

        // DELETE — un-star.
        app.buttons["fav.airspeed"].firstMatch.tap()
        XCTAssertEqual(app.buttons["fav.airspeed"].firstMatch.value as? String, "off")
    }
}
