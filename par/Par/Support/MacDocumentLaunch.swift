#if os(macOS) && !PAR_CAPTURE
import AppKit

/// Makes a `DocumentGroup` app open a tape on launch instead of an Open panel.
///
/// ## The rejection this exists to prevent
///
/// App Review rejected 1.0.1 build 5 under Guideline 2.1(a): "the app failed to launch any main
/// window or menu bar extra app" (MacBook Air M3, macOS 26.6). It was not a crash. Measured on a
/// fresh launch of the Release binary, `CGWindowListCopyWindowInfo` reported exactly one window
/// owned by Par: a 917x448 panel titled "Open". On a reviewer's machine there are no `.partape`
/// files to list, so the panel is empty, and cancelling it leaves a running app showing nothing.
///
/// Reproducing it takes two conditions that are easy to get wrong, and getting either wrong gives a
/// confident wrong answer: the build must be **signed** (with `CODE_SIGNING_ALLOWED=NO` the sandbox
/// is not enforced and launch behaves differently), and it must be launched through
/// **LaunchServices** (`open -n`). Exec'ing `Par.app/Contents/MacOS/Par` directly reports zero
/// windows for a sandboxed app whether it is healthy or not. `scripts/verify_mac_launch.sh` encodes
/// both.
///
/// This is SwiftUI's default macOS behaviour for `DocumentGroup`, not a bug in the tape code —
/// AppKit's own document apps open an untitled document at launch, and SwiftUI does not. It was
/// invisible to the whole test suite because every UI run forces `-configuration Capture`, which
/// compiles `WindowGroup` instead and never reaches this path. Hence `!PAR_CAPTURE` above: under a
/// capture build there is no document controller to drive and the scene is already a window.
///
/// ## Why `applicationShouldOpenUntitledFile` and not `newDocument(_:)` in `didFinishLaunching`
///
/// Returning `true` here is the documented hook AppKit consults *before* deciding to show the Open
/// panel, and it is asked only when the launch carries no document. Calling `newDocument(nil)` from
/// `applicationDidFinishLaunching` instead would race that decision: opening Par by double-clicking
/// a `.partape` file would get the user's tape *and* a spurious untitled one. The `documents`
/// guard below is belt-and-braces for the reopen path, where AppKit asks the same question after a
/// dock click and a document may already be on screen.
final class MacDocumentLaunchDelegate: NSObject, NSApplicationDelegate {

    /// Turns off AppKit's "app-centric open panel", which is what puts the panel on screen in place
    /// of a document.
    ///
    /// Must be called from `ParApp.init()`. AppKit reads this default while deciding what to do with
    /// a bare launch, and that decision is already made by `applicationDidFinishLaunching` —
    /// measured, the panel was on screen and `NSApp.windows.count == 1` by the time the delegate
    /// first heard anything. `register(defaults:)` writes to the volatile registration domain, so it
    /// sets the fallback without persisting anything and without overriding a user who has
    /// deliberately set the key themselves.
    static func openATapeInsteadOfAnOpenPanel() {
        UserDefaults.standard.register(
            defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false]
        )
    }

    /// Launched with nothing to open: make a new tape rather than asking the user to find one.
    ///
    /// SwiftUI does not consult this on a cold launch — measured, it is never called, which is why
    /// the default above is the actual fix. It is kept because AppKit *does* ask it on other
    /// untitled-file paths, and answering consistently costs nothing.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.documents.isEmpty
    }

    /// Clicking the dock icon with every window closed must bring a tape back. Without this the app
    /// stays running and unreachable — the same "no main window" symptom, one step later.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, NSDocumentController.shared.documents.isEmpty else { return true }
        NSDocumentController.shared.newDocument(nil)
        return false
    }
}
#endif
