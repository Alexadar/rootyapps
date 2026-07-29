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
            let app = XCUIApplication()
            // Start from an empty tape so the row count after one append is unambiguous.
            app.launchEnvironment["PAR_TOOL"] = tool.slug
            app.launchEnvironment["PAR_TAPE_SEED"] = "0"
            app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()

            let append = app.descendants(matching: .any)["\(tool.prefix).tape.append"].firstMatch
            XCTAssertTrue(append.waitForExistence(timeout: 5),
                          "\(tool.slug): no append control on screen — this is the defect this test exists for")
            XCTAssertTrue(append.isEnabled,
                          "\(tool.slug): the screen's default inputs do not produce an appendable row")

            // Name it first, so the label field is exercised too — it was reachable only through the
            // same toolbar, which meant every row would have arrived unlabeled.
            let label = app.descendants(matching: .any)["\(tool.prefix).tape.label"].firstMatch
            if label.waitForExistence(timeout: 2), label.isHittable {
                label.tap()
                label.typeText("probe")
            }

            append.tap()

            // The tape now has a line. On a compact width it is behind the peek strip; on a regular
            // width it is already beside the calculator. Either way the row exists.
            let peek = app.descendants(matching: .any)["tape.peek"].firstMatch
            if peek.waitForExistence(timeout: 2), peek.isHittable {
                peek.tap()
            }
            let empty = app.descendants(matching: .any)["tape.empty"].firstMatch
            XCTAssertFalse(empty.exists,
                           "\(tool.slug): the tape is still empty after appending")

            app.terminate()
        }
    }
}
