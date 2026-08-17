import XCTest

/// The second app-preview tour: Analysis handing a value to a calculator.
///
/// ## Why a fork rather than an extra scene in `ReelTour`
///
/// A screenshot — and a reel — freezes the build it was taken from. The existing tour is the reel of
/// an app with 26 tools and no source; splicing Measure into it would invalidate that footage the day
/// Analysis ships and leave no way to record the old story again. Two tours, two reels, and whichever
/// is current gets captured.
///
/// ## Why it skips
///
/// The Measure entry is **absent** on a released SDK, so without the override there is nothing to
/// record — and a tour that silently recorded 40 seconds of the catalog would produce a plausible,
/// wrong reel. `make_reel.sh` passes `ONLY_TESTING`, so this runs only when it is asked for.
final class ReelTourMeasure: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    func testMeasureTour() throws {
        let app = XCUIApplication()
        if let lang = ProcessInfo.processInfo.environment["OVERTONELAB_LANG"], !lang.isEmpty {
            app.launchEnvironment["OVERTONELAB_LANG"] = lang
        }
        // The reel needs a measurement to show; a live capture in a simulator has no audio.
        app.launchEnvironment["OVERTONELAB_MEASURE"] = "1"
        app.launchEnvironment["OVERTONELAB_SESSION"] = Self.fixture
        app.launch()

        try XCTSkipUnless(any(app, "catalog.measure").waitForExistence(timeout: 15),
                          "Audio Analysis is not available in this build — nothing to record")

        NSLog("REEL_T0 %.3f", Date().timeIntervalSince1970)
        dwell(1.4)

        // ── Scene 1 · the source in the catalog
        mark("Measure")
        any(app, "catalog.measure").tap()
        dwell(2.4)

        // ── Scene 2 · what it found. One hero, no verdict.
        mark("Results")
        dwell(2.6)

        // ── Scene 3 · handing a value over, and it arriving marked
        mark("Handoff")
        any(app, "send.tempo").tap()
        _ = any(app, "result.tempo").waitForExistence(timeout: 10)
        dwell(3.2)

        NSLog("REEL_END %.3f", Date().timeIntervalSince1970)
    }

    private static let fixture = """
    {"id":"1B4E28BA-2FA1-11D2-883F-0016D3CCA427","sourceName":"Take 3.wav",\
    "measuredAt":"2026-08-06T10:24:00Z","bpm":128,"keyTonic":"F#","keyIsMinor":true,\
    "integratedLUFS":-18.3,"peakDB":-0.7,"barCount":32}
    """

    private func mark(_ key: String) { NSLog("REEL_SCENE %@ %.3f", key, Date().timeIntervalSince1970) }
    private func dwell(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }
}
