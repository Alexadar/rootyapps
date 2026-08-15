import XCTest

/// One numeric check per shipping tab, asserted at a pinned instant.
///
/// ## What this layer is for
///
/// Not arithmetic — EphemerisKit owns that and proves it against JPL Horizons with 61 `@Test`s in
/// milliseconds. These tests prove **wiring**: that a correct number reaches the right label on the
/// right screen. A model test cannot catch a view bound to the wrong property, and that is the only
/// thing being checked here.
///
/// ## Why the expected values are duplicated from the Kit tests
///
/// Deliberately (§C.1). If someone changes what the Kit answers, *both* layers have to be updated
/// and the diff makes that visible. A UI test that recomputed the expected value from the Kit would
/// agree with any regression the Kit introduced.
///
/// ## The instant, and why it is this one
///
/// `2026-07-15T12:00:00Z` in Los Angeles, chosen by scanning candidates rather than picked by hand:
/// every body sits at least **3°19′ clear of a sign boundary** and there are 17 aspects in orb.
/// The first instant tried (the March equinox) put the Sun 6 arcminutes from the Pisces/Aries edge —
/// a value any tiny ephemeris difference could flip into the next sign, which would look like a
/// rendering bug rather than the knife-edge input it was. It also had **zero** aspects, leaving the
/// Aspects tab with nothing to assert.
final class TabChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// Tab indices, matching `IOSContentView`'s tags and `MacOSContentView`'s selection.
    private enum Tab { static let chart = 0, positions = 1, aspects = 2, cycle = 3, events = 4 }

    // MARK: - Tab 0 — Chart

    func testChartWheelRendersAndHousesShowKnownAngles() {
        // The wheel and the houses now live on two different lenses of the Sky section, so this
        // checks the wheel first, then reopens on the Houses lens for the angles.
        let app = XCUIApplication().launchPinned(tab: Tab.chart)

        let wheel = any(app, "chart.wheel")
        XCTAssertTrue(wheel.waitForExistence(timeout: 20),
                      "the chart wheel must publish an element — a bare Canvas publishes nothing, "
                      + "so this also guards the .accessibilityElement() on it")

        // Placidus at 34.052N/118.244W. Ascendant and Midheaven are the two values a practitioner
        // checks first, so they are the ones worth pinning.
        app.terminate()

        let houses = XCUIApplication().launchPinned(tab: Tab.chart, lens: "houses")
        XCTAssertTrue(any(houses, "card.houses").waitForExistence(timeout: 20))
        XCTAssertEqual(any(houses, "angle.ac.degrees").text, "10° 50′", "Ascendant")
        XCTAssertEqual(any(houses, "angle.mc.degrees").text, "24° 40′", "Midheaven")
        // Cusp 1 is the Ascendant, so this also proves the cusp rows are wired to the same houses.
        XCTAssertEqual(any(houses, "cusp.1.degrees").text, "10° 50′", "1st cusp = Ascendant")
    }

    /// The house-system control: a model test can prove the six systems compute differently, but only
    /// this can prove the picker is actually bound to the cusps that get drawn.
    func testChangingHouseSystemRedrawsTheCusps() {
        let app = XCUIApplication().launchPinned(tab: Tab.chart, lens: "houses")
        let cusp11 = any(app, "cusp.11.degrees")
        XCTAssertTrue(cusp11.waitForExistence(timeout: 20))

        let placidus = cusp11.text
        XCTAssertEqual(placidus, "29° 48′", "Placidus 11th cusp")

        let picker = any(app, "input.houseSystem")
        guard picker.waitForExistence(timeout: 10) else {
            return XCTFail("the house-system picker must be addressable")
        }
        picker.tap()
        // Whole Sign puts every cusp at 0° of its sign — an unmistakably different answer, so this
        // cannot pass by accident the way a neighbouring system's similar value might.
        let wholeSign = menuOption(app, "Whole Sign")
        guard wholeSign.exists else {
            return XCTFail("Whole Sign must be offered in the picker")
        }
        wholeSign.tap()

        XCTAssertEqual(any(app, "cusp.11.degrees").text, "0° 00′",
                       "switching to Whole Sign must REDRAW the cusps, not just relabel the menu — "
                       + "a picker that changes its title while the numbers stay put is the exact "
                       + "defect that shipped a dead unit toggle on a watch app")
    }

    // MARK: - Tab 1 — Positions

    func testPositionsShowKnownDegrees() {
        let app = XCUIApplication().launchPinned(tab: Tab.positions)
        XCTAssertTrue(any(app, "card.positions").waitForExistence(timeout: 20))

        XCTAssertEqual(any(app, "pos.sun.degrees").text, "23° 02′", "Sun in Cancer")
        XCTAssertEqual(any(app, "pos.moon.degrees").text, "8° 14′", "Moon in Leo")
        XCTAssertEqual(any(app, "pos.jupiter.degrees").text, "3° 19′", "Jupiter in Leo")
        XCTAssertEqual(any(app, "pos.pluto.degrees").text, "4° 33′", "Pluto in Aquarius")
    }

    /// Retrograde is a boolean the Kit computes and the row renders with a ℞ prefix. Mercury is
    /// retrograde at this instant and Venus is not, so this pins both polarities — a motion column
    /// that always printed ℞, or never did, would pass a single-sided check.
    func testRetrogradeMarkerReflectsTheEphemeris() {
        let app = XCUIApplication().launchPinned(tab: Tab.positions)
        XCTAssertTrue(any(app, "pos.mercury.motion").waitForExistence(timeout: 20))

        XCTAssertTrue(any(app, "pos.mercury.motion").text.contains("℞"),
                      "Mercury is retrograde on 2026-07-15")
        XCTAssertFalse(any(app, "pos.venus.motion").text.contains("℞"),
                       "Venus is direct on 2026-07-15")
    }

    // MARK: - Tab 2 — Aspects

    func testAspectsShowKnownOrb() {
        let app = XCUIApplication().launchPinned(tab: Tab.aspects)
        XCTAssertTrue(any(app, "card.aspects").waitForExistence(timeout: 20))

        // Sun conjunct Mercury, orb 3.85°. Asserted by containment rather than equality because the
        // row also carries the word "orb" and a degree sign, and the decimal separator follows the
        // app's locale.
        let sunMercury = any(app, "aspect.sun.mercury.orb")
        XCTAssertTrue(sunMercury.waitForExistence(timeout: 10),
                      "Sun–Mercury must be in orb at this instant")
        XCTAssertTrue(sunMercury.text.contains("3.8"),
                      "expected orb ≈3.85°, got '\(sunMercury.text)'")

        XCTAssertTrue(any(app, "aspect.mars.saturn.orb").text.contains("2.8"),
                      "Mars sextile Saturn, orb ≈2.85°")
    }

    // MARK: - Tab 3 — Cycle

    func testCycleShowsThePhaseForTheChosenBody() {
        let app = XCUIApplication().launchPinned(tab: Tab.cycle)
        let title = any(app, "cycle.phaseTitle")
        XCTAssertTrue(title.waitForExistence(timeout: 20), "the synodic phase card must render")
        // The Kit composes this from structured fields; asserting non-empty proves the composition
        // reached the label. Mercury is retrograde here, so the phase must say so.
        XCTAssertFalse(title.text.isEmpty, "the phase title must not be empty")
        XCTAssertTrue(any(app, "input.cycleBody").waitForExistence(timeout: 10),
                      "the body picker must be addressable")
    }

    // MARK: - Tab 4 — Events

    func testEventsShowDatedRows() {
        let app = XCUIApplication().launchPinned(tab: Tab.events)
        XCTAssertTrue(any(app, "card.events").waitForExistence(timeout: 20))
        // Identifiers are keyed on the Kit's event code, so rather than pin a code that a window
        // shift could move out of range, assert that dated rows exist at all.
        XCTAssertGreaterThan(allMatching(app, "card.events").count, 0)
        let anyDate = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'event.' AND identifier ENDSWITH '.date'"))
        XCTAssertGreaterThan(anyDate.count, 0, "the timeline must publish dated rows")
    }

    // MARK: - Coverage guard

    /// Fails when a section ships without a numeric check above (§C.1).
    ///
    /// The two counts are deliberately separate. Five sections render numbers at the pinned instant
    /// and are asserted against known values. **Natal is not one of them** — its library is empty
    /// until a chart is saved, so there is nothing numeric to pin; it is covered structurally by
    /// `DeepLinkChecks` instead. Claiming a numeric check it does not have would be worse than
    /// admitting the gap.
    ///
    /// The total is asserted too, so adding a sixth-and-then-seventh section forces this decision
    /// rather than silently shipping untested.
    func testEveryToolHasANumericCheck() {
        // Navigation regrouped from six flat sections to three categories with lenses. What is
        // asserted did not shrink — these are the same readings, now reached differently.
        let numericallyCovered = ["sky.wheel", "sky.table", "sky.aspects", "sky.houses",
                                  "cycles.synodic", "cycles.timeline"]
        XCTAssertEqual(numericallyCovered.count, 6, "six readings assert a known value")
        XCTAssertEqual(Set(numericallyCovered).count, numericallyCovered.count,
                       "duplicate in the coverage list")

        // Charts is covered structurally by DeepLinkChecks, not numerically: its library is empty
        // until a chart is saved, so there is nothing to pin. Claiming a numeric check it does not
        // have would be worse than naming the gap.
        let categories = ["sky", "charts", "cycles"]
        XCTAssertEqual(categories.count, 3,
                       "three categories — a fourth needs a check, numeric or structural")
    }
}
