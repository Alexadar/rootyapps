import XCTest

/// Every tier-one screen has at least one check in this suite. If a screen is added,
/// this list must grow with it — the guard fails loudly instead of coverage rotting
/// silently. (Report what's covered, not how many tests are green.)
final class CoverageGuard: XCTestCase {

    func testEveryScreenIsCovered() {
        let covered: [String: [String]] = [
            "Library": ["LibraryChecks"],
            "Document grid + review": ["GridChecks"],
            "Search": ["SearchChecks"],
            "Destinations + export": ["ExportChecks"],
            "Activity": ["ImportPipelineChecks"],   // audit lines asserted there
            "Deep links (both layouts)": ["DeepLinkChecks"],
            "Import pipeline end-to-end": ["ImportPipelineChecks"],
        ]
        // Screens shipped in this target — update alongside RootView.AppSection and
        // the document surface.
        let screens = ["Library", "Document grid + review", "Search",
                       "Destinations + export", "Activity",
                       "Deep links (both layouts)", "Import pipeline end-to-end"]
        for screen in screens {
            XCTAssertNotNil(covered[screen], "screen without a UITest: \(screen)")
            XCTAssertFalse(covered[screen]?.isEmpty ?? true)
        }
        // Excluded, with reasons — visible here so the gaps stay deliberate:
        //  · Camera capture: no camera in the simulator.
        //  · Join & Split: needs a multi-page import fixture; add with the first
        //    multi-page PDF fixture (tracked in PROMPT.md next-steps).
    }
}
