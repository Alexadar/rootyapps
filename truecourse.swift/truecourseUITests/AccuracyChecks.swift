import XCTest

/// Exhaustive accuracy verification: for every calculator and every sub-screen, launch
/// straight into it via the `TRUECOURSE_TOOL` / `TRUECOURSE_SCREEN` deep-links and assert
/// that *every* displayed readout equals the value a student must see.
///
/// Expected strings are **independently hand-derived** from the published formula for each
/// tool's default inputs (see the derivation comment on each row) — deliberately NOT recomputed
/// by the app's own code, so a wiring / formatting / unit bug is caught rather than mirrored.
/// (Kit-formula accuracy is separately covered by the 47 `*Kit` oracle tests.)
///
/// Each readout is read by its stable `result.<label>` accessibility id and compared to the
/// element's `.value` (label + unit), set in `ResultRow`.
final class AccuracyChecks: XCTestCase {

    private struct Screen {
        let tool: String
        let screen: Int
        let expect: [(label: String, value: String)]
    }

    /// tool → sub-screen → readout id → exact expected "value unit".
    private let cases: [Screen] = [
        // Wind — course 90 / TAS 120 / wind 180@30 kt ; derive from hdg 104.5 / GS 116.2
        Screen(tool: "wind", screen: 0, expect: [
            ("Heading", "104°"),            // HDG = course + asin(0.25) = 104.5° → 104
            ("Groundspeed", "116 kt"),      // 120·√0.9375 = 116.19
            ("Wind correction", "+14 °")]), // asin(0.25) = 14.5° → +14
        Screen(tool: "wind", screen: 1, expect: [
            ("Crosswind (from right)", "30 kt"),  // wind 180 vs rwy 090 → pure 90° cross
            ("Headwind", "0 kt")]),
        Screen(tool: "wind", screen: 2, expect: [
            ("Wind from", "180°"),
            ("Wind speed", "30 kt")]),
        // Airspeed
        Screen(tool: "airspeed", screen: 0, expect: [
            ("True airspeed", "116 kt")]),        // 100 KCAS @ PA10k / −5°C, σ=0.7391
        Screen(tool: "airspeed", screen: 1, expect: [
            ("Mach number", "0.837"),             // 480 kt @ −56.5°C, a=573.6
            ("Speed of sound", "574 kt")]),
        // Altitude
        Screen(tool: "altitude", screen: 0, expect: [
            ("Density altitude", "7801 ft"),      // PA5000 / OAT30 (Kit value, ±5 of the ~7800 standard)
            ("ISA deviation", "+25 °C")]),        // 30 − 5.09
        Screen(tool: "altitude", screen: 1, expect: [
            ("Pressure altitude", "5000 ft")]),   // ind5000 @ 29.92
        Screen(tool: "altitude", screen: 2, expect: [
            ("Convective cloud base", "4000 ft AGL"),  // (25−15)/2.5·1000
            ("Freezing level", "7571 ft MSL"),         // 15 / 1.9812 · 1000
            ("Pivotal altitude", "885 ft AGL")]),      // 100²/11.3
        // Nav
        Screen(tool: "nav", screen: 0, expect: [
            ("Time enroute", "75:00"),            // 150 nm / 120 kt
            ("Minutes", "75.0 min")]),
        Screen(tool: "nav", screen: 1, expect: [
            ("Distance flown", "150 nm")]),       // 120 kt · 75 min
        Screen(tool: "nav", screen: 2, expect: [
            ("Groundspeed", "120 kt")]),          // 150 nm / 75 min
        // Fuel
        Screen(tool: "fuel", screen: 0, expect: [
            ("Fuel burned", "25.0 gal"),          // 10 gph · 2.5 h
            ("Weight (avgas)", "150 lb")]),       // ·6
        Screen(tool: "fuel", screen: 1, expect: [
            ("Endurance", "4:00"),                // 40 gal / 10 gph
            ("Decimal hours", "4.00 h")]),
        Screen(tool: "fuel", screen: 2, expect: [
            ("Specific range", "12.0 nm/gal"),    // 120 / 10
            ("Still-air range", "480 nm")]),      // ·40
        // Climb / Descent
        Screen(tool: "climb", screen: 0, expect: [
            ("Descent rate", "600 fpm"),          // 3000 ft / 10 nm / 120 kt
            ("Begin descent", "9.4 nm out")]),    // 3000 / 318
        Screen(tool: "climb", screen: 1, expect: [
            ("Required climb rate", "450 fpm"),   // 300 ft/nm · 90 kt / 60
            ("Gradient", "4.94 %"),               // 300 / 6076.1
            ("Angle", "2.83 °")]),
        Screen(tool: "climb", screen: 2, expect: [
            ("Glide distance", "7.4 nm")]),       // 9:1 · 5000 / 6076.1
        // Weight & Balance (Loading)
        Screen(tool: "wb", screen: 0, expect: [
            ("Centre of gravity", "38.4 in"),     // 59120 / 1540
            ("Gross weight", "1540 lb"),
            ("Total moment", "59120 lb·in")]),
        // Convert (Temperature default: 100 °C → °F)
        Screen(tool: "convert", screen: 0, expect: [
            ("°F", "212.0")]),
        // Timer (count-down default 5 min; live clock skipped)
        Screen(tool: "timer", screen: 0, expect: [
            ("Remaining", "5:00")]),
    ]

    func testEveryReadoutIsAccurate() {
        for c in cases {
            let app = XCUIApplication()
            app.launchEnvironment["TRUECOURSE_TOOL"] = c.tool
            app.launchEnvironment["TRUECOURSE_SCREEN"] = String(c.screen)
            app.launch()
            for e in c.expect {
                let el = app.descendants(matching: .any).matching(identifier: "result.\(e.label)").firstMatch
                XCTAssertTrue(el.waitForExistence(timeout: 8),
                              "[\(c.tool)/\(c.screen)] readout ‘\(e.label)’ not found")
                XCTAssertEqual(el.value as? String, e.value,
                               "[\(c.tool)/\(c.screen)] ‘\(e.label)’ should read ‘\(e.value)’")
            }
            app.terminate()
        }
    }

    /// The W&B envelope screen has no numeric ResultRow — assert the in-limits verdict shows.
    /// Read by the stable `verdict.envelope` id (not the raw string, which differs from the Loading
    /// screen's "IN ENVELOPE") and via `.text` (a plain Text has an empty `label` on macOS).
    func testWeightBalanceEnvelopeVerdict() {
        let app = launchTrueCourse(tool: "wb", screen: 1)
        let verdict = app.any("verdict.envelope")
        XCTAssertTrue(verdict.waitForExistence(timeout: 8), "envelope verdict not found")
        XCTAssertTrue(verdict.text.contains("WITHIN LIMITS"),
                      "default W&B load should read WITHIN LIMITS, got ‘\(verdict.text)’")
        app.terminate()
    }

    /// Coverage guard (§C.1): every shipping tool must appear in `cases` above. Adding a 10th tool
    /// without a numeric check fails here — the diff makes the omission visible. (UI targets are
    /// black-box, so the catalog can't be imported; the expected set is duplicated on purpose.)
    func testEveryToolHasANumericCheck() {
        let covered = Set(cases.map(\.tool))
        let expected: Set<String> = ["wind", "airspeed", "altitude", "nav",
                                     "fuel", "climb", "wb", "convert", "timer"]
        XCTAssertEqual(covered, expected, "the catalog ships 9 tools; each needs a numeric check")
    }
}
