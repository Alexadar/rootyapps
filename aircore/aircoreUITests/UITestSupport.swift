import XCTest

// Shared helpers for the whole UI suite. Everything here exists because of a measured
// cross-platform trap, not for tidiness — see uitests.md §3 and each doc comment below.

/// Cross-platform element reading.
///
/// ## The trap this exists for
///
/// The same SwiftUI `Text` publishes its string in a DIFFERENT attribute depending on the platform,
/// so an iOS suite can be fully green while macOS fails on every assertion that reads a number:
///
/// | element | iOS | macOS |
/// |---|---|---|
/// | plain `Text` leaf | `label` = `62.5` | `label` = **`""`**, `value` = `62.5` |
/// | `.accessibilityElement(children: .combine)` | `label` = combined | `label` = combined |
///
/// So `.label` works on macOS *only* for combined elements. Every test that reads a plain `Text`
/// would compare against `""` and fail with a message printing nothing — which reads like "the
/// screen is empty" and sends you hunting a navigation bug that is not there.
///
/// Always read through `text`. Never `.label` directly.
extension XCUIElement {
    var text: String {
        let label = self.label
        if !label.isEmpty { return label }
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

    /// Find an element by identifier, **whatever type it turned out to be**.
    ///
    /// SwiftUI decides whether a styled card surfaces as `otherElement`, `staticText` or a group,
    /// it changes with modifiers, and it differs per platform. Querying `app.otherElements[id]`
    /// therefore finds a result on iOS and nothing on macOS — a failure indistinguishable from the
    /// screen not rendering. Never hard-code the type.
    func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Tap the first *hittable* element with this identifier.
    ///
    /// A SwiftUI `Label` publishes its identifier on both the icon and the text, and `firstMatch`
    /// returns the icon — which lies inside the row but is not itself hittable, so the tap fails
    /// with "Failed to not hittable". This cost three iPad tests that silently asserted against
    /// whatever screen was already showing.
    func tap(_ app: XCUIApplication, _ identifier: String) {
        let candidates = app.descendants(matching: .any).matching(identifier: identifier)
        let target = candidates.allElementsBoundByIndex.first { $0.isHittable }
            ?? candidates.firstMatch
        target.tap()
    }

    /// Launch with the hooks the UI suite and the capture pipeline share.
    ///
    /// `reset` is on by default: a test that inherits the previous test's persisted state passes
    /// for the wrong reason, and once failed for one. The persistence tests are the deliberate
    /// exception and pass `reset: false` on their second launch.
    ///
    /// Every hook goes through `LaunchOverride`, which is compiled out of Release — see
    /// uitests.md §4b.
    @discardableResult
    func launchApp(tool: String? = nil, reset: Bool = true,
                   contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [:]
        if let tool { app.launchEnvironment["AIRCORE_TOOL"] = tool }
        if reset { app.launchEnvironment["AIRCORE_RESET"] = "1" }
        if let contentSize {
            app.launchArguments = ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        #if os(macOS)
        // Start from a clean window frame. macOS restores the last saved one, so a window a
        // previous run left at 900×450 comes back at 900×450 — small enough that the split layout
        // collapses and elements fall outside the window, where they are not published to the
        // accessibility tree at all. The suite would then be testing a layout no user chose.
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        #endif
        app.launch()
        return app
    }

    /// Assert an identified element shows `needle`, in **either** accessibility attribute.
    ///
    /// A result tile carries its name in `label` and its number in `value`, so a check that reads
    /// only one of them tests the wrong half. Both are searched.
    func assertShows(_ app: XCUIApplication, _ identifier: String, _ needle: String,
                     timeout: TimeInterval = 10,
                     file: StaticString = #filePath, line: UInt = #line) {
        let element = any(app, identifier)
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "\(identifier) never appeared", file: file, line: line)
        let shown = element.label + " " + ((element.value as? String) ?? "")
        XCTAssertTrue(shown.contains(needle),
                      "\(identifier) shows \"\(shown)\", expected to contain \"\(needle)\"",
                      file: file, line: line)
    }

    /// Assert an identified element shows a number, **whatever the device's locale does to it**.
    ///
    /// The app formats through `FormatStyle`, so on a French simulator 26,507 renders as
    /// `26 507` with a non-breaking space, and 62.6 as `62,6`. The dedicated `AIRC-*` sims are
    /// pinned to `en_US` for exactly this reason — but a suite that only passes on a pinned sim is
    /// a suite that fails mysteriously the first time someone runs it elsewhere, so the comparison
    /// normalises instead of trusting the pin.
    func assertShowsNumber(_ app: XCUIApplication, _ identifier: String, _ expected: String,
                           timeout: TimeInterval = 10,
                           file: StaticString = #filePath, line: UInt = #line) {
        let element = any(app, identifier)
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "\(identifier) never appeared", file: file, line: line)
        let shown = element.label + " " + ((element.value as? String) ?? "")
        XCTAssertTrue(shown.normalisedDigits.contains(expected.normalisedDigits),
                      "\(identifier) shows \"\(shown)\", expected the number \"\(expected)\"",
                      file: file, line: line)
    }

