import XCTest
@testable import Wallpapers

/// The credit the app is obliged to show.
///
/// The diffusion checkpoint ships under terms with `allowNoCredit: false` — attribution is a
/// **condition of redistributing the weights**, and the weights are in the bundle. This is the one
/// piece of UI whose absence is a licence breach rather than a missing feature, and it is exactly
/// the kind of quiet text a later layout change deletes without anything going red.
///
/// So it is asserted. The authoritative record lives in `LICENCE.txt` beside the converted model;
/// this checks the app actually says it.
final class AttributionChecks: XCTestCase {

    func testTheModelThatRequiresCreditIsCredited() {
        let all = AdvancedSheet.credits.joined(separator: "\n")
        XCTAssertTrue(all.contains("Lyriel"),
                      "the diffusion checkpoint requires attribution and is not credited")
    }

    func testEveryModelInThePipelineIsNamed() {
        // Not all of these demand credit. Listing them all is what keeps the list honest — a list
        // with silent omissions is harder to keep true than a complete one.
        let all = AdvancedSheet.credits.joined(separator: "\n")
        for name in ["Theovercomer8", "ControlNet", "lllyasviel", "Real-ESRGAN", "Stable Diffusion"] {
            XCTAssertTrue(all.contains(name), "\(name) is in the pipeline but not acknowledged")
        }
    }

    func testTheLicenceLineNamesTheModelActuallyShipped() {
        // The design bundle says "Stable Diffusion 1.5 under the CreativeML Open RAIL-M licence".
        // That is the BASE model's licence, not the fine-tune in the bundle. Shipping it would
        // discharge an obligation the app does not have and leave the one it does have unmet.
        XCTAssertTrue(Attribution.licenceLine.contains("Lyriel"),
                      "the shipped checkpoint requires this credit by name")
        XCTAssertFalse(Attribution.licenceLine.contains("CreativeML"),
                       "the bundle's incorrect licence must not creep back in")
    }

    func testAdvancedStillCarriesTheCreditAfterTheExtraction() {
        // The list moved to `Attribution`; this alias is the proof nothing was dropped on the way.
        XCTAssertEqual(AdvancedSheet.credits, Attribution.credits)
        XCTAssertFalse(AdvancedSheet.credits.isEmpty)
    }

    func testTheCreditsAreNotEmptyOrPlaceholders() {
        XCTAssertGreaterThanOrEqual(AdvancedSheet.credits.count, 5)
        for line in AdvancedSheet.credits {
            XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(line.lowercased().contains("todo"), "placeholder credit: \(line)")
        }
    }
}
