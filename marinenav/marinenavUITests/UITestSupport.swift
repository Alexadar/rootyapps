import XCTest

/// Cross-platform element reading and querying.
///
/// ## The traps this exists for
///
/// **1. The same `Text` publishes its string in a DIFFERENT attribute per platform.** The iOS suite
/// can be fully green while macOS fails every assertion that reads a number:
///
/// | element | iOS | macOS |
/// |---|---|---|
/// | plain `Text` leaf | `label` = "4.58 ft" | `label` = **""**, `value` = "4.58 ft" |
/// | `.accessibilityElement(children: .combine)` | `label` = combined | `label` = combined |
///
/// So `.label` works on macOS *only* for combined elements. Every test that reads a plain `Text`
/// would compare against `""` and fail printing nothing — which reads like "the screen is empty"
/// and sends you hunting a navigation bug that does not exist.
///
/// **2. The element TYPE changes with modifiers and per platform.** A `.combine`d card is a
/// `staticText` on iOS and a `group` on macOS, so `app.buttons["x"]` can pass on iOS and fail on
/// macOS with a message indistinguishable from a real rendering bug. Query by identifier ALONE.
extension XCUIElement {

    /// The string a user would read, whichever attribute this platform chose to put it in.
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

/// An element by identifier, whatever TYPE SwiftUI published it as on this platform.
///
/// This is the type-agnostic form every result, card and catalog row must be queried with. The
/// previous suite used `app.buttons["tool.tides"]`, which only ever ran on iOS — the UI-test target
/// was not wired for macOS, so the latent failure could not surface.
func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
}

/// The catalog row for a tool, type-agnostically.
func toolRow(_ app: XCUIApplication, _ tool: String) -> XCUIElement {
    any(app, "tool.\(tool)")
}

/// An element whose visible text contains `needle`, searched over TEXT elements only.
///
/// ⚠ Do NOT write `app.descendants(matching: .any).matching(textMatches(needle))`. That walks
/// every element in the tree evaluating a compound `label OR value` predicate, and on macOS it
/// does not merely run slowly — it fails outright:
///
///     Failed to get matching snapshots: Timed out while evaluating UI query.
///
/// after burning 135 s. Matching by IDENTIFIER stays cheap on both platforms (all of
/// `CalculationChecks` passes), so the cost is specific to predicate-over-everything. Scoping the
/// search to `.staticText` is both cheaper and what was actually meant: a visible label.
func textElement(_ app: XCUIApplication, _ needle: String) -> XCUIElement {
    app.descendants(matching: .staticText).matching(textMatches(needle)).firstMatch
}

/// A launch with the locale pinned, so a sim that booted in a comma-decimal region cannot fail a
/// test on the separator rather than the arithmetic. Belt and braces alongside the sim's
/// `AppleLocale` — see §C.4 of the rollout prompt.
extension XCUIApplication {
    func launchPinned(_ extraArguments: [String] = []) {
        launchArguments += extraArguments
        launchEnvironment["MARINENAV_LANG"] = "en"
        launch()
    }
}