    // MARK: - Navigation helpers

    /// Open a tool without the deep link — the path a user actually takes.
    ///
    /// Compact width shows a catalogue of cards; regular width shows a sidebar whose rows are
    /// static text inside a cell, not buttons.
    func navigateToTool(_ app: XCUIApplication, _ tool: String) {
        if any(app, "tool.\(tool)").waitForExistence(timeout: 10) {
            tap(app, "tool.\(tool)")
            return
        }
        XCTAssertTrue(any(app, "sidebar.\(tool)").waitForExistence(timeout: 5),
                      "could not find \(tool) in the catalogue or the sidebar")
        tap(app, "sidebar.\(tool)")
    }
    /// A cheap fingerprint of what an identified element is currently showing.
    ///
    /// Includes the element **itself**, not only its descendants. A result tile is
    /// `.accessibilityElement(children: .ignore)`, so on macOS it is a leaf with no descendants at
    /// all and a descendants-only fingerprint is the empty string — for both the before and the
    /// after, which makes "did this change?" assertions pass or fail on nothing. iOS happened to
    /// expose children, which hid it.
    func signature(_ app: XCUIApplication, _ identifier: String) -> String {
        let element = any(app, identifier)
        // `label` on an element that does not exist raises "No matches found for first query"
        // rather than returning empty — so absence has to be checked, not assumed.
        guard element.exists else { return "" }
        let own = element.label + (element.value as? String ?? "")
        let children = element.descendants(matching: .any)
            .allElementsBoundByIndex
            .map { $0.label + (($0.value as? String) ?? "") }
            .joined(separator: "|")
        return own + "|" + children
    }
}

extension String {
    /// Just the digits, in order.
    ///
    /// Locales disagree about both separators and swap their meanings: `26,507` is twenty-six
    /// thousand in en_US and twenty-six-point-five in fr_FR, so no substitution rule can normalise
    /// them into each other. Dropping every separator sidesteps the ambiguity — `26,507`,
    /// `26 507` and `26507` all become `26507`, and `62.6` and `62,6` both become `626`.
    ///
    /// The cost is that the decimal point's position is no longer checked. That is acceptable
    /// here: these assertions guard against a *different number* reaching the label, and the Kit
    /// suites already pin the value itself against a cited source to five figures.
    var normalisedDigits: String {
        String(unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
            .map(Character.init))
    }
}

extension XCUIElement {

    /// Clear the field and type something else. `typeText` alone appends.
    func replaceText(with text: String) {
        #if os(macOS)
        typeKey("a", modifierFlags: .command)
        #else
        if let existing = value as? String, !existing.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 2))
        }
        #endif
        typeText(text)
    }

    /// What a **text field** contains.
    ///
    /// Not `text`: a field publishes its name in `label` and its contents in `value`, so the
    /// label-first helper returns "Dry bulb" no matter what is typed. That cost a persistence test
    /// that looked like a broken save and was a broken assertion.
    var fieldValue: String { (value as? String) ?? "" }

    /// Wait for the field's contents to contain a substring — an edit commits a frame or two after
    /// the keystroke, and asserting immediately reads the old value.
    func waitForText(containing needle: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if fieldValue.contains(needle) || text.contains(needle) { return true }
            usleep(100_000)
        } while Date() < deadline
        return false
    }
}
