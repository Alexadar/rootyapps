import XCTest

/// watchOS UI tests.
///
/// XCUITest IS usable on watchOS — `XCUIDevice.shared.rotateDigitalCrown(delta:)` exists in
/// XCUIAutomation gated on `TARGET_OS_WATCH`. No crown test here, deliberately: eartharound's watch
/// app uses no `digitalCrownRotation` at all, so the focus-stealing regression that affects other
/// apps in this repo cannot occur. Only *appearance* needs a real wrist.
///
/// Pages are reached through `EARTHAROUND_WATCH_PAGE` (validated 0…2) rather than by swiping a
/// `.verticalPage` TabView, which is not reliably scriptable.
final class WatchChecks: XCTestCase {

    override func setUp() { super.setUp(); continueAfterFailure = false }

    private func launch(page: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["EARTHAROUND_FIXTURE"] = "1"
        app.launchEnvironment["EARTHAROUND_LANG"] = "en"
        app.launchEnvironment["EARTHAROUND_WATCH_PAGE"] = "\(page)"
        app.launch()
        return app
    }

    /// Page 0, the hero readout: the Kp value and the 24 h peak added alongside it.
    func testReadoutPageShowsKpAndPeak() {
        let app = launch(page: 0)
        XCTAssertTrue(app.staticTexts.containing(textMatches("KP")).firstMatch
                        .waitForExistence(timeout: 15), "no KP label on the readout page")
        XCTAssertTrue(app.staticTexts.containing(textMatches("24H")).firstMatch.exists,
                      "the 24-hour peak is missing from the readout page")
    }

    /// Page 2, wind: carries both the latest flare and the 24 h peak, the parity added this session.
    func testWindPageShowsFlareAndPeak() {
        let app = launch(page: 2)
        XCTAssertTrue(app.staticTexts.containing(textMatches("WIND")).firstMatch
                        .waitForExistence(timeout: 15), "no WIND label on page 2")
        XCTAssertTrue(app.staticTexts.containing(textMatches("24H")).firstMatch.exists,
                      "the 24-hour peak is missing from the wind page")
    }

    /// Every page renders without dying. The watch app is three pages and a crash on any of them
    /// leaves a blank face.
    func testEveryPageSurvives() {
        for page in 0...2 {
            let app = launch(page: page)
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15),
                          "page \(page) did not reach the foreground")
            XCTAssertEqual(app.state, .runningForeground, "page \(page) died")
        }
    }
}
