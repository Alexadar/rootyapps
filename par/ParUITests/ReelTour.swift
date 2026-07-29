import UIKit
import XCTest

/// The app-preview tour: five scenes, driven by real taps, at human speed.
///
/// What it has to show, in order, is Par's actual pitch — a solved problem lands on a tape and stays
/// there. So the tour solves, watches the line appear, solves again, and only then goes wandering
/// through the other tools. A tour that just visits screens would sell a menu.
///
/// Timing contract with `marketing/reels/make_reel.sh`: `REEL_T0` and `REEL_END` bracket the content
/// (everything before T0 is trimmed as launch settle), and each `REEL_SCENE <key>` marks a caption
/// boundary. `align_scenes.py` turns those epochs into measured caption windows, so the captions
/// cannot drift out of sync with what is on screen — the JSON's own start/end are only a fallback.
///
/// Nothing here asserts. `continueAfterFailure = true` and every step is conditional: a missed
/// element must degrade one beat of the reel, never abort a recording that is already running.
final class ReelTour: XCTestCase {

    override func setUp() {
        continueAfterFailure = true
    }

    func testReelTour() {
        let app = XCUIApplication()
        // Regular width shows the tape beside the calculator, so it is on screen from the first
        // frame — an empty column there is half a preview of nothing. Compact reaches the tape
        // through a sheet, where the beat that sells it is a line *arriving* on an empty tape.
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        // Start from an empty tape: the reel's second beat is a solved line appearing on it, and a
        // seeded tape would push the new row below the fold.
        app.launchEnvironment["PAR_TAPE_SEED"] = isPad ? "1" : "0"
        // The simulator's own locale renders 6.25 as "6,250" and 420000 as "420 000,00". Correct
        // there, wrong for a US listing — and a recording is much harder to notice it in than a still.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        dwell(1.4)
        NSLog("REEL_T0 %.3f", Date().timeIntervalSince1970)

        // ── Scene 1 · TVM — change the rate on Par's own keypad and watch the payment move ──
        //
        // Only the rate is typed. The first cut ran 78 s of content, which the 30-second cap then
        // speed-fit by 2.7× — fast enough to read as frantic rather than confident. Fewer keystrokes,
        // same story.
        mark("TVM")
        dwell(0.5)
        tapID(app, "tvm.input.annualRate.row")
        clearAndType(app, "5.75")
        dwell(0.9)                                  // the hero has been recomputing the whole time
        keypad(app, "solve")
        dwell(0.9)

        // ── Scene 2 · the tape — the line that just landed on it ──
        mark("Tape")
        if isPad {
            dwell(2.2)                              // the tape is already beside the calculator
        } else {
            tapID(app, "tape.peek")
            dwell(2.0)
            tapID(app, "tape.done")
            dwell(0.4)
        }

        // ── Scene 3 · a second scenario, so the tape earns its place ──
        mark("Compare")
        tapID(app, "tvm.input.periods.row")
        clearAndType(app, "180")
        dwell(0.6)
        keypad(app, "solve")
        dwell(0.5)
        if isPad {
            dwell(2.0)                              // 30 year and 15 year, side by side
        } else {
            tapID(app, "tape.peek")
            dwell(2.2)
            tapID(app, "tape.done")
            dwell(0.4)
        }

        // ── Scene 4 · Bond — a yield, and the convention it was priced under ──
        open(app, tool: "Bond")
        mark("Bond")
        dwell(2.2)

        // ── Scene 5 · Dates — six conventions disagreeing on the same two dates ──
        open(app, tool: "Dates")
        mark("Dates")
        dwell(2.6)

        NSLog("REEL_END %.3f", Date().timeIntervalSince1970)
    }

    // MARK: - Steps
    //
    // Everything is matched by accessibility identifier rather than by visible label. kerfcalc's tour
    // matches on copy ("Rafter", "All formulas") and silently degrades to a static screen when a
    // string changes; Par's screens carry identifiers precisely so the reel cannot rot that way.

    /// Clear the selected register and punch a value in on Par's keypad, one key at a time so the
    /// hero visibly recomputes as it goes.
    private func clearAndType(_ app: XCUIApplication, _ value: String) {
        keypad(app, "clearEntry")
        dwell(0.2)
        for character in value {
            keypad(app, character == "." ? "decimal" : "digit.\(character)")
            dwell(0.10)
        }
        dwell(0.5)
    }

