import XCTest

/// Cross-platform element reading, and one launcher every suite shares.
///
/// ## The trap the `text` accessor exists for
///
/// The same SwiftUI `Text` publishes its string in a DIFFERENT attribute depending on the platform,
/// so an iOS suite can be fully green while every macOS assertion that reads a number fails:
///
/// | element | iOS | macOS |
/// |---|---|---|
/// | plain `Text` leaf | `label` = "-2,586.01" | `label` = **""**, `value` = "-2,586.01" |
/// | `.accessibilityElement(children: .combine)` | `label` = combined | `label` = combined |
///
/// So `.label` works on macOS *only* for combined elements, and a failure prints an empty string —
/// which reads like "the screen never loaded" and sends you hunting a navigation bug that is not
/// there. Read through `text`, match with `textMatches`, and never touch `.label` directly.
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

/// An element by identifier, whatever TYPE SwiftUI published it as.
///
/// The type is not stable: it changes with modifiers *and* across platforms — a `.combine`d card is a
/// `staticText` on iOS and a `group` on macOS, and a `SettingCard`'s `Menu` is a `button` on iOS and a
/// `popUpButton` on macOS. `app.buttons["x"]` passing on iOS and failing on macOS is the single most
/// expensive trap in this suite, because the message is indistinguishable from a real rendering bug.
/// Query by identifier alone.
func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
}

/// Launch Par with the scaffolding every test needs.
///
/// The locale is pinned twice on purpose. `Fmt` (`Par/Views/DesignSystem/Fmt.swift`) builds a
/// `NumberFormatter` with no explicit locale, so it follows the device region: on a comma-decimal
/// simulator every number renders `-2 586,01` and each numeric check fails on the separator rather
/// than on the arithmetic. The dedicated sims have `AppleLocale` pinned in their
/// `.GlobalPreferences.plist` as well — belt and braces, because a fresh or re-created device loses
/// the plist edit and the launch arguments are the only thing that travels with the test.
func launchPar(tool: String? = nil, showsTape: Bool = false, seedTape: Bool = false)
    -> XCUIApplication {
    let app = XCUIApplication()
    if let tool { app.launchEnvironment["PAR_TOOL"] = tool }
    if showsTape { app.launchEnvironment["PAR_TAPE"] = "1" }
    // Default to an EMPTY tape: a seeded one puts four rows above the fold and makes "did this
    // append?" ambiguous. Only the reel wants the seeded version.
    app.launchEnvironment["PAR_TAPE_SEED"] = seedTape ? "1" : "0"
    app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    // Deliberately NOT calling `activate()` on macOS. It looks like the right thing — the window
    // reports `Disabled` in the accessibility tree until the app is frontmost — but measured on Par
    // it made things worse: without it nine of ten screens appended correctly, with it none did.
    // `launch()` already foregrounds the app, and forcing activation on top of that appears to leave
    // the first click being consumed as a window raise rather than a press.
    return app
}

extension XCUIElement {

    /// Whether this element currently holds keyboard focus.
    ///
    /// XCUITest exposes it only as an untyped attribute, and there is no cross-platform accessor.
    /// It matters because focus is not the same gesture everywhere: a `tap()` focuses a TextField on
    /// iOS but not on macOS, and an element below the fold takes no focus on either. Typing into an
    /// unfocused field throws "Neither element nor any descendant has keyboard focus", which reads
    /// like the field is missing when in fact it is simply not first responder.
    var hasFocus: Bool {
        (value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }
}

extension XCUIElement {

    /// Press this element, falling back to its centre coordinate when the framework calls it
    /// unhittable.
    ///
    /// On macOS an element inside a window the accessibility tree marks `Disabled` — which happens
    /// when the app is not frontmost, and `activate()` does not always cure it — reports
    /// `isHittable == false` even though its frame is correct and fully on screen. The failure reads
    /// "Element Button ... is not hittable", which looks like a layout bug and is not one: measured
    /// on Par, the button sat 25pt above the window's bottom edge, inside a window entirely within
    /// the display. A coordinate press goes to the point regardless, which is what a user's mouse
    /// does anyway.
    func press() {
        // `tap()` on both platforms when the framework says the element is hittable. This is not
        // interchangeable with `click()`: measured on Par, switching the macOS path to `click()`
        // turned nine passing screens into nine failures — the click was consumed without the
        // button's action running. `tap()` is what worked, and XCUITest maps it to a click on macOS
        // itself. Only the fallback needs a coordinate.
        if isHittable {
            tap()
            return
        }
        // Unhittable but on screen: an element inside a window the tree marks `Disabled` reports
        // false here even with a correct frame fully inside the display. A coordinate press goes to
        // the point regardless, which is what a mouse does anyway.
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
