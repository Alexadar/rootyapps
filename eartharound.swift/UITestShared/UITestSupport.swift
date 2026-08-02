import XCTest

// Compiled into BOTH UI-test targets (iOS and watchOS) from one place.
// Duplicating these helpers per target is how the same font bug shipped three times in
// this repo — each renderer had its own private copy. One copy, two targets.

/// Cross-platform element reading.
///
/// ## The trap this exists for
///
/// The same SwiftUI `Text` publishes its string in a DIFFERENT attribute depending on the platform,
/// and an iOS suite can be fully green while macOS fails on every assertion that reads a number:
///
/// | element | iOS | macOS |
/// |---|---|---|
/// | plain `Text` leaf | `label` = "5.3" | `label` = **""**, `value` = "5.3" |
/// | `.accessibilityElement(children: .combine)` | `label` = combined | `label` = combined |
///
/// So `element.label` works on macOS *only* for combined elements. Every test that read a plain
/// `Text` would compare against `""` and fail with a message printing nothing — which reads like
/// "the screen is empty" and sends you hunting a navigation bug that isn't there.
///
/// Always read through `text` (or match with `textMatches`). Never `.label` directly.
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

extension XCUIApplication {

    /// An element by identifier, whatever TYPE SwiftUI decided to publish it as.
    ///
    /// Never assume `staticTexts` or `otherElements`: a `.combine`d card is a static text on iOS and
    /// a group on macOS, so `app.otherElements["x"]` passes on iOS and fails on macOS with a message
    /// indistinguishable from a real rendering bug. Querying `descendants(matching: .any)` asserts
    /// the thing that actually matters — the identifier is reachable.
    ///
    /// Lives here rather than private to one test class, so both suites share one copy.
    func any(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }
}
