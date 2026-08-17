import XCTest

/// Shared helpers, shaped entirely by `uitests.md` §3.
///
/// A suite that was 38/38 green on iPhone and iPad failed 15 of 39 on the Mac, every failure
/// printing an empty string. The five traps below are the reason, and every one of them is worked
/// around here rather than in each test.
enum UI {

    /// Query by identifier ALONE — never by element type.
    ///
    /// Trap 2, and the most expensive one in the doc: SwiftUI does not promise which XCUIElement
    /// type a view becomes, and it differs between platforms. `app.buttons["x"]` that resolves to
    /// an `otherElement` on macOS fails in a way indistinguishable from a real bug.
    static func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    static func exists(_ app: XCUIApplication, _ identifier: String, timeout: TimeInterval = 5) -> Bool {
        any(app, identifier).waitForExistence(timeout: timeout)
    }

    /// Scoped to `.staticText`, never `.any`.
    ///
    /// §9: a compound predicate over `descendants(matching: .any)` times out on macOS after about
    /// 135 seconds — which looks like a hang, not a failing assertion.
    static func text(_ app: XCUIApplication, containing needle: String) -> XCUIElement {
        app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", needle, needle)
        ).firstMatch
    }

    /// Launch with overrides. Every one goes through `LaunchOverride`, which compiles out of
    /// Release.
    static func launch(_ overrides: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ARCH_LANG"] = "en"
        for (key, value) in overrides { app.launchEnvironment[key] = value }
        app.launch()
        return app
    }
}

extension XCUIElement {
    /// Read a label, falling back to the value.
    ///
    /// Trap 3: on macOS a plain SwiftUI `Text` has an EMPTY `label` and its string lives in
    /// `value`. Nothing in this suite may touch `.label` directly —
    /// `grep -n '\.label' architectureUITests/*.swift` must return only comments.
    var text: String {
        let labelText = label
        if !labelText.isEmpty { return labelText }
        return (value as? String) ?? ""
    }

    /// Drag by coordinates.
    ///
    /// §6: a same-element drag needs coordinates; `press(forDuration:thenDragTo:)` between two
    /// points on ONE element is the only shape that works, and a drag that does one step and then
    /// dies means the view is swapping identity mid-gesture.
    func drag(fromRelativeX start: CGFloat, toRelativeX end: CGFloat) {
        let from = coordinate(withNormalizedOffset: CGVector(dx: start, dy: 0.5))
        let to = coordinate(withNormalizedOffset: CGVector(dx: end, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: to)
    }
}
