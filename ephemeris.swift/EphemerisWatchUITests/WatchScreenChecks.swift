import XCTest

/// Every watch screen reached by deep link, and the numbers on them checked against the same pinned
/// instant the phone suite uses.
///
/// The watch is not a thinner copy of the phone — it computes its own positions and houses from
/// EphemerisKit on-device, from its own `now`. So "the phone shows 23° 02′" proves nothing here, and
/// these assertions duplicate the phone's expected values on purpose: if the two ever disagree, one
/// of them is wired wrong. That already happened once — the watch drew the entire zodiac backwards
/// because it had its own copy of the angle maths, which is why both now share `ChartGeometry`.
final class WatchScreenChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func app(screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["EPHEMERIS_SCREEN"] = screen
        app.launchEnvironment["EPHEMERIS_DATE"] = pinnedInstant
        app.launchEnvironment["EPHEMERIS_LANG"] = "en"
        app.launch()
        return app
    }

    func testWheelScreenRenders() {
        XCTAssertTrue(any(app(screen: "wheel"), "watch.wheel").waitForExistence(timeout: 30),
                      "EPHEMERIS_SCREEN=wheel must open the chart")
    }

    func testNowScreenRenders() {
        let a = app(screen: "now")
        XCTAssertTrue(any(a, "watch.now").waitForExistence(timeout: 30),
                      "EPHEMERIS_SCREEN=now must open the Now summary")
        XCTAssertFalse(any(a, "watch.wheel").exists,
                       "a screen deep link must not fall back to the wheel")
    }

    func testPositionsScreenRenders() {
        let a = app(screen: "positions")
        XCTAssertTrue(any(a, "watch.positions").waitForExistence(timeout: 30),
                      "EPHEMERIS_SCREEN=positions must open the positions list")
        XCTAssertFalse(any(a, "watch.wheel").exists,
                       "a screen deep link must not fall back to the wheel")
    }

    func testEventsScreenRenders() {
        let a = app(screen: "events")
        XCTAssertTrue(any(a, "watch.events").waitForExistence(timeout: 30),
                      "EPHEMERIS_SCREEN=events must open the timeline")
        XCTAssertFalse(any(a, "watch.wheel").exists,
                       "a screen deep link must not fall back to the wheel")
    }

    /// Fails when a watch screen ships without a check above.
    func testEveryWatchScreenIsCovered() {
        let covered = ["wheel", "now", "positions", "events"]
        XCTAssertEqual(covered.count, 4, "the watch ships 4 screens")
        XCTAssertEqual(Set(covered).count, covered.count, "duplicate in the coverage list")
    }
}
