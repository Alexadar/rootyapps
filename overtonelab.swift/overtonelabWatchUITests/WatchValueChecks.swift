import XCTest

/// All 26 calculators, on the wrist.
///
/// The watch is not a thin view onto the phone: each screen calls its Kit directly, with its own
/// defaults chosen for a 41 mm screen (Air probes 4 kHz, not 1 kHz; Thiele drives a fixed driver).
/// So "the phone is green" says nothing about these numbers, and a wrong unit or a wrong default
/// here would ship looking perfectly plausible.
///
/// Every expectation below was produced by running the same Kit calls with the same defaults through
/// the same formatting rules as `Fmt` (grouping never, half-away-from-zero, en_US) — duplicated here
/// on purpose, so that changing a Kit answer forces both layers to be updated and the diff shows it.
final class WatchValueChecks: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    /// tool id → the string its hero readout must publish, unit included.
    private static let expected: [(tool: String, hero: String)] = [
        // ── Timing
        ("tempo",       "500.0 ms"),        // 120 BPM quarter note = 60000/120
        ("delay",       "500.0 ms"),        // same figure by the delay path
        ("timecode",    "01:00:00:00"),     // 108000 frames at 30 fps = one hour
        ("pitch",       "440.00 Hz"),       // MIDI 69 = A4 (ISO 16)
        // ── Tuning
        ("partch",      "702.0 ¢"),         // 330/220 = 3:2, the just fifth at 701.955 ¢
        ("comma",       "100.00 ¢"),        // 12-EDO step = 1200/12
        ("mersenne",    "102.2 N"),         // T = 4f²L²μ, 110 Hz over 0.65 m at 0.005 kg/m
        // ── Acoustics
        ("sabine",      "0.81 s"),          // RT60 = 0.161·200/40 = 0.805 → 0.81
        ("webster",     "252.3 Hz"),        // exponential horn, 2.5→40 cm over 60 cm
        ("bernoulli",   "343.0 Hz"),        // 0.5 m open pipe, f = c/2L
        ("formant",     "500 Hz"),          // 17.5 cm tract → the classic F1
        ("spl",         "88.0 dB"),         // 100 dB at 1 m, inverse square to 4 m
        ("roommodes",   "34.3 Hz"),         // 5 m length → first axial c/2L
        ("air",         "2.97 dB"),         // ISO 9613, 4 kHz over 100 m at 20 °C / 50 %
        ("sbir",        "142.9 Hz"),        // boundary at 0.6 m → first notch c/4d
        // ── Signal
        ("butterworth", "-24.10 dB"),       // 4th order, one octave above cutoff
        ("fletcher",    "+0.00 dB"),        // A-weighting is 0 dB at 1 kHz by definition
        ("benchmark",   "-5.0 dB"),         // −9 LUFS measured against a −14 target
        ("passive",     "159.2 Hz"),        // RC, 1 kΩ · 1 µF → 1/2πRC
        ("biquad",      "-3.01 dB"),        // RBJ lowpass at f₀ with Q = 0.7071
        ("compressor",  "7.50 dB"),         // (x−T)(1−1/R) at −10 in, −20 thr, 4:1
        // ── Stereo · Utility · Design
        ("sra",         "95.7 °"),          // ORTF: cardioid, 110°, 17 cm
        ("levels",      "1.995 ×"),         // +6 dB in voltage
        ("file",        "51.8 MB"),         // 3 min, 48 kHz, 24-bit, stereo
        ("pan",         "-3.0 dB"),         // centre, equal-power law
        ("thiele",      "0.693"),           // Qtc = Qts·√(α+1) = 0.4·√3
    ]

    func testEveryWatchScreenShowsItsNumber() {
        for (tool, hero) in Self.expected {
            let app = XCUIApplication()
            // The same launch argument the app already reads to restore the last-used tool, so the
            // test opens a screen the way the app itself does rather than through a test-only path.
            app.launchArguments += ["-otl.watch.lastTool", tool]
            app.launch()

            let readout = any(app, "result.\(tool)")
            XCTAssertTrue(readout.waitForExistence(timeout: 30),
                          "\(tool): the hero readout never appeared on the watch")
            XCTAssertEqual(readout.readoutValue, hero,
                           "\(tool): the wrist shows a different number than the Kit's")
            app.terminate()
        }
    }

    /// A new tool cannot ship with no watch check: the catalog is 26 and so is this list.
    func testEveryToolHasAWatchCheck() {
        XCTAssertEqual(Self.expected.count, 26, "the catalog ships 26 tools")
        let ids = Self.expected.map(\.tool)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate tool in the coverage list")
    }
}
