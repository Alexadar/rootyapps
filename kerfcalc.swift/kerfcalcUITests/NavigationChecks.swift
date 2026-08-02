import XCTest

/// Navigation, deep links and the field keypad sheet — the wiring between screens rather than any
/// number. Run on an iPhone sim AND an iPad sim: the two size classes are different code paths
/// (compact `TabView` vs a rail + `CategorySidebar`), so passing on one proves nothing about the other.
final class NavigationChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    // MARK: - Deep links must land in BOTH layouts

    /// `KERFCALC_TAB=1` must reach Formulas at every width.
    ///
    /// ## The expensive trap this guards
    ///
    /// A compact layout has a `TabView`; a regular layout has a rail with no tabs at all. The router
    /// sets `selectedTab`, and if the regular root only watches its sidebar selection then every tab
    /// deep link silently lands on the default screen at regular width. kerfcalc has already shipped
    /// this once: it is how an iPad screenshot of the Spec keypad ended up captioned as a formula
    /// screen, in a live App Store listing.
    ///
    /// So this asserts BOTH that we arrived and that we did not stay: the keypad's `=` must be gone.
    func testTabDeepLinkReachesFormulasInEveryLayout() {
        let app = launchApp(tab: "1")
        let grid = any(app, "tool.rafter")
        XCTAssertTrue(grid.waitForExistence(timeout: 10),
                      "KERFCALC_TAB=1 did not reach Formulas — no tool tiles on screen")
        XCTAssertFalse(any(app, "key.equals").exists, "this is still the Spec keypad, not Formulas")
    }

    /// `KERFCALC_TOOL` must open the tool's DETAIL, not merely select its tab.
    ///
    /// Seeding a `NavigationStack` path without also selecting its tab pushes onto a stack nobody can
    /// see — the tool is then invisible on iPhone and the launch shows Spec.
    func testToolDeepLinkOpensTheDetailInEveryLayout() {
        let app = launchApp(tool: "rafter")
        assertShows(app, "rafter.hero", "173.57")
        XCTAssertTrue(any(app, "formula.citation").waitForExistence(timeout: 6),
                      "the cited FormulaCard did not render on Rafter")
        XCTAssertFalse(any(app, "key.equals").exists, "deep link landed on Spec, not the Rafter detail")
    }

    /// `KERFCALC_SCREEN` picks a tool's sub-screen. The screenshot pipeline depends on this, so a
    /// silent regression here produces a listing image of the wrong mode.
    func testSubScreenDeepLinkSelectsTheSegment() {
        let app = launchApp(tool: "concrete", screen: "1")   // Column / Hole
        XCTAssertTrue(any(app, "concrete.hero").waitForExistence(timeout: 10),
                      "Concrete detail did not load for KERFCALC_SCREEN=1")
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - Navigating from the grid

    /// Opening a tool from the Formulas grid lands on its detail with its cited formula.
    func testGridTileOpensDetail() {
        let app = launchApp(tab: "1")
        tapId(app, "tool.footing")
        assertShows(app, "footing.hero", "3.292")
        XCTAssertTrue(any(app, "formula.citation").waitForExistence(timeout: 6),
                      "Footing opened without its cited formula")
    }

    /// The favourite star toggles, and the grid survives it.
    ///
    /// Both directions: `Right Angle` (`pitch`) is not one of the seeded favourites
    /// (`rafter, concrete, stairs`), so it goes off → on → off. A star that only works one way is still
    /// broken, and asserting just the first tap would not see it.
    ///
    /// `pitch` and not `miter`: **iOS does not publish accessibility leaves that have never been on
    /// screen.** Miter sits in the fourth section, below the fold on a phone, so `fav.miter` genuinely
    /// does not exist until it is scrolled to — a real platform behaviour, not a missing identifier. The
    /// tile *title* is addressable at that depth (`tool.footing` works two sections down) because the
    /// grid keeps row containers alive; the star is a leaf inside one, and leaves are dropped.
    func testFavouriteStarTogglesBothWays() {
        let app = launchApp(tab: "1")
        let star = any(app, "fav.pitch")
        XCTAssertTrue(star.waitForExistence(timeout: 10), "Right Angle's star is missing")
        let before = star.text

        star.tap()
        XCTAssertNotEqual(any(app, "fav.pitch").text, before, "starring Right Angle changed nothing")

        any(app, "fav.pitch").tap()
        XCTAssertEqual(any(app, "fav.pitch").text, before, "un-starring Right Angle did not restore it")
        XCTAssertEqual(app.state, .runningForeground, "the grid died on a star tap")
    }

    // MARK: - Surfaces

    /// The rail (regular) / tab bar (compact) switches surfaces, and Spec's keypad comes back.
    func testSurfaceSwitchingReachesReferenceAndSpec() {
        let app = launchApp(tool: "rafter")
        _ = any(app, "rafter.hero").waitForExistence(timeout: 10)

        surface(app, "Reference")
        let ref = app.staticTexts.containing(textMatches("Stair code")).firstMatch
        XCTAssertTrue(ref.waitForExistence(timeout: 6) || app.navigationBars["Reference"].exists,
                      "the Reference surface did not show")

        surface(app, "Spec")
        XCTAssertTrue(any(app, "key.equals").waitForExistence(timeout: 6),
                      "the Spec keypad did not come back")
    }

    // MARK: - The field keypad sheet

    /// Tap a tool's feet-inch field, punch a new value on the glove pad, commit → the field updates and
    /// the hero recomputes.
    ///
    /// 20 ft of run at 6/12 is a **268.33"** line length, but the hero is the *actual cut*: less half the
    /// 1½" ridge (−0.84") plus the 12" overhang along the slope (+13.42") = **280.91"**.
    /// Kit oracle: `FramingKit.Rafter.actualLength` / `.commonLength` / `.ridgeDeductionIn` /
    /// `.overhangAlongIn`.
    ///
    /// The deleted `KeypadSheetTests` asserted `268.33` here — the line length, not the cut — so it had
    /// been failing on this screen the same way `ToolTourTests` was failing on Concrete's `1.235`.
    ///
    /// Note the sheet's own namespace (`fkey.`): its `=` COMMITS AND DISMISSES rather than evaluating,
    /// so tapping the Spec pad's `key.equals` here would be a different action entirely.
    func testFieldKeypadSheetUpdatesTheHero() {
        let app = launchApp(tool: "rafter")
        assertShows(app, "rafter.hero", "173.57")            // the 12 ft default first

        tapId(app, "input.rafter.run")
        XCTAssertTrue(any(app, "field.readout").waitForExistence(timeout: 6), "the keypad sheet did not open")

        enter(app, pad: "fkey.", feet: 20)
        tapId(app, "field.done")

        assertShows(app, "rafter.hero", "280.91")
    }

    /// The pitch stepper drives the hero, in both directions.
    ///
    /// Up: 6/12 → 7/12 must change the cut length. Down again must restore it. The steppers used to
    /// share the hardcoded ids `stepDec`/`stepInc`, and the Rafter screen has two of them, so a test
    /// could only ever reach the first one via `.firstMatch`.
    func testPitchStepperMovesTheHeroBothWays() {
        let app = launchApp(tool: "rafter")
        let start = value(app, "rafter.hero")

        tapId(app, "input.rafter.pitch.inc")
        let up = value(app, "rafter.hero")
        XCTAssertNotEqual(up, start, "the pitch stepper's + did not change the cut length")

        tapId(app, "input.rafter.pitch.dec")
        XCTAssertEqual(value(app, "rafter.hero"), start, "the pitch stepper's − did not restore it")
    }
}
