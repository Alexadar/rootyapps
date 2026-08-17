import XCTest

/// The app-preview tour — **a capture driver, not a test.**
///
/// It asserts almost nothing on purpose: its job is to walk the app at human speed while
/// `make_reel.sh` records the screen, and to emit `REEL_T0 / REEL_SCENE / REEL_END` markers that
/// `align_scenes.py` reads so each caption lands on the segment it describes. It is excluded from
/// the `aircore` scheme's test action, because 30 seconds of scripted dwelling is not a test and
/// would only slow every real run down.
///
/// ## What the 30 seconds argue
///
/// In order: the chart is *the* interface and works in both directions; the elevation is a
/// first-class input and visibly changes the answers; the duct surface is real; two airstreams mix
/// by mass; and the water side is honest about the two methods disagreeing. That is the product's
/// case, made by using it rather than by claiming it.
final class ReelTour: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    func testReelTour() {
        let app = XCUIApplication()
        app.launchEnvironment["AIRCORE_RESET"] = "1"
        app.launchEnvironment["AIRCORE_TOOL"] = "psychrometrics"
        #if os(macOS)
        // Without this the Mac window comes back at whatever size it was last left, and a narrow
        // window folds the toolbar into a "..." overflow — where the elevation chip is no longer a
        // Button anyone can find. The tour then dies on scene two.
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        // A Mac capture runs on this machine and inherits its region, so the first Mac recording
        // read "86,6 °F" and "1 000 CFM" — comma decimals and space separators — in a preview for a
        // US-only listing. The simulators are pinned at creation; there is no device to pin here,
        // so the app is pinned instead. Same fix as make_mac_shots.sh, which the reel never got.
        app.launchArguments += ["-AppleLocale", "en_US", "-AppleLanguages", "(en-US)"]
        // 16:9, so fitting the capture to the required 1920×1080 is a downscale and not a crop.
        app.launchEnvironment["AIRCORE_WINDOW"] = "1456x819"
        // Pinned so the recording matches the Mac screenshots regardless of the hour it runs at.
        app.launchEnvironment["AIRCORE_APPEARANCE"] = "light"
        #endif
        app.launch()
        dwell(1.4)
        NSLog("REEL_T0 %.3f", Date().timeIntervalSince1970)

        // ── Scene 1 · Chart — drag the state point, every value follows ──────────────────
        mark("Chart")
        let chart = any(app, "psychro.chart")
        if chart.waitForExistence(timeout: 8) {
            // Three unhurried drags. The point is the interface, so this is the one scene that has
            // to read as *use* rather than as a screenshot with a cursor over it.
            drag(chart, from: CGVector(dx: 0.45, dy: 0.45), to: CGVector(dx: 0.62, dy: 0.38))
            dwell(0.9)
            drag(chart, from: CGVector(dx: 0.62, dy: 0.38), to: CGVector(dx: 0.72, dy: 0.58))
            dwell(0.9)
            drag(chart, from: CGVector(dx: 0.72, dy: 0.58), to: CGVector(dx: 0.5, dy: 0.5))
            dwell(1.2)
        }

        // ── Scene 2 · Elevation — the differentiator, shown moving the numbers ───────────
        mark("Elevation")
        tap(app, "settings.elevation")     // type-agnostic: not a Button on every platform
        dwell(1.1)
        tap(app, "elevation.preset.Denver")
        dwell(1.6)                                   // the corrected constant appears
        tap(app, "elevation.done")
        dwell(1.6)                                   // …and every result on the screen has moved

        // ── Scene 3 · Duct — the surface is real, and so is the velocity check ───────────
        openAndMark(app, "duct", "Duct"); dwell(1.4)
        tap(app, "duct.roughness")
        dwell(0.7)
        let rough = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Rough' OR title == 'Rough'")).firstMatch
        if rough.waitForExistence(timeout: 2) { rough.tap() }
        dwell(2.2)                                   // diameter and velocity both jump

