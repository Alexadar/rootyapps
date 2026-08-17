import XCTest

/// Shared launch helpers.
///
/// ⚠️ **These tests are written and deliberately NOT run here** (PROMPT §10). The owner runs them;
/// see `../uitests.md` for the per-platform invocations and the macOS accessibility traps that turn
/// an iOS-green suite red.
extension XCUIApplication {

    /// Launches with a photo already imported and a one-second enhancer, so a test spends its time
    /// asserting rather than waiting out a realistic pass.
    static func launchedWithPhoto(enhancer: String = "fast",
                                  extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["STUDIO_FIXTURE_PHOTO"] = "1"
        app.launchEnvironment["STUDIO_ENHANCER"] = enhancer
        // These are US-market apps and several assertions read formatted numbers; a simulator that
        // booted in a comma-decimal region would fail them for the wrong reason.
        app.launchEnvironment["STUDIO_LANG"] = "en"
        for (key, value) in extra { app.launchEnvironment[key] = value }
        app.launch()
        return app
    }

    /// Launches with no photo, on the import screen.
    static func launchedEmpty() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["STUDIO_ENHANCER"] = "fast"
        app.launchEnvironment["STUDIO_LANG"] = "en"
        app.launch()
        return app
    }
}

extension XCTestCase {

    /// `waitForExistence` with a message, because a bare `XCTAssertTrue(element.exists)` in a UI
    /// suite prints nothing about *which* element was missing.
    @discardableResult
    func expect(_ element: XCUIElement,
                _ description: String,
                timeout: TimeInterval = 10,
                file: StaticString = #filePath,
                line: UInt = #line) -> Bool {
        let found = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(found, "never appeared: \(description)", file: file, line: line)
        return found
    }

    func expectGone(_ element: XCUIElement,
                    _ description: String,
                    timeout: TimeInterval = 15,
                    file: StaticString = #filePath,
                    line: UInt = #line) {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "never went away: \(description)", file: file, line: line)
    }
}
