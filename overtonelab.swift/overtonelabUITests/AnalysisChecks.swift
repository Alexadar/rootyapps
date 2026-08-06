import XCTest

/// Audio Analysis, exercised with **no microphone and no framework**.
///
/// `OVERTONELAB_MEASURE=1` puts the catalog entry back (it is absent on a released SDK, which is the
/// whole availability design) and `OVERTONELAB_SESSION=<json>` seeds a fixture measurement. Between
/// them the entire feature is reachable in a test: the marking, the routing, the revert, and the one
/// rule that has to hold forever — Analysis reports, `benchmark` judges.
final class AnalysisChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// A complete session: 128 BPM, F# minor, −18.3 LUFS. Enough to feed tempo, delay, pitch, partch
    /// and benchmark, which is every route the app can honestly serve.
    private static let fixture = """
    {"id":"1B4E28BA-2FA1-11D2-883F-0016D3CCA427","sourceName":"Take 3.wav",\
    "measuredAt":"2026-08-06T10:24:00Z","bpm":128,"keyTonic":"F#","keyIsMinor":true,\
    "integratedLUFS":-18.3,"peakDB":-0.7,"barCount":32}
    """

    private func launch(tool: String? = nil, session: String? = fixture) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["OVERTONELAB_MEASURE"] = "1"
        app.launchEnvironment["OVERTONELAB_LANG"] = "en"
        if let session { app.launchEnvironment["OVERTONELAB_SESSION"] = session }
        if let tool { app.launchEnvironment["OVERTONELAB_TOOL"] = tool }
        app.launch()
        return app
    }

    // MARK: - Availability

    /// Present only behind the override. The absent case is asserted at the unit level, because a UI
    /// test cannot prove the *absence* of a row it was never told the identifier of.
    func testMeasureAppearsInTheCatalogWhenAvailable() {
        let app = launch(session: nil)
        XCTAssertTrue(any(app, "catalog.measure").waitForExistence(timeout: 15),
                      "the Measure entry must be in the catalog when Analysis is available")
    }

    // MARK: - The benchmark boundary

    /// ⚠ THE RULE THAT KEEPS LUFS IN ONE PLACE. Analysis measures loudness; `benchmark` alone reasons
    /// about it. If a screen here ever compares against a target, this fails — which is exactly what
    /// should happen, because the fix is to move that screen into `benchmark`.
    func testAnalysisRendersNoTargetNoDeltaNoVerdict() {
        let app = launch()
        any(app, "catalog.measure").tap()
        XCTAssertTrue(any(app, "measure.lufs").waitForExistence(timeout: 15),
                      "the measured loudness must be on screen for this test to mean anything")

        for forbidden in ["result.target", "result.delta", "result.verdict",
                          "measure.target", "measure.delta", "measure.verdict"] {
            XCTAssertFalse(any(app, forbidden).exists,
                           "Analysis must not render \(forbidden) — that reasoning belongs to benchmark")
        }
        // And no target platform is named anywhere on the screen.
        for word in ["Spotify", "Apple Music", "EBU R128"] {
            XCTAssertFalse(app.descendants(matching: .any).containing(textMatches(word)).firstMatch.exists,
                           "naming \(word) here would put loudness judgement in two places")
        }
    }

    // MARK: - Provenance

    /// The three signals, and the one that survives images off: the spoken value.
    func testAHandedValueIsMarkedMeasured() {
        let app = launch()
        any(app, "catalog.measure").tap()

        let send = any(app, "send.tempo")
        XCTAssertTrue(send.waitForExistence(timeout: 15), "tempo must be offered — the fixture has BPM")
        send.tap()

        let field = any(app, "result.tempo")
        XCTAssertTrue(field.waitForExistence(timeout: 15), "the tempo screen must open")
        // 128 BPM quarter note = 468.75 ms. The measured value really reached the calculation.
        XCTAssertEqual(field.text, "468.75 ms",
                       "the handed BPM must drive the tool's own maths, not just sit in a box")

        // Provenance rides in the accessibility VALUE, so it is there with images off.
        let marked = app.descendants(matching: .any).containing(textMatches("Measured")).firstMatch
        XCTAssertTrue(marked.waitForExistence(timeout: 5),
                      "the word Measured is one of the three signals and must be present")
    }

    /// Editing clears the marking — there is no "measured but modified".
    func testTypingClearsTheMeasuredMarking() throws {
        let app = launch()
        any(app, "catalog.measure").tap()
        any(app, "send.tempo").tap()
        XCTAssertTrue(any(app, "result.tempo").waitForExistence(timeout: 15))

        let marked = app.descendants(matching: .any).containing(textMatches("Measured")).firstMatch
        XCTAssertTrue(marked.waitForExistence(timeout: 5), "precondition: it starts marked")

        // Type into the tempo field. The first keystroke must drop the marking.
        let entry = app.textFields.firstMatch
        try XCTSkipUnless(entry.waitForExistence(timeout: 5), "no editable field on this platform")
        entry.tap()
        entry.typeText("90\n")

        XCTAssertFalse(app.descendants(matching: .any).containing(textMatches("Measured")).firstMatch.exists,
                       "a value the user changed is theirs — the marking must go immediately")
    }

    // MARK: - Session outlives the stack

    /// `MeasurementStore` is a sibling of `FavoritesStore` on `RootView`, so leaving Analysis discards
    /// a view and not a session. Measure once, visit a calculator, come back — still there.
    func testSessionSurvivesLeavingAndReturning() {
        let app = launch()
        any(app, "catalog.measure").tap()
        XCTAssertTrue(any(app, "measure.bpm").waitForExistence(timeout: 15))

        any(app, "send.tempo").tap()
        XCTAssertTrue(any(app, "result.tempo").waitForExistence(timeout: 15))

        // Back to the catalog, then into Measure again.
        app.navigationBars.buttons.firstMatch.tap()
        if any(app, "catalog.measure").waitForExistence(timeout: 10) {
            any(app, "catalog.measure").tap()
        }
        XCTAssertTrue(any(app, "measure.bpm").waitForExistence(timeout: 15),
                      "the measurement must still be there — popping discards a view, not a session")
    }
}
