import XCTest

// Cross-platform element reading + a single launch path. Ported from
// storypole/storypoleUITests/UITestSupport.swift.
//
// The traps this exists for (all macOS-only, all print an EMPTY string so they read like "the
// screen never loaded"):
//  • A plain SwiftUI `Text` has an EMPTY `label` on macOS; its string is in `value`. → read `.text`.
//  • Element TYPE differs per platform: a `.combine`d card is a `staticText` on iOS and a `group`
//    on macOS. → never `app.staticTexts[...]`/`otherElements[...]`; query by identifier via `any`.
//  • `NSPredicate(format: "label CONTAINS %@")` silently matches nothing on macOS. → `textMatches`.

extension XCUIElement {
    /// The string a user would read, whichever attribute this platform chose to put it in.
    var text: String {
        let l = label
        if !l.isEmpty { return l }
        return (value as? String) ?? ""
    }
}

/// A predicate matching `needle` in EITHER attribute.
func textMatches(_ needle: String) -> NSPredicate {
    NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", needle, needle)
}

extension XCUIApplication {
    /// An element by identifier, whatever TYPE SwiftUI published it as (it differs per platform).
    func any(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }
    /// The `result.<label>` readout (ResultRow publishes "label" + unit as `.value`).
    func result(_ label: String) -> XCUIElement { any("result.\(label)") }
    /// The `field.<title>` input.
    func field(_ title: String) -> XCUIElement { any("field.\(title)") }
}

/// The single launch path for every test: seed the launch-time deep links and pin the locale.
///
/// These are US-market apps; formatting follows the device region, so on a comma-decimal simulator
/// every number renders "152,11" and tests fail on the separator, not the arithmetic. The real pin
/// is the sim's `AppleLocale en_US` (set once at sim creation, never `simctl erase`d); `TRUECOURSE_LANG`
/// is belt-and-braces. All three hooks are honoured only in DEBUG (see LaunchOverride).
@discardableResult
func launchTrueCourse(tool: String? = nil, screen: Int? = nil, demo: Bool = false) -> XCUIApplication {
    let app = XCUIApplication()
    if let tool   { app.launchEnvironment["TRUECOURSE_TOOL"] = tool }
    if let screen { app.launchEnvironment["TRUECOURSE_SCREEN"] = String(screen) }
    if demo       { app.launchEnvironment["TRUECOURSE_DEMO"] = "1" }
    app.launchEnvironment["TRUECOURSE_LANG"] = "en"
    app.launch()
    return app
}
