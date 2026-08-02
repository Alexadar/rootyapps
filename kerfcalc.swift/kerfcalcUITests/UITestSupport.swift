import XCTest

// Shared helpers for the whole UI suite. Everything here exists because of a measured
// cross-platform trap, not for tidiness — see each doc comment.

/// Cross-platform element reading.
///
/// ## The trap this exists for
///
/// The same SwiftUI `Text` publishes its string in a DIFFERENT attribute depending on the platform,
/// so an iOS suite can be fully green while the macOS suite fails on every assertion that reads a
/// number. Measured from `app.debugDescription` on both:
///
/// | element | iOS | macOS |
/// |---|---|---|
/// | plain `Text` leaf | `label` = `12' 6-1/2"` | `label` = **`""`**, `value` = `12' 6-1/2"` |
/// | `.accessibilityElement(children: .combine)` | `label` = combined | `label` = combined |
///
/// So `.label` works on macOS *only* for combined elements. Every test that read a plain `Text`
/// compared against `""` and failed with a message that printed nothing — which reads like "the
/// screen is empty" and sends you hunting a navigation bug that isn't there.
///
/// Always read through `text`. Never `.label` directly.
extension XCUIElement {
    var text: String {
        let l = label
        if !l.isEmpty { return l }
        return (value as? String) ?? ""
    }
}

/// A predicate matching `needle` in EITHER attribute.
///
/// `NSPredicate(format: "label CONTAINS[c] %@")` silently matches nothing on macOS for plain text.
func textMatches(_ needle: String) -> NSPredicate {
    NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", needle, needle)
}

extension XCTestCase {

    /// Launch with the deep-link hooks the capture pipeline also uses.
    ///
    /// The locale is pinned because these are US-market apps: on a comma-decimal simulator every
    /// formatted number renders `152,11` and the tests fail on the separator rather than on the
    /// arithmetic. The dedicated `KC-iPhone` / `KC-iPad` sims are pinned to `en_US` as well — this is
    /// the belt to that braces, and it is the only guarantee if someone runs the suite elsewhere.
    func launchApp(tool: String? = nil, tab: String? = nil, screen: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let tool { app.launchEnvironment["KERFCALC_TOOL"] = tool }
        if let tab { app.launchEnvironment["KERFCALC_TAB"] = tab }
        if let screen { app.launchEnvironment["KERFCALC_SCREEN"] = screen }
        app.launchEnvironment["KERFCALC_LANG"] = "en"
        app.launch()
        return app
    }

    /// An element by identifier, whatever TYPE SwiftUI published it as.
    ///
    /// **Never** `app.staticTexts["x"]` or `app.otherElements["x"]` for a result or a card: the type
    /// changes with modifiers *and* per platform — a `.combine`d card is a `staticText` on iOS and a
    /// group on macOS. That mismatch passes on iOS and fails on macOS with a message identical to a
    /// real rendering bug, which makes it the most expensive trap in this suite.
    func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The string shown by the element with this identifier.
    func value(_ app: XCUIApplication, _ id: String,
               timeout: TimeInterval = 10,
               file: StaticString = #filePath, line: UInt = #line) -> String {
        let e = any(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout),
                      "no element with identifier '\(id)'", file: file, line: line)
        return e.text
    }

    /// Assert the element with `id` contains `needle`.
    ///
    /// A `contains` on a substring, never `==` on a whole formatted string: the readout carries units
    /// and separators that are not what the test is about, and pinning them makes the test fail on a
    /// label tweak rather than on the number.
    func assertShows(_ app: XCUIApplication, _ id: String, _ needle: String,
                     file: StaticString = #filePath, line: UInt = #line) {
        let got = value(app, id, file: file, line: line)
        XCTAssertTrue(got.contains(needle),
                      "\(id): expected to contain «\(needle)», got «\(got)»", file: file, line: line)
    }

    /// Tap the element with this identifier.
    func tapId(_ app: XCUIApplication, _ id: String,
               timeout: TimeInterval = 10,
               file: StaticString = #filePath, line: UInt = #line) {
        let e = any(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout),
                      "no element with identifier '\(id)' to tap", file: file, line: line)
        XCTAssertTrue(e.isEnabled, "'\(id)' is disabled", file: file, line: line)
        e.tap()
    }

    /// Type a measurement on a keypad: `enter(app, feet: 12, inches: 4, num: 1, den: 2)` → 12' 4-1/2".
    ///
    /// `pad` selects which keypad — `key.` is the Spec tab's, `fkey.` the field sheet's. They share
    /// labels and `=` means different things on each (evaluate vs commit-and-dismiss), which is why
    /// the identifiers are namespaced rather than matched by glyph. Matching by glyph was also simply
    /// fragile: the minus key is U+2212 MINUS SIGN and the fraction key U+2044 FRACTION SLASH.
    func enter(_ app: XCUIApplication, pad: String = "key.",
               feet: Int? = nil, inches: Int? = nil, num: Int? = nil, den: Int? = nil,
               file: StaticString = #filePath, line: UInt = #line) {
        func k(_ suffix: String) { tapId(app, pad + suffix, file: file, line: line) }
        if let feet { String(feet).forEach { k("digit\($0)") }; k("feet") }
        if let inches { String(inches).forEach { k("digit\($0)") }; k("inch") }
        if let num, let den {
            String(num).forEach { k("digit\($0)") }
            k("fraction")                                   // numerator FIRST
            String(den).forEach { k("digit\($0)") }
        }
    }

    /// A bare number — no Feet/Inch tag, so the engine treats it as a scalar multiplier.
    func enterScalar(_ app: XCUIApplication, _ n: Int, pad: String = "key.",
                     file: StaticString = #filePath, line: UInt = #line) {
        String(n).forEach { tapId(app, pad + "digit\($0)", file: file, line: line) }
    }

    /// Switch surface. Works on both size classes: compact has a tab bar, regular a 78 pt rail.
    func surface(_ app: XCUIApplication, _ label: String) {
        let tab = app.tabBars.buttons[label].firstMatch
        if tab.waitForExistence(timeout: 2) { tab.tap(); return }
        let rail = app.buttons[label].firstMatch
        if rail.waitForExistence(timeout: 2) { rail.tap() }
    }

    /// Print the whole accessibility tree. When a query fails, DUMP — do not guess: one dump costs
    /// less than two wrong hypotheses, and it prints the real identifier and type of everything.
    func dump(_ app: XCUIApplication) { print(app.debugDescription) }
}
