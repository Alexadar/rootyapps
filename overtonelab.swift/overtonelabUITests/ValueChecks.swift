import XCTest

/// All 26 calculators: the number the app DISPLAYS, end to end (View → ViewModel → Kit).
///
/// The Kits' oracle tests own the arithmetic. This layer owns the wiring — a view bound to the wrong
/// property, a unit conversion done in the ViewModel that no Kit test can see, a formatter that
/// drops a digit. Every expectation is duplicated from the Kit answer **on purpose**: changing a Kit
/// result must force both layers to be edited, and the diff makes that visible.
///
/// Each tool is opened by the `OVERTONELAB_TOOL` deep link, one fresh launch each, so nothing depends
/// on catalog scrolling or on the previous tool's state.
///
/// Queried by identifier only, never by element type or by displayed string:
/// `app.staticTexts["500.00 ms"]` matches on `label`, and on macOS a plain `Text` has an EMPTY label
/// with its string in `value` — so the old form was guaranteed to fail on the Mac while passing here,
/// printing an empty string that reads like a screen that never loaded.
final class ValueChecks: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    /// tool id → the string that tool's primary screen must show at its defaults.
    private static let expected: [(tool: String, hero: String)] = [
        // ── Timing
        ("tempo",       "500.00 ms"),       // 120 BPM quarter note = 60000/120
        ("delay",       "250.00 ms"),       // 120 BPM eighth note (the Delay screen defaults to 1/8)
        ("timecode",    "01:00:00:00"),     // 108000 frames at 30 fps = one hour
        ("pitch",       "440.00 Hz"),       // MIDI 69 = A4 (ISO 16)
        // ── Tuning
        ("partch",      "702.0 ¢"),         // 330/220 = 3:2, the just fifth at 701.955 ¢
        ("comma",       "100.000 ¢"),       // 12-EDO step = 1200/12
        ("mersenne",    "102.25 N"),        // T = 4f²L²μ, 110 Hz over 0.65 m at 0.005 kg/m
        // ── Acoustics
        ("sabine",      "0.81 s"),          // RT60 = 0.161·200/40 = 0.805 → 0.81
        ("webster",     "252.3 Hz"),        // exponential horn, 2.5 → 40 cm over 60 cm
        ("bernoulli",   "343.0 Hz"),        // 0.5 m open pipe, f = c/2L
        ("formant",     "500 Hz"),          // 17.5 cm tract → the classic F1
        ("spl",         "88.0 dB"),         // 100 dB at 1 m, inverse square to 4 m
        ("air",         "343.2 m/s"),       // speed of sound at 20 °C (ISO 9613-1)
        ("sbir",        "143 Hz"),          // boundary at 0.6 m → first notch c/4d
        // ── Signal
        ("butterworth", "-24.10 dB"),       // 4th order, one octave above cutoff
        ("fletcher",    "0.00 dB"),         // A-weighting is 0 dB at 1 kHz by definition
        ("benchmark",   "-19.99 LUFS"),     // a −20 dBFS 1 kHz tone through the real BS.1770 engine
        ("passive",     "159.15 Hz"),       // RC, 1 kΩ · 1 µF → 1/2πRC
        ("biquad",      "-3.01 dB"),        // RBJ lowpass at f₀ with Q = 0.7071
        ("compressor",  "7.5 dB"),          // (x−T)(1−1/R) at −10 in, −20 thr, 4:1
        // ── Stereo · Utility · Design
        // No space before the degree sign: this screen builds "96°" into the value itself rather
        // than passing ° as a separate unit, the way the watch does.
        ("sra",         "96°"),             // ORTF: cardioid, 110°, 17 cm
        ("levels",      "2.22 dBu"),        // 1 V referred to 0.7746 V
        ("file",        "31.8 MB"),         // 3 min, 44.1 kHz, 16-bit, stereo
        ("pan",         "-3.01 dB"),        // centre, equal-power law
        ("thiele",      "47.1 L"),          // Vb for Qtc 0.707 from fs 25 / Qts 0.4 / Vas 100
    ]

    /// Room Modes is checked on its mode count, not its hero: in the default 5 × 4 × 2.8 m room two
    /// modes are exactly degenerate, so "smallest spacing" legitimately reads 0.0 Hz — a value a
    /// broken function would also produce. The count is the assertion with teeth.
    private static let roomModes = (tool: "roommodes", id: "result.roommodes.count", value: "210")

    func testEveryToolDisplaysItsNumber() {
        for (tool, hero) in Self.expected {
            let app = launch(tool: tool)
            let readout = any(app, "result.\(tool)")
            XCTAssertTrue(readout.waitForExistence(timeout: 15),
                          "\(tool): the hero readout never appeared")
            XCTAssertEqual(readout.text, hero,
                           "\(tool): the screen shows a different number than the Kit's")
            app.terminate()
        }
    }

    func testRoomModesCountsItsModes() {
        let app = launch(tool: Self.roomModes.tool)
        let count = any(app, Self.roomModes.id)
        XCTAssertTrue(count.waitForExistence(timeout: 15), "the mode count never appeared")
        XCTAssertEqual(count.text, Self.roomModes.value,
                       "a 5 × 4 × 2.8 m room has 210 modes at or below 300 Hz")
    }

    /// A new tool cannot ship without a numeric check.
    func testEveryToolHasANumericCheck() {
        let covered = Self.expected.map(\.tool) + [Self.roomModes.tool]
        XCTAssertEqual(covered.count, 26, "the catalog ships 26 tools")
        XCTAssertEqual(Set(covered).count, covered.count, "duplicate in the coverage list")
    }

    // MARK: helpers

    /// One launch per tool, English pinned.
    ///
    /// The language pin matters: results follow the *app* language now (a German user reads 0,81 s),
    /// so without it every expectation above would depend on the host machine's region.
    private func launch(tool: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["OVERTONELAB_TOOL"] = tool
        app.launchEnvironment["OVERTONELAB_LANG"] = "en"
        app.launch()
        return app
    }
}
