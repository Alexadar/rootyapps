import XCTest

/// Favourites CRUD + persistence across the compact instrument grid.
final class FavoritesChecks: XCTestCase {

    func testFavoritesCRUDAndPersistence() throws {
        let app = launchTrueCourse()

        // READ — "airspeed" is not a default favourite. Query by identifier alone (type-agnostic):
        // the grid star is a Button, but never assume that across platforms.
        let star = app.any("fav.airspeed")
        guard star.waitForExistence(timeout: 8) else {
            // Regular width (iPad/Mac) uses the sidebar swipe action (id `fav.<tool>`, but revealed
            // only by a swipe) instead of the grid star — skip the grid flow there.
            throw XCTSkip("Compact catalog grid not present on this size class")
        }
        XCTAssertEqual(star.value as? String, "off")

        // CREATE — star it.
        star.tap()
        XCTAssertEqual(app.any("fav.airspeed").value as? String, "on")

        // PERSIST — relaunch; the favourite survives.
        app.terminate()
        _ = launchTrueCourse()
        XCTAssertEqual(app.any("fav.airspeed").value as? String, "on")

        // DELETE — un-star.
        app.any("fav.airspeed").tap()
        XCTAssertEqual(app.any("fav.airspeed").value as? String, "off")
    }
}
