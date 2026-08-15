import XCTest

/// `EPHEMERIS_TAB` must land on the tab it names — on every layout and every platform.
///
/// ## Why this is a separate suite
///
/// The failure this guards against is silent and expensive: a deep link that quietly lands on the
/// **default** screen. Every screenshot and reel in the store is captured by setting this variable,
/// so if tab 2 opens tab 0 the pipeline produces a picture of the wrong screen and captions it
/// confidently. That is how an iPad screenshot of a calculator once shipped captioned "Every number
/// has a source".
///
/// ## What differs here from the standard trap
///
/// The documented trap is a compact `TabView` versus a regular-width `NavigationSplitView`, where the
/// router sets `selectedTab` and the regular root only watches a sidebar selection. **Ephemeris is
/// not shaped that way** — `IOSContentView` uses one `TabView` at both size classes, so iPhone and
/// iPad share a single code path.
///
/// It still has *two* paths, though: macOS is a completely separate root
/// (`MacOSContentView.selection`) reading the same variable into different state. So passing on
/// iPhone proves nothing about the Mac, and this suite runs on all three destinations.
final class DeepLinkChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// An identifier that exists **only** at the given destination, so landing anywhere else fails.
    ///
    /// The navigation was regrouped from six flat sections to three categories with lenses, and
    /// these indices are unchanged on purpose: every store screenshot and preview is captured by
    /// setting `EPHEMERIS_TAB`, so an index that stopped landing where it used to would silently
    /// re-point the whole capture pipeline. `LegacyTab.destination(for:)` is the mapping; this table
    /// is the assertion that it works.
    ///
    /// | index | was | now |
    /// |---|---|---|
    /// | 0 | Chart | Sky · Wheel |
    /// | 1 | Positions | Sky · Table |
    /// | 2 | Aspects | Sky · Aspects |
    /// | 3 | Cycle | Cycles · Synodic |
    /// | 4 | Events | Cycles · Timeline |
    /// | 5 | Natal | Charts |
    private static let marker: [Int: String] = [
        0: "chart.wheel",
        1: "card.positions",
        2: "card.aspects",
        3: "card.currentPhase",
        4: "card.events",
        // State-independent: the library shows an empty state, an error or a list, and this marker
        // is on all three.
        5: "screen.natal",
    ]

    func testEveryTabDeepLinkReachesItsOwnScreen() {
        for (tab, marker) in Self.marker.sorted(by: { $0.key < $1.key }) {
            let app = XCUIApplication().launchPinned(tab: tab)
            XCTAssertTrue(any(app, marker).waitForExistence(timeout: 20),
                          "EPHEMERIS_TAB=\(tab) did not reach '\(marker)'")

            // The real failure mode is landing on the DEFAULT screen, which a positive check alone
            // cannot see: tab 0's marker being present proves nothing when tab 0 is where every
            // broken deep link ends up. So for any non-zero tab, assert the chart is NOT showing.
            if tab != 0 {
                XCTAssertFalse(any(app, "chart.wheel").exists,
                               "EPHEMERIS_TAB=\(tab) fell back to the default Chart tab — the deep "
                               + "link is not wired on this layout")
            }
            app.terminate()
        }
    }
}
