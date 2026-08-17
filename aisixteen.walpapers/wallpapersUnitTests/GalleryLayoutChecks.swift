import XCTest
import ModelKit
import TaskKit
import GenerationKit
@testable import Wallpapers

/// ORACLES:
///  • INVARIANT — the split is **total**. Every item appears exactly once across hero + beside +
///    rest, in the original order. The failure that matters is not a wrong shape; it is a wallpaper
///    drawn twice, or one that silently stops being reachable because it fell between two layouts.
///  • BOUNDARY — a hero worth two columns needs a grid wide enough to seat something beside it. The
///    phone's two columns must come back untouched, not cramped.
final class GalleryLayoutChecks: XCTestCase {

    private func items(_ n: Int) -> [String] { (0..<n).map { "w\($0)" } }

    // MARK: Totality

    func testEveryItemSurvivesTheSplitExactlyOnceAndInOrder() {
        // Swept across the sizes where the boundaries actually are — nothing, a lone hero, a hero
        // with one neighbour, a full row, and rows beyond it.
        for count in 0...12 {
            let split = GalleryLayout.split(items(count), featured: true, columns: 4)
            let rebuilt = [split.hero].compactMap { $0 } + split.beside + split.rest

            XCTAssertEqual(rebuilt, items(count),
                           "the split lost, duplicated or reordered something at \(count) items")
        }
    }

    func testTheHeroIsTheMostRecentAndNeverRepeatsBelow() {
        let split = GalleryLayout.split(items(9), featured: true, columns: 4)

        XCTAssertEqual(split.hero, "w0")
        XCTAssertEqual(split.beside, ["w1", "w2"])
        XCTAssertFalse(split.rest.contains("w0"), "the hero must not also be a grid cell")
        XCTAssertEqual(split.rest, ["w3", "w4", "w5", "w6", "w7", "w8"])
    }

    // MARK: When the featured layout must not apply

    func testTwoColumnsRefuseTheHeroRatherThanCrampIt() {
        // The phone. A 2-column grid has no room beside a 2-wide hero, so asking for one must return
        // the plain grid — not a hero with an empty gutter where its neighbours should be.
        let split = GalleryLayout.split(items(6), featured: true, columns: 2)

        XCTAssertNil(split.hero)
        XCTAssertTrue(split.beside.isEmpty)
        XCTAssertEqual(split.rest, items(6), "every item stays in the ordinary grid")
    }

    func testNotFeaturingLeavesTheListCompletelyAlone() {
        let split = GalleryLayout.split(items(6), featured: false, columns: 4)

        XCTAssertNil(split.hero)
        XCTAssertEqual(split.rest, items(6))
    }

    func testAnEmptyLibraryProducesNoHero() {
        let split = GalleryLayout.split([String](), featured: true, columns: 4)

        XCTAssertNil(split.hero, "there is nothing to feature")
        XCTAssertTrue(split.rest.isEmpty)
    }

    // MARK: The nearly-empty cases, which is where an index bug would land

    func testASingleWallpaperBecomesTheHeroWithNothingBeside() {
        let split = GalleryLayout.split(["only"], featured: true, columns: 4)

        XCTAssertEqual(split.hero, "only")
        XCTAssertTrue(split.beside.isEmpty)
        XCTAssertTrue(split.rest.isEmpty)
    }

    func testTwoWallpapersFillOnlyOneOfTheTwoSideCells() {
        let split = GalleryLayout.split(["a", "b"], featured: true, columns: 4)

        XCTAssertEqual(split.hero, "a")
        XCTAssertEqual(split.beside, ["b"], "one neighbour, not a padded pair")
        XCTAssertTrue(split.rest.isEmpty)
    }

    func testTheSideColumnNeverTakesMoreThanTwo() {
        // Two is a geometric fact — a 2×2 hero leaves exactly two single cells beside it. A third
        // would be drawn outside the row it belongs to.
        for count in 3...20 {
            let split = GalleryLayout.split(items(count), featured: true, columns: 4)
            XCTAssertEqual(split.beside.count, 2, "at \(count) items")
        }
    }

    func testAWiderGridStillSeatsExactlyTwoBesideTheHero() {
        // The hero is 2 columns wide whatever the grid is, so at 6 columns the row has spare cells —
        // those belong to `rest`, and must not be absorbed into `beside`.
        let split = GalleryLayout.split(items(10), featured: true, columns: 6)

        XCTAssertEqual(split.hero, "w0")
        XCTAssertEqual(split.beside, ["w1", "w2"])
        XCTAssertEqual(split.rest.first, "w3")
    }
}

/// ORACLES:
///  • BEHAVIOUR — two animations were declared by the design and never called, so every transition
///    ran at the morph's pace. These assert the pairing, which is why the tokens exist as functions
///    of a destination rather than as a `switch` buried in a view body.
final class MotionPairingChecks: XCTestCase {

    func testTheArrivalAtFullBleedUsesItsOwnFasterSpring() {
        // Stage 4 travels much further than the capsule-to-card changes before it; at the morph's
        // 0.8 response the same distance reads as the screen sagging open.
        XCTAssertEqual(WPMotion.stageChange(toResult: true, reduceMotion: false),
                       WPMotion.reveal(reduceMotion: false))
        XCTAssertEqual(WPMotion.stageChange(toResult: false, reduceMotion: false),
                       WPMotion.morph(reduceMotion: false))
        XCTAssertNotEqual(WPMotion.reveal(reduceMotion: false), WPMotion.morph(reduceMotion: false),
                          "if these are ever the same, the pairing above is asserting nothing")
    }

    func testAToastFadesAndAResumeCardMorphs() {
        // A toast is a sentence appearing, not an object moving — springing it gives weight to
        // something that is gone in two seconds.
        XCTAssertEqual(WPMotion.shelfChange(toToast: true, reduceMotion: false), WPMotion.toastFade)
        XCTAssertEqual(WPMotion.shelfChange(toToast: false, reduceMotion: false),
                       WPMotion.morph(reduceMotion: false))
    }

    func testReduceMotionFlattensBothSpringsWithoutMergingTheirRoles() {
        // Both become the same short ease — correct, and the reason the assertions above must be
        // made with motion ON, or they would pass while the pairing was wrong.
        XCTAssertEqual(WPMotion.stageChange(toResult: true, reduceMotion: true),
                       WPMotion.reveal(reduceMotion: true))
        XCTAssertEqual(WPMotion.reveal(reduceMotion: true), WPMotion.morph(reduceMotion: true))
    }

    func testTheShelfSlotKnowsWhichOccupantItIs() {
        let job = JobManifest(kind: .generate, prompt: "a slate coastline under fog",
                              negativePrompt: "", seed: 7, steps: 28, guidanceScale: 7.5,
                              aspect: .phone,
                              models: [ModelUse(role: .generate, id: "sd15cn", fingerprint: "abc")],
                              stage: .refining(tile: 2, of: 9),
                              startedAt: Date(), updatedAt: Date())

        XCTAssertTrue(ShelfSlot.toast("Stopped").isToast)
        XCTAssertFalse(ShelfSlot.resume(job).isToast)
    }
}
