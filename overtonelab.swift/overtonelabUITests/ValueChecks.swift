import XCTest

/// UI value tests — assert the numbers the app actually DISPLAYS match the known-correct math,
/// end-to-end (View → ViewModel → Kit). Complements the Kit oracle unit tests: those prove the
/// math; these prove the app-layer wiring (unit conversions, bindings, formatting) shows it right.
///
/// Each tool is opened directly via the `OVERTONELAB_TOOL` deep-link (a fresh launch per tool) —
/// no catalog scrolling, so it stays reliable as the catalog grows. Every expected value is a
/// default-state result computed from a cited formula.
final class ValueChecks: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testDisplayedValuesMatchMath() {
        // Tempo — 120 BPM quarter note → 60000/120 = 500 ms; rate 1000/500 = 2 Hz.
        check("tempo", ["500.00 ms", "2.000 Hz"])
        // Pitch — MIDI 69 = A4 = 440 Hz (ISO 16); λ = 343/440 = 0.780 m.
        check("pitch", ["440.00 Hz", "0.780 m"])
        // Sabine — V=200 m³, A=40 sabins → RT60 = 0.161·V/A = 0.81 s; Schroeder = 127 Hz.
        check("sabine", ["0.81 s", "127 Hz"])
        // Bernoulli — 0.5 m open pipe → f = c/(2L) = 343 Hz.
        check("bernoulli", ["343.0 Hz"])
        // Butterworth — order 4 low-pass at fc: exactly −3.01 dB.
        check("butterworth", ["-3.01 dB"])
        // Passive — RC: R=1 kΩ, C=1 µF → f = 1/(2πRC) = 159.15 Hz.
        check("passive", ["159.15 Hz"])
        // Thiele — Fs25/Qts0.4/Vas100, target Qtc 0.707 → Vb = 47.1 L.
        check("thiele", ["47.1 L"])
        // Benchmark — −20 dBFS stereo 1 kHz tone through the real BS.1770 engine → −19.99 LUFS.
        check("benchmark", ["-19.99 LUFS"])
        // Biquad — LPF, fs 48k, f0 1 kHz, Q 0.707 → magnitude at f0 = −3.01 dB (RBJ cookbook).
        check("biquad", ["-3.01 dB"])
        // Room Modes — L=5 m → first axial mode c/(2·5) = 34.3 Hz.
        check("roommodes", ["34.3 Hz"])
        // Air — speed of sound at 20 °C = 343.2 m/s (ISO 9613-1 / 331.3·√(1+T/273.15)).
        check("air", ["343.2 m/s"])
        // SBIR — boundary at 0.6 m → first notch c/(4·0.6) = 143 Hz.
        check("sbir", ["143 Hz"])
        // Compressor — in −10, thr −20, ratio 4 → gain reduction (x−T)(1−1/R) = 7.5 dB.
        check("compressor", ["7.5 dB"])
        // SRA — default ORTF (cardioid, 110°, 17 cm) → recording angle ≈ 96° (Sengpiel/DPA/Williams).
        check("sra", ["96°"])
    }

    /// Launch straight into `toolRaw` (deep-link) and assert every displayed value string appears.
    private func check(_ toolRaw: String, _ values: [String]) {
        let app = XCUIApplication()
        app.launchEnvironment["OVERTONELAB_TOOL"] = toolRaw
        // Pin English: results now follow the app language (a German user reads 0,81 s), so the
        // expected strings below would otherwise depend on the host machine's locale.
        app.launchEnvironment["OVERTONELAB_LANG"] = "en"
        app.launch()
        for v in values {
            XCTAssertTrue(app.staticTexts[v].firstMatch.waitForExistence(timeout: 8),
                          "\(toolRaw): expected displayed value “\(v)” not found")
        }
        app.terminate()
    }
}
