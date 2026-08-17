import XCTest

/// The Mac's three additions (`1h`): drag-and-drop import, **Space** to hold the original, and
/// **⌘Z** to revert.
///
/// ⚠️ Written, not run — and on macOS a UI-test run seizes the whole screen, so this one needs the
/// owner's explicit go-ahead before it is ever invoked. See `../uitests.md` §3 for the
/// accessibility traps that turn an iOS-green suite red here.
#if os(macOS)
final class MacChecks: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testSpaceHoldsTheOriginalAndReleasingRestoresTheSplitExactly() {
        let app = XCUIApplication.launchedWithPhoto(enhancer: "fast")
        app.buttons["edit.enhance"].tap()
        expect(app.buttons["edit.save"], "the pass to land", timeout: 20)

        let canvas = app.descendants(matching: .any)["compare.canvas"]
        expect(canvas, "the comparison canvas")
        canvas.adjust(toNormalizedSliderPosition: 0.6)
        let before = canvas.value as? String

        // Key-down only, so the hold is genuinely held rather than tapped.
        XCUIElement.perform(withKeyModifiers: []) {
            app.typeKey(" ", modifierFlags: [])
        }
        // After a full press-and-release the value must be exactly what it was: the hold is
        // transient and must never move the handle.
        XCTAssertEqual(canvas.value as? String, before)
    }

    func testCommandZReverts() {
        let app = XCUIApplication.launchedWithPhoto(enhancer: "fast")
        app.buttons["edit.enhance"].tap()
        expect(app.buttons["edit.save"], "the pass to land", timeout: 20)

        app.typeKey("z", modifierFlags: .command)
        expect(app.buttons["edit.enhance"], "the Enhance capsule after ⌘Z")
    }

    func testTheSidebarLinksToTheRealFolderInFinder() {
        let app = XCUIApplication.launchedWithPhoto()
        let link = app.buttons["library.openInFinder"]
        expect(link, "the Open in Finder link")
        // Not tapped: opening Finder mid-suite steals focus and the next test starts against the
        // wrong frontmost app. Its presence and its wording are what matter.
        XCTAssertTrue(link.label.contains("Finder"), link.label)
    }

    func testTheWindowIsNotADocumentOpenPanel() {
        // 2.1(a): a SwiftUI `DocumentGroup` app opens on an empty Open panel on the Mac, which this
        // repository has already had rejected once. The app's own library is the document.
        let app = XCUIApplication.launchedEmpty()
        expect(app.buttons["import.library"], "the import screen, not an Open panel")
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }
}
#endif
