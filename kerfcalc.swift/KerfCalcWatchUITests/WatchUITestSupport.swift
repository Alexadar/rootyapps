import XCTest

/// Shared helpers for the watch suite.
///
/// Deliberately a near-copy of `kerfcalcUITests/UITestSupport.swift` rather than a shared file: a
/// watchOS test bundle and an iOS one cannot be in the same target, and the crown helpers below have no
/// meaning on the phone. The parts that ARE identical (`text`, `any`, `assertShows`) are identical on
/// purpose — the same trap applies, and a divergent spelling would hide it on one platform.
extension XCUIElement {

    /// The string a user would read, whichever attribute this platform put it in. A plain SwiftUI
    /// `Text` leaf reports an EMPTY `label` and carries its string in `value`, so `.label` alone
    /// compares against `""` and fails with a message that prints nothing.
    var text: String {
        let l = label
        if !l.isEmpty { return l }
        return (value as? String) ?? ""
    }

    /// The NUMBER on a readout that publishes a label *and* a value.
    ///
    /// **This is the inverse preference of `text`, and every watch readout needs it.**
    /// `WatchHero`, `WatchRow` and `CrownField` all `.combine` their children and then set
    /// `accessibilityLabel` to the quantity's *name* and `accessibilityValue` to the figure. So `label`
    /// is `"TONNAGE"` / `"AREA"` / `"RUN"` — a constant — and reading it asserts against the caption,
    /// which passes no matter what the maths or the crown did.
    ///
    /// Measured, not assumed: the first run of `CrownFocusChecks` failed 11 tests with
    /// `("TONNAGE") is equal to ("TONNAGE")`. The crown was working the whole time; the helper was
    /// reading the label. Same shape as `overtonelab`'s `readoutValue`.
    var readoutValue: String {
        if let v = value as? String, !v.isEmpty { return v }
        return label
    }
}

extension XCTestCase {

    /// Launch the watch app, optionally deep-linked to a tool via `KERFCALC_TOOL`.
    func launchWatch(tool: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let tool { app.launchEnvironment["KERFCALC_TOOL"] = tool }
        app.launchEnvironment["KERFCALC_LANG"] = "en"
        app.launch()
        return app
    }

    /// An element by identifier, whatever TYPE SwiftUI published it as. `StackedReadout` is
    /// `.combine`d, so it is a `staticText` on one platform and a group on another — querying a
    /// concrete type is the trap that passes here and fails elsewhere.
    func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The figure shown by the element with this identifier.
    ///
    /// `readoutValue`, never `text`: everything this suite queries is a combined readout with an
    /// explicit `accessibilityLabel`, so `text` would return the caption and every assertion would
    /// pass vacuously.
    func value(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 10,
               file: StaticString = #filePath, line: UInt = #line) -> String {
        let e = any(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout),
                      "no element with identifier '\(id)'", file: file, line: line)
        return e.readoutValue
    }

    func assertShows(_ app: XCUIApplication, _ id: String, _ needle: String,
                     file: StaticString = #filePath, line: UInt = #line) {
        let got = value(app, id, file: file, line: line)
        XCTAssertTrue(got.contains(needle),
                      "\(id): expected to contain «\(needle)», got «\(got)»", file: file, line: line)
    }

    func tapId(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 10,
               file: StaticString = #filePath, line: UInt = #line) {
        let e = any(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout),
                      "no element with identifier '\(id)' to tap", file: file, line: line)
        e.tap()
    }

    // MARK: - The crown

    /// Turn the Digital Crown.
    ///
    /// `rotateDigitalCrown(delta:)` is watchOS-only (`XCUIAutomation`'s `XCUIDevice.h`, gated on
    /// `TARGET_OS_WATCH`, since Xcode 13). `delta` is in **revolutions**, not detents, so the value a
    /// field lands on depends on its own `step` and `sensitivity` — which is why every assertion below
    /// checks that the value CHANGED, never that it reached a specific number. Pinning a number here
    /// would be asserting the framework's detent maths, not the app's.
    ///
    /// ## Why 5 and not something small
    ///
    /// **A sub-detent rotation moves nothing, and repeating it does not accumulate** — each call is a
    /// discrete gesture. This suite originally used `0.6`, which is less than one detent for a coarse
    /// field like Estimate's area (`step: 25` over `0...100000`), so that screen read as a completely
    /// dead crown through six retries while the crown was working: measured, `delta: 1.0` moved it
    /// 1000 → 1025 immediately. Two "defects" on Estimate and Pavers were this and nothing else.
    ///
    /// `1.0` is the smallest value measured to clear one detent on **both** extremes of this app's
    /// fields — Estimate's coarse `step: 25` over `0...100000` (1000 → 1025) and Mortar's `step: 5`
    /// (100 → 155). `overtonelab` uses `5`, which is fine for its ranges but **saturates** ours: five
    /// revolutions drove Pavers' area (`step: 5`, max `20000`) to its ceiling, and once a crown-driven
    /// value saturates, watchOS passes the rotation on to the enclosing `ScrollView` — which scrolled
    /// the field off screen and out of the accessibility tree, reading as "no element".
    func turnCrown(_ delta: CGFloat = 1.0) {
        XCUIDevice.shared.rotateDigitalCrown(delta: delta)
    }

    /// Rotate, then wait for the value at `id` to stop matching `previous`.
    ///
    /// Returns the new value, or `previous` if nothing moved. A poll rather than a fixed sleep: the
    /// crown drives a `@State` through a binding, so the readout updates a frame or two later.
    func turnCrownAndRead(_ app: XCUIApplication, _ id: String, from previous: String,
                          delta: CGFloat = 1.0, attempts: Int = 3) -> String {
        for _ in 0..<attempts {
            turnCrown(delta)
            let now = value(app, id)
            if now != previous { return now }
        }
        return value(app, id)
    }
}
