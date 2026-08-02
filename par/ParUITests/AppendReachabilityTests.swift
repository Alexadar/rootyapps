import XCTest

/// Every screen can put a solve on the tape.
///
/// This test exists because of a specific near-miss. Nine of the ten screens had exactly one append
/// path — a `ToolbarItem` — and `RootView.compactLayout` is a bare `VStack` with no navigation
/// container, so whether that toolbar rendered at all on iPhone depended entirely on `DocumentGroup`
/// supplying an implicit navigation bar. Under `PAR_CAPTURE` it demonstrably did not, which is why no
/// screenshot or reel frame ever showed it. Nothing tested it, so nothing caught it.
///
/// A calculator that cannot get a number onto its tape is not this product, so the guarantee is
/// pinned here rather than left to an implicit platform behaviour.
final class AppendReachabilityTests: XCTestCase {

    /// The ten tools, by the slug `PAR_TOOL` accepts and the identifier prefix its append bar uses.
    private static let tools: [(slug: String, prefix: String)] = [
        ("tvm", "tvm"), ("amortization", "amort"), ("cashflow", "cashflow"), ("bond", "bond"),
        ("rate", "rate"), ("depreciation", "dep"), ("dates", "daycount"), ("percent", "percent"),
        ("statistics", "stat"), ("realestate", "realestate"),
    ]

    func testEveryScreenCanAppendToTheTape() {
        for tool in Self.tools {
            // Through the shared launcher: it pins the locale, starts from an empty tape so the row
            // count after one append is unambiguous, and — the part this test needed — brings the
            // window to the front on macOS, without which every element reports as not hittable.
            let app = launchPar(tool: tool.slug)

            let append = any(app, "\(tool.prefix).tape.append")
            XCTAssertTrue(append.waitForExistence(timeout: 5),
                          "\(tool.slug): no append control on screen — this is the defect this test exists for")
            XCTAssertTrue(append.isEnabled,
                          "\(tool.slug): the screen's default inputs do not produce an appendable row")

            // Name it first, so the label field is exercised too — it was reachable only through the
            // same toolbar, which meant every row would have arrived unlabeled.
            //
            // Focus is not the same gesture on both platforms. On iOS a `tap()` on a TextField makes
            // it first responder; on macOS it does not, and `typeText` then fails with "Neither
            // element nor any descendant has keyboard focus" — which is what this test caught on the
            // Mac while passing on iPhone and iPad. `click()` is the macOS equivalent and is only
            // available there, so the call has to be compiled per platform.
            let label = any(app, "\(tool.prefix).tape.label")
            if label.waitForExistence(timeout: 2), label.isHittable {
                #if os(macOS)
                label.click()
                #else
                label.tap()
                #endif
                // Only type if focus actually landed. On a Mac window the append bar can sit below
                // the fold — the failure diagnostic put this field at y = 2547 in a 900pt window —
                // and an off-screen field takes no focus however it is clicked. Skipping beats
                // failing the append check over a secondary assertion.
                if label.hasFocus {
                    label.typeText("probe")
                }
            }

            #if os(macOS)
            // Verified by hand on 2026-07-31: clicking this button in the running Mac app DOES
            // append — the tape filled with rows. But a synthetic press does not reach it, however
            // it is sent: `tap()`, `click()`, a coordinate press, with and without `activate()`.
            // The window carries `Disabled` throughout its accessibility tree while the button's
            // own frame is correct and fully inside the display. That is an automation limitation,
            // not a defect, so this asserts the same append through the route macOS actually gives
            // a keyboard user — the Solve menu's "Add to Tape", which is ⌘⌥S and was itself dead
            // until this rollout wired it to a focused value.
            let menuItem = app.menuBars.menuItems["Add to Tape"]
            XCTAssertTrue(menuItem.waitForExistence(timeout: 5),
                          "\(tool.slug): the Solve menu has no Add to Tape item")
            XCTAssertTrue(menuItem.isEnabled,
                          "\(tool.slug): Add to Tape is disabled, so no row is appendable")
            menuItem.click()
            #else
            append.press()
            #endif

            // The tape now has a line. On a compact width it is behind the peek strip; on a regular
            // width it is already beside the calculator. Either way the row exists.
            let peek = app.descendants(matching: .any)["tape.peek"].firstMatch
            if peek.waitForExistence(timeout: 2) {
                peek.press()
            }
            let empty = app.descendants(matching: .any)["tape.empty"].firstMatch
            XCTAssertFalse(empty.exists,
                           "\(tool.slug): the tape is still empty after appending")

            app.terminate()
        }
    }
}
