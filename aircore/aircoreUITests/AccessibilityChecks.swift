import XCTest

/// The accessibility floor, which for this app is a stated requirement rather than a nicety:
/// Dynamic Type throughout, VoiceOver on every computed value **and on the chart**, and nothing
/// conveyed by colour alone.
final class AccessibilityChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    // MARK: - Dynamic Type

    /// At the largest accessibility size the app must still be usable: results present, unit
    /// toggle reachable. The grids collapse to one column past `.accessibility1` precisely so this
    /// holds — at two columns a number and its label cannot both fit at that size.
    func testToolsSurviveAccessibilityXXXL() {
        for tool in ["psychrometrics", "duct", "pipe"] {
            let app = launchApp(tool: tool,
                                contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
            XCTAssertTrue(any(app, "\(tool).hero").waitForExistence(timeout: 15),
                          "\(tool) showed no result at accessibility XXXL")
            let toggle = app.buttons["settings.units"]
            XCTAssertTrue(toggle.exists, "\(tool) lost its unit toggle at accessibility XXXL")
            XCTAssertTrue(toggle.isHittable, "\(tool)'s unit toggle is not reachable")
            app.terminate()
        }
    }

    /// The catalogue is the first screen, and a two-column grid of cards is where large type
    /// breaks first.
    func testTheCatalogueSurvivesAccessibilityXXXL() throws {
        let app = launchApp(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        guard any(app, "tool.psychrometrics").waitForExistence(timeout: 10) else {
            throw XCTSkip("regular width shows a sidebar, not a catalogue")
        }
        let cards = app.descendants(matching: .any).matching(identifier: "tool.psychrometrics")
        XCTAssertTrue(cards.allElementsBoundByIndex.contains { $0.isHittable },
                      "the first tool card is unreachable at accessibility XXXL")
    }

    // MARK: - VoiceOver

    /// **A chart invisible to VoiceOver is a failed screen.** The state point has to be its own
    /// element with a spoken value carrying the whole condition — not a decorative shape.
    func testTheChartIsReachableByVoiceOver() throws {
        let app = launchApp(tool: "psychrometrics")
        XCTAssertTrue(any(app, "psychro.chart").waitForExistence(timeout: 15),
                      "the chart publishes no accessibility element")

        let point = any(app, "psychro.point.a")
        XCTAssertTrue(point.waitForExistence(timeout: 5),
                      "the state point is invisible to VoiceOver")

        let spoken = point.label + " " + ((point.value as? String) ?? "")
        for phrase in ["dry bulb", "wet bulb", "relative humidity"] {
            XCTAssertTrue(spoken.contains(phrase), "the point does not say \(phrase): \(spoken)")
        }
        // Symbols must be spelled out: VoiceOver reads "°F" as "degree F" and "ft³/lb" as noise.
        XCTAssertFalse(spoken.contains("°"), "the spoken value contains a degree sign: \(spoken)")
        XCTAssertFalse(spoken.contains("/"), "the spoken value contains a slash: \(spoken)")
    }

    /// Every result announces what it is and what it says. A number with no label is a number a
    /// screen-reader user cannot use.
    func testEveryResultAnnouncesItselfAndItsValue() {
        let app = launchApp(tool: "psychrometrics")
        XCTAssertTrue(any(app, "psychrometrics.hero").waitForExistence(timeout: 15))

        for identifier in ["psychrometrics.hero", "psychrometrics.dryBulb",
                           "psychrometrics.relativeHumidity", "psychrometrics.enthalpy"] {
            let tile = any(app, identifier)
            XCTAssertTrue(tile.exists, "\(identifier) is not addressable")

            // Read label AND value: macOS drops `accessibilityValue` on these tiles, which is why
            // the whole utterance now lives in the label. Asserting on `value` alone would have
            // passed on iOS while the Mac announced no numbers at all.
            let spoken = tile.label + " " + ((tile.value as? String) ?? "")
            XCTAssertFalse(spoken.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(identifier) says nothing")
            XCTAssertTrue(spoken.contains(where: \.isNumber),
                          "\(identifier) announces its name but no number: \(spoken)")
            XCTAssertTrue(spoken.first?.isLetter == true,
                          "\(identifier) leads with its number, not its name: \(spoken)")
            XCTAssertFalse(spoken.contains("°"), "\(identifier) speaks a degree sign: \(spoken)")
            XCTAssertFalse(spoken.contains("/"), "\(identifier) speaks a slash: \(spoken)")
        }
    }

    /// Nothing by colour alone: a warning has to be legible as words, because a red banner in
    /// bright sun on a phone at arm's length is a grey banner.
    func testWarningsCarryWordsNotJustColour() {
        let app = launchApp(tool: "duct")
        let banner = any(app, "duct.velocityBanner")
        XCTAssertTrue(banner.waitForExistence(timeout: 15))

        let spoken = (banner.label + " " + ((banner.value as? String) ?? "")).lowercased()
        XCTAssertTrue(spoken.contains("within") || spoken.contains("above"),
                      "the banner states its outcome only in colour: \(spoken)")
    }

    /// The elevation chip is the app's claim that altitude is never silently wrong, so it has to
    /// announce the elevation it is set to.
    func testTheElevationChipAnnouncesItsValue() {
        let app = launchApp(tool: "psychrometrics")
        let chip = app.buttons["settings.elevation"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        XCTAssertEqual(chip.label, "Site elevation")
        let spoken = (chip.value as? String) ?? ""
        XCTAssertTrue(spoken.contains("feet") || spoken.contains("metres"),
                      "the chip does not announce its elevation: \(spoken)")
    }
}