        // ── Scene 4 · Mixing — two states, the line between them, weighted by mass ───────
        openAndMark(app, "mixing", "Mixing"); dwell(3.2)

        // ── Scene 5 · Pipe — two published methods, and the gap between them ─────────────
        openAndMark(app, "pipe", "Pipe"); dwell(1.2)
        let hazen = any(app, "pipe.method").descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Hazen' OR title CONTAINS 'Hazen'"))
            .firstMatch
        if hazen.waitForExistence(timeout: 2) { hazen.tap() }
        dwell(2.6)

        NSLog("REEL_END %.3f", Date().timeIntervalSince1970)

        // Hold the window open past the end of the content.
        //
        // On macOS the recorder is a separate process writing to the same window: when the test
        // ends, the app quits, the window goes, and ScreenCaptureKit is killed mid-write — leaving
        // a multi-megabyte .mov with no moov atom, which ffprobe reports as "Invalid data" and no
        // tool can read. This tail is outside REEL_END so it never reaches the cut; it exists only
        // to give the recorder time to finalise.
        dwell(8.0)
    }

    // MARK: - Steps

    // `any(_:_:)` and `tap(_:_:)` come from UITestSupport — redeclaring them here would try to
    // override an extension method, which Swift does not allow, and would also fork two lookups
    // that need to stay identical.

    /// Back to the catalogue, into the next tool, and **only mark the scene once it is actually on
    /// screen**.
    ///
    /// The first recording marked each scene the moment it *asked* to navigate. Two of the five
    /// navigations silently failed — a picker menu was still open and swallowed the tap — so the
    /// captions "Mixed by mass, not volume" and "Darcy and Hazen–Williams" played over thirty
    /// seconds of the duct screen. The video looked fine; only tiling it showed the mismatch, and
    /// captions describing content that is not on screen are an accurate-metadata rejection.
    ///
    /// So arrival is now waited for and returned, and the marker is emitted by the caller only on
    /// success.
    @discardableResult
    private func openAndMark(_ app: XCUIApplication, _ tool: String, _ key: String) -> Bool {
        // A menu left open swallows the next tap. Dismiss whatever is up before navigating.
        // Dismiss whatever is open before navigating — a live menu swallows the next tap.
        // `app.tap()` is an iOS idiom: on macOS the application element is not hittable and the
        // call throws outright, which ended the tour on scene two.
        #if os(macOS)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        #else
        if app.sheets.firstMatch.exists || app.popovers.firstMatch.exists {
            app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        } else {
            app.tap()
        }
        #endif
        dwell(0.5)

        // Sidebar first. On iPad and Mac the tools live in a sidebar and there is no catalogue to
        // go back to — and `navigationBars.buttons[0]` there is the sidebar TOGGLE, so the phone's
        // back-then-tap dance collapsed the sidebar and stranded the tour on the second scene.
        if any(app, "sidebar.\(tool)").exists {
            tap(app, "sidebar.\(tool)")
        } else {
            let backButtons = app.navigationBars.buttons
            if backButtons.count > 0, backButtons.element(boundBy: 0).exists {
                backButtons.element(boundBy: 0).tap()
                dwell(0.9)
            }
            if any(app, "tool.\(tool)").waitForExistence(timeout: 3) {
                tap(app, "tool.\(tool)")
            }
        }

        let arrived = any(app, "\(tool).hero").waitForExistence(timeout: 6)
        if arrived {
            mark(key)
        } else {
            NSLog("REEL_MISS %@ — never arrived, caption would have drifted", tool)
        }
        return arrived
    }

    private func drag(_ element: XCUIElement, from: CGVector, to: CGVector) {
        element.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.08,
                   thenDragTo: element.coordinate(withNormalizedOffset: to))
    }

    private func mark(_ key: String) {
        NSLog("REEL_SCENE %@ %.3f", key, Date().timeIntervalSince1970)
    }

    private func dwell(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}