    /// Keypad keys are resolved once and then tapped by coordinate.
    ///
    /// Every element query snapshots the whole accessibility tree, which on a 13" iPad — sidebar,
    /// tape, ten registers — costs about three seconds. Fifteen taps of that is a minute of dead
    /// reel. The keypad does not move for the duration of the tour, so its frames can be cached and
    /// the taps sent straight to the coordinates.
    private func keypad(_ app: XCUIApplication, _ key: String) {
        let identifier = "keypad.\(key)"
        if let frame = keyFrames[identifier] {
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
                .tap()
            return
        }
        let element = app.buttons[identifier].firstMatch
        guard element.waitForExistence(timeout: 1.5) else {
            NSLog("REEL_MISS %@", identifier)
            return
        }
        keyFrames[identifier] = element.frame
        element.tap()
    }

    private var keyFrames: [String: CGRect] = [:]

    /// Tap by identifier, whatever kind of element carries it. The first cut only searched
    /// `app.buttons`, so every register row and tool segment — containers, not buttons — silently
    /// timed out and the tour played 19 s of nothing. Existence, not hittability, is the gate: a
    /// custom container can report itself unhittable and still occupy a frame a finger would hit.
    private func tapID(_ app: XCUIApplication, _ identifier: String) {
        for query in [app.buttons[identifier], app.descendants(matching: .any)[identifier]] {
            let element = query.firstMatch
            guard element.waitForExistence(timeout: 1.5) else { continue }
            element.tap()
            return
        }
        NSLog("REEL_MISS %@", identifier)
    }

    /// Switch tools. Regular width (iPad) uses the sidebar list; compact (iPhone) the segmented
    /// picker at the top. One tour serves both, as the reel is shot on each.
    private func open(_ app: XCUIApplication, tool: String) {
        // Compact (iPhone) is the segmented picker, regular (iPad) the sidebar list. Both carry real
        // identifiers — `tool.picker.Bond`, `sidebar.tool.Bond` — so neither depends on visible copy.
        let routes = UIDevice.current.userInterfaceIdiom == .pad
            ? ["sidebar.tool.\(tool)", "tool.picker.\(tool)"]
            : ["tool.picker.\(tool)", "sidebar.tool.\(tool)"]
        for identifier in routes {
            let element = app.descendants(matching: .any)[identifier].firstMatch
            guard element.waitForExistence(timeout: 1.5) else { continue }
            // Ten tools do not fit across a phone, so the later ones start beyond the fold. Scroll
            // the strip until the segment is actually on screen — and let the scroll play, since a
            // reel showing the strip move is a reel showing there is more than one tool.
            let strip = app.scrollViews["tool.picker.strip"].firstMatch
            var attempts = 0
            while !isOnScreen(app, element), attempts < 4, strip.exists {
                // Ten tools on a strip the Reference button narrowed: a slow swipe needs four or
                // five passes, and each one costs a snapshot as well as its own dwell.
                strip.swipeLeft(velocity: .init(rawValue: 900))
                dwell(0.12)
                attempts += 1
            }
            guard isOnScreen(app, element) else { continue }
            element.tap()
            dwell(0.7)
            return
        }
        NSLog("REEL_MISS tool.%@", tool)
    }

    private func swipe(_ app: XCUIApplication, times: Int) {
        for _ in 0..<times {
            app.swipeUp(velocity: .init(rawValue: 420))
            dwell(0.5)
        }
    }

    /// Whether an element occupies real estate inside the window. `isHittable` is the obvious test
    /// and the wrong one: on an element scrolled past the fold XCUITest cannot compute an activation
    /// point and *fails the test* rather than returning false, which is exactly how a whole recording
    /// was lost to the tenth tool being off screen.
    private func isOnScreen(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard frame.width > 1, frame.height > 1 else { return false }
        if windowFrame == .null { windowFrame = app.windows.firstMatch.frame }
        return windowFrame.contains(frame)
    }

    /// Resolved once. The window does not move, and asking for it costs a snapshot.
    private var windowFrame: CGRect = .null

    private func mark(_ key: String) {
        NSLog("REEL_SCENE %@ %.3f", key, Date().timeIntervalSince1970)
    }

    private func dwell(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
