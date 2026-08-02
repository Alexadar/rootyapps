import XCTest

/// Cross-platform element reading.
///
/// ## The trap this exists for
///
/// The same SwiftUI `Text` publishes its string in a DIFFERENT attribute depending on the platform,
/// and the iOS suite can be fully green while the macOS suite fails on every assertion that reads
/// a number. Measured from `app.debugDescription` on both:
///
/// | element | iOS | macOS |
/// |---|---|---|
/// | plain `Text` leaf | `label` = "12' 6-1/2\"" | `label` = **""**, `value` = "12' 6-1/2\"" |
/// | `.accessibilityElement(children: .combine)` | `label` = combined | `label` = combined |
///
/// So `element.label` works on macOS *only* for combined elements. Every test that read a plain
/// `Text` compared against `""` and failed with a message that printed nothing — which reads like
/// "the screen is empty" and sends you hunting for a navigation bug that isn't there.
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
