import XCTest

/// The plain launch a first-time user performs — no deep link, no capture flags, nothing seeded.
///
/// ## Why this suite exists
///
/// App Review rejected 1.0.1 build 5 under Guideline 2.1(a): "the app failed to launch any main
/// window or menu bar extra app" (MacBook Air M3, macOS 26.6). It was not a crash and not a layout
/// bug. SwiftUI's `DocumentGroup` opens a Mac app on an *Open panel* rather than a document, so a
/// reviewer with no `.partape` files on disk got an empty file chooser and, once they dismissed it,
/// a running app with nothing on screen.
///
/// The whole UI suite missed it because every run forced `-configuration Capture`, which compiles
/// `WindowGroup` in place of `DocumentGroup`. The tests exercised a scene the store build does not
/// contain.
///
/// ## What this file can and cannot cover
///
/// Only the iOS half of that is testable here. On macOS, XCUITest reports **no window at all** for
/// this app whether the bug is present or not — measured against both a fixed and a rejected build
/// while diagnosing it. The framework's launch path does not reproduce a user launch for a
/// sandboxed `DocumentGroup` app, so any assertion would fail identically on a good build and a bad
/// one. `scripts/verify_mac_launch.sh` is the real macOS guard: it launches a **signed** build
/// through **LaunchServices** and inspects the window list, and it is negatively verified — it
/// fails on the rejected build and passes on the fixed one.
///
/// Every other test here launches through `launchPar(...)`, which sets `PAR_TOOL` and friends.
/// This one must not: those flags are precisely what a store launch lacks.
final class LaunchTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// A bare launch must put something usable on screen, with no help from launch arguments.
    ///
    /// The bar is deliberately different per platform, because the correct behaviour is different.
    /// On iOS the document browser *is* the expected first run — a full-screen system UI the user
    /// can act on, and it passed review. On the Mac the equivalent is an Open panel floating over
    /// nothing, which is what was rejected.
    func testBareLaunchShowsAMainWindow() throws {
        #if os(macOS)
        throw XCTSkip(
            "macOS launch behaviour is covered by scripts/verify_mac_launch.sh — XCUITest cannot "
            + "distinguish a good launch from the 2.1(a) failure for a sandboxed DocumentGroup app"
        )
        #else
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 30),
            "the app did not reach the foreground on a plain launch"
        )

        // The document browser is the expected entry point here, so the assertion is only that
        // something was actually presented — a blank window would still be a launch failure.
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30), "no window after a plain launch")
        XCTAssertGreaterThan(window.frame.height, 0, "launch window has no height")
        #endif
    }
}
