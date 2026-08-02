import XCTest

/// Cross-platform element reading, compiled into BOTH the phone/Mac suite and the watch suite.
///
/// ## The trap this exists for
///
/// The same SwiftUI `Text` publishes its string in a DIFFERENT attribute depending on the platform,
/// so an iOS suite can be entirely green while every macOS assertion that reads a number fails:
///
/// | element | iOS | macOS |
/// |---|---|---|
/// | plain `Text` leaf | `label` = `500.00 ms` | `label` = **`""`**, `value` = `500.00 ms` |
/// | `.accessibilityElement(children: .combine)` | `label` = combined | `label` = combined |
///
/// So `.label` works on macOS *only* for combined elements. A test reading `.label` compares against
/// `""` and fails printing nothing — which reads like "the screen never loaded" and sends you hunting
/// a navigation bug that does not exist.
///
/// Always read through `text`, match with `textMatches`, and address elements with `any(_:_:)`.
extension XCUIElement {

    /// The string a user would read, whichever attribute this platform chose to put it in.
    var text: String {
        let l = label
        if !l.isEmpty { return l }
        return (value as? String) ?? ""
    }

    /// The NUMBER on a readout that publishes a label *and* a value — the watch's `StackedReadout`,
    /// which combines its children and then sets `accessibilityLabel` to the quantity's name and
    /// `accessibilityValue` to the figure.
    ///
    /// Deliberately the inverse preference of `text`: there the label is the string a user reads,
    /// here the label is "RT60 (Sabine)" and the number lives in `value`, so preferring `label`
    /// would assert against the caption and pass no matter what the maths did.
    var readoutValue: String {
        if let v = value as? String, !v.isEmpty { return v }
        return label
    }
}

/// A predicate matching `needle` in EITHER attribute.
///
/// `NSPredicate(format: "label CONTAINS[c] %@")` silently matches nothing on macOS for plain text.
func textMatches(_ needle: String) -> NSPredicate {
    NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", needle, needle)
}

/// An element by identifier, whatever TYPE SwiftUI published it as.
///
/// Never `app.staticTexts["x"]` or `app.otherElements["x"]`: the published type changes with
/// modifiers *and* per platform — a `.combine`d card is a `staticText` on iOS and a group on macOS.
/// That mismatch passes on iOS and fails on macOS with a message indistinguishable from a genuine
/// rendering bug, which is the most expensive trap in this repo.
func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
}
