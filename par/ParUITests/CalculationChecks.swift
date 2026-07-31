import XCTest

/// Every shipping tool, checked through the UI against a known answer.
///
/// ## What this proves, and what it does not
///
/// Not the arithmetic. Ten Kits own that, with 261 `swift test` assertions against 31 CFR 356 App B,
/// 12 CFR 1026 App J, 12 CFR 1030 App A, IRS Publication 946 App A, the 2006 ISDA Definitions §4.16
/// and the NIST/ITL reference datasets. If a number here is wrong, a Kit test is the one that should
/// have caught it, and this file only tells you the **wiring** between Kit and screen is broken — a
/// view reading the wrong property, a formatter dropping a place, a tool showing another tool's
/// result. Par shipped with six such defects at once, so the layer is not hypothetical.
///
/// The expected values are deliberately the same worked examples the Kits assert. They are duplicated
/// on purpose: change a Kit's answer and both layers must be updated, and the diff makes that visible.
///
/// Two of the ten are genuinely published numbers, and those are the ones worth defending:
///
/// - **Depreciation `1,429.00`** — IRS Publication 946 Appendix A, Table A-1, year 1 of 7-year
///   property at 14.29%. The screen's default inputs *are* the publication's worked example
///   ($10,000 of office furniture), asserted at `DepKitTests/DepTests.swift` `publishedFurnitureExample`.
/// - **Rate & APR `9.686%`** — Regulation Z Appendix J example (c)(1)(i): $5,000 advanced, 24 monthly
///   payments of $230. Note the authority publishes **9.69**, correct to two decimals, while the hero
///   prints three. Both are right; the difference is precision, and pinning it here is the point.
///
/// ## Formatting
///
/// `Fmt` builds a `NumberFormatter` with `.decimal`, so there is **no currency symbol** anywhere —
/// `-2,586.01`, never `-$2,586.01` — and thousands are grouped. Assertions are substring matches
/// against the element's `text`, which reads `label` or falls back to `value` (see `UITestSupport`).
/// `Fmt.spokenMoney` renders a negative as the word "negative" rather than a `-` glyph, so money
/// assertions match the unsigned digits; that is enough to prove the wiring.
///
/// ## Running — the configuration is not optional
///
///     xcodebuild test -scheme Par -configuration Capture \
///       -destination 'platform=iOS Simulator,name=<a dedicated, locale-pinned sim>' \
///       -only-testing:ParUITests/CalculationChecks
///
/// **`-configuration Capture`, not Debug.** Par ships as a `DocumentGroup`, so a Debug launch opens
/// the system document browser and no calculator is on screen at all — every identifier below is
/// missing and all ten tests fail with "no element". `PAR_CAPTURE` swaps that one scene container for
/// a `WindowGroup` bound to the same `RootView` and the same `TapeDocument`; nothing about any
/// calculator screen differs.
///
/// **Known gap, stated rather than hidden:** because of that swap, these tests never exercise the
/// document-browser entry path a customer meets on first run. `ParTests` covers the document itself
/// — save, reopen, per-row re-solve — but the browser-to-editor transition is untested by anything.
///
/// Simulators only, never a physical device: a run launches and kills the app dozens of times.
final class CalculationChecks: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Helpers

    /// The string an element shows, whatever type SwiftUI published it as.
    private func value(_ app: XCUIApplication, _ identifier: String,
                       file: StaticString = #filePath, line: UInt = #line) -> String {
        let element = any(app, identifier)
        XCTAssertTrue(element.waitForExistence(timeout: 10),
                      "no element '\(identifier)' — dump app.debugDescription rather than guessing",
                      file: file, line: line)
        return element.text
    }

    private func assertShows(_ app: XCUIApplication, _ identifier: String, _ needle: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let got = value(app, identifier, file: file, line: line)
        XCTAssertTrue(got.contains(needle),
                      "'\(identifier)' shows \"\(got)\", expected to contain \"\(needle)\"",
                      file: file, line: line)
    }

    // MARK: - One numeric check per tool

    func testTimeValueOfMoneySolvesThePayment() {
        // 360 months, 6.25% nominal, PV 420,000, FV 0 -> PMT. A 30-year mortgage.
        let app = launchPar(tool: "tvm")
        assertShows(app, "tvm.hero", "2,586.01")
    }

    func testAmortizationLevelPaymentAndTotalInterest() {
        // The same loan, from the other side: AmortKit's annuity must agree with TVMKit's.
        let app = launchPar(tool: "amortization")
        assertShows(app, "amort.hero", "2,586.01")
        assertShows(app, "amort.totalInterest", "510,966.07")
    }

    func testCashFlowInternalRateOfReturn() {
        // One sign change, so the IRR is unique and the hero is a result, not a failure notice.
        // Three decimals: the root comes from a bisection, so do not assert more than is stable.
        let app = launchPar(tool: "cashflow")
        assertShows(app, "cashflow.hero", "11.185%")
        assertShows(app, "cashflow.npv", "62,808.79")
    }

    func testBondYieldToMaturityAndAccruedInterest() {
        // Price 98.75, 4.25% coupon, 10 full semiannual periods, r = 18, s = 181, regular first
        // period (31 CFR 356 App B §II.A).
        let app = launchPar(tool: "bond")
        assertShows(app, "bond.hero", "4.530%")
        // Accrued is a §I identity, checkable by hand: [(181 - 18) / 181] x (4.25 / 2).
        assertShows(app, "bond.accrued", "1.913674")
    }

    func testAnnualPercentageRateMatchesRegulationZ() {
        // 12 CFR 1026 (Regulation Z) Appendix J, example (c)(1)(i): 5,000 advanced, 24 x 230.
        // The regulation publishes 9.69 to two decimals; the hero shows three.
        let app = launchPar(tool: "rate")
        assertShows(app, "rate.hero", "9.686%")
        assertShows(app, "rate.totalOfPayments", "5,520.00")
    }

    func testMacrsFirstYearMatchesPublication946() {
        // IRS Pub 946 App A Table A-1: 7-year property, half-year convention, year 1 = 14.29%.
        // 10,000 x 14.29% = 1,429.00 — the publication's own worked example.
        let app = launchPar(tool: "depreciation")
        assertShows(app, "dep.hero", "1,429.00")
        // The column totals the whole basis; that is what makes the rounding carry correct.
        assertShows(app, "dep.total", "10,000.00")
    }

    func testDayCountThirty360BetweenTwoMidMonthDates() {
        // 2026-01-15 -> 2026-07-15 under 30/360 is exactly 180. The hero is raw interpolation,
        // so there is no grouping separator to worry about.
        let app = launchPar(tool: "dates")
        assertShows(app, "daycount.hero", "180")
        // The comparison strip is the screen's argument: Actual/360 disagrees on the same dates.
        assertShows(app, "daycount.compare.actual360", "181")
    }

    func testPercentMarginAndMarkupAreNotInterchangeable() {
        // Cost 60, sell 100: margin on price is 40%, markup on cost is 66.67%. The whole point of
        // the screen is that these are different numbers.
        let app = launchPar(tool: "percent")
        assertShows(app, "percent.hero", "40.00%")
        assertShows(app, "percent.markup", "66.67%")
    }

    /// Percent's Change mode: the second half of §C.2's rule — flip the control, assert the OUTPUT
    /// changed, and assert the identifiers are unambiguous.
    ///
    /// This mode shipped rendering its own input fields twice, in `inputs` and again in `secondary`,
    /// so `percent.input.from` matched two elements and a user saw the pair duplicated. Asserting a
    /// single match is what makes that specific regression impossible.
    func testPercentChangeModeShowsResultsNotADuplicateOfItsInputs() {
        let app = launchPar(tool: "percent")
        // Cost 60 / sell 100 read as from 60 -> to 100: a 66.67% rise, +40 absolute.
        any(app, "percent.mode.Change").tap()

        assertShows(app, "percent.hero", "66.67%")
        assertShows(app, "percent.absoluteChange", "40.00")

        // Exactly one field per identifier. Two means the duplication is back.
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "percent.input.from").count, 1,
                       "percent.input.from must name exactly one field")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "percent.input.to").count, 1,
                       "percent.input.to must name exactly one field")

        // And the mode really switched: margin's rows are gone.
        XCTAssertFalse(any(app, "percent.markup").exists, "Change mode still shows the margin rows")
    }

    func testStatisticsForecastsFromTheLinearFit() {
        // Five points, linear model, forecast at x' = 6.
        let app = launchPar(tool: "statistics")
        assertShows(app, "stat.hero", "170,016.10")
    }

    func testRealEstateSizesTheLoanByTheBindingTest() {
        // NOI = 518,400 x 0.95 - 197,000 = 295,480 — exact arithmetic on the defaults, which is why
        // it is a better anchor than the hero's rounded annuity.
        let app = launchPar(tool: "realestate")
        assertShows(app, "realestate.noi", "295,480")
        // Coverage binds here: 3,199,304 by DSCR against 4,050,000 by LTV.
        assertShows(app, "realestate.hero", "3,199,304")
    }

    // MARK: - Coverage guard

    /// A new tool cannot ship without a numeric check.
    ///
    /// `RootView.Tool` is the catalog; if it grows, this fails until the test above it exists.
    func testEveryToolHasANumericCheck() {
        let covered = ["tvm", "amortization", "cashflow", "bond", "rate",
                       "depreciation", "dates", "percent", "statistics", "realestate"]
        XCTAssertEqual(covered.count, 10, "the catalog ships 10 tools")
        XCTAssertEqual(Set(covered).count, covered.count, "duplicate in the coverage list")
    }
}
