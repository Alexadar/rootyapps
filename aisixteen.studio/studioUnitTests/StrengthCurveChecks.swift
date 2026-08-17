import XCTest
import RecipeKit
import EnhanceKit
import DiffusionRuntime
@testable import Studio

/// **The rail, swept.**
///
/// Not the four detents — the whole interval. `Scheduler.addNoise` indexes
/// `timeSteps[steps - Int(steps × strength)]`, so any denoise where `steps × strength` floors to
/// zero reads one past the end of the array and kills the process. A preset-table assertion goes
/// green with 16 of 100 reachable rail positions still fatal, which is how this nearly shipped: the
/// detents are labels on a continuous control, not the set of values a user can produce.
final class StrengthCurveChecks: XCTestCase {

    /// The step counts worth caring about: the shipped one and the alternative the owner is
    /// weighing.
    private let stepCounts = [12, 24]

    func testEveryReachableRailPositionRunsAtLeastOneStep() {
        for steps in stepCounts {
            // 0.1 granularity — finer than the slider can express, and still microseconds.
            for tick in 1...1000 {
                let rail = Double(tick) / 10
                guard let denoise = StrengthCurve.denoise(for: Strength(rail), steps: steps) else {
                    return XCTFail("rail \(rail) produced no denoise at all")
                }
                XCTAssertGreaterThan(
                    TiledControlNetPass.stepsPerTile(strength: denoise, steps: steps), 0,
                    "rail \(rail) → denoise \(denoise) runs nothing at steps \(steps) — this traps")
            }
        }
    }

    func testZeroIsTheOneRailPositionWithNoPassAtAll() {
        // Not a crash and not a floor: at zero the answer is the original, and running a model to
        // produce it would be theatre. The interface refuses Enhance there.
        XCTAssertNil(StrengthCurve.denoise(for: .zero))
    }

    func testTheFloorIsTheBaseSMinimumAndNotANumberWeChose() {
        for steps in stepCounts {
            let lowest = StrengthCurve.denoise(for: Strength(0.1), steps: steps)!
            XCTAssertGreaterThanOrEqual(lowest,
                                        TiledControlNetPass.minimumStrength(forSteps: steps),
                                        "at steps \(steps)")
        }
    }

    // MARK: The detents earn their descriptions

    func testEachDetentLandsOnItsMeasuredAnchor() {
        let expected: [(Detent, Float)] = [(.whisper, 0.10), (.subtle, 0.18),
                                           (.balanced, 0.28), (.strong, 0.42)]
        for (detent, denoise) in expected {
            XCTAssertEqual(StrengthCurve.denoise(for: detent.strength)!, denoise, accuracy: 1e-5,
                           "\(detent.name)")
        }
    }

    func testTheDefaultDetentStaysBelowTheFaceAlteringThreshold() {
        // Measured on the wallpaper app: 0.35 invents texture. Right for a generated picture, wrong
        // for a photo of a person. Subtle is the default, so this is the one that matters most.
        XCTAssertLessThan(StrengthCurve.denoise(for: Detent.subtle.strength)!, 0.20)
        XCTAssertLessThan(StrengthCurve.denoise(for: Detent.whisper.strength)!, 0.12,
                          "Whisper claims to be pixel-faithful")
    }

    func testTheRailNeverReachesArchitecturesTerritory() {
        // Above ~0.5 the pass stops enhancing a photo and starts replacing it.
        XCTAssertEqual(StrengthCurve.denoise(for: .full)!, StrengthCurve.maximumDenoise,
                       accuracy: 1e-6)
        for tick in 1...1000 {
            XCTAssertLessThanOrEqual(StrengthCurve.denoise(for: Strength(Double(tick) / 10))!,
                                     StrengthCurve.maximumDenoise)
        }
    }

    func testTheCurveIsMonotonicSoALouderDetentIsNeverGentler() {
        var previous: Float = 0
        for tick in 1...1000 {
            let denoise = StrengthCurve.denoise(for: Strength(Double(tick) / 10))!
            XCTAssertGreaterThanOrEqual(denoise, previous, "at rail \(Double(tick) / 10)")
            previous = denoise
        }
    }

    // MARK: What the dial can actually express

    func testTheDialResolvesToFarFewerPicturesThanItHasPositions() {
        // Documented, not lamented: the rail has at most `steps × cap` distinct outcomes, so a
        // hundred-position slider produces six pictures at twelve steps. If this number ever changes
        // silently, the interface is promising precision it cannot deliver.
        XCTAssertEqual(StrengthCurve.distinctOutcomes(forSteps: 12), 6)
        XCTAssertEqual(StrengthCurve.distinctOutcomes(forSteps: 24), 12)
    }

    func testTheShippedStepCountIsTheOneTheCurveWasSweptAgainst() {
        XCTAssertTrue(stepCounts.contains(StrengthCurve.steps),
                      "StrengthCurve.steps changed to \(StrengthCurve.steps) without a sweep")
    }
}

/// The translation from Studio's vocabulary to the pass's, without loading a model.
final class StudioEnhancerChecks: XCTestCase {

    func testTheWorkingSizePreservesAspectRatio() {
        // Squaring a photo silently is the bug nobody reports, because they assume the model did it.
        let (w, h) = StudioEnhancer.workingSize(width: 4032, height: 3024, side: 1024)
        XCTAssertEqual(w, 1024)
        XCTAssertEqual(h, 768)
        XCTAssertEqual(Double(w) / Double(h), 4032.0 / 3024.0, accuracy: 0.01)
    }

    func testASmallPhotoIsNotUpscaledOnTheWayIn() {
        let (w, h) = StudioEnhancer.workingSize(width: 640, height: 480, side: 1024)
        XCTAssertEqual(w, 640)
        XCTAssertEqual(h, 480)
    }

    func testTheTileCountVariesWithAspectAndIsNotTheWallpaperAppsNine() {
        // Nine is the wallpaper app's number for a square 1024 master. A photo is whatever shape it
        // is, and the count has to be computed rather than assumed anywhere in the interface.
        //
        // ⚠️ Counted **after** the downscale to `workingSide`, which is the size `run` actually
        // tiles. A 1024 × 1792 photo is often quoted as 12 tiles; that is its pre-downscale figure.
        // Fitting the long edge to 1024 makes it 585 × 1024, which is six.
        var settings = TiledControlNetPass.Settings()
        settings.steps = StrengthCurve.steps
        settings.strength = StrengthCurve.denoise(for: .subtle)!

        func tiles(width: Int, height: Int) -> Int {
            let (w, h) = StudioEnhancer.workingSize(width: width, height: height,
                                                    side: settings.workingSide)
            return TiledControlNetPass.plan(for: settings, width: w, height: h).totalTiles
        }

        let square = tiles(width: 1024, height: 1024)
        let portrait = tiles(width: 1024, height: 1792)
        let wide = tiles(width: 4032, height: 1024)

        XCTAssertEqual(square, 9, "the square master is the familiar nine")
        XCTAssertNotEqual(portrait, square, "a 9:16 photo must not tile like a square")
        XCTAssertNotEqual(wide, square)
        XCTAssertTrue([square, portrait, wide].allSatisfy { $0 > 0 })
    }

    func testEveryDetentProducesARunnablePlanForARealPhotoShape() {
        for detent in Detent.allCases {
            var settings = TiledControlNetPass.Settings()
            settings.steps = StrengthCurve.steps
            settings.strength = StrengthCurve.denoise(for: detent.strength)!

            let (w, h) = StudioEnhancer.workingSize(width: 4032, height: 3024,
                                                    side: settings.workingSide)
            let plan = TiledControlNetPass.plan(for: settings, width: w, height: h)
            XCTAssertTrue(plan.isRunnable, "\(detent.name) produces an empty schedule")
            XCTAssertGreaterThan(plan.totalSteps, 0, "\(detent.name)")
        }
    }

    func testThePromptIsAConstantAndTheAppHasNoWayToChangeIt() {
        // The Guideline 4.3 firewall: Studio enhances, Architecture reimagines. A prompt field here
        // is the clearest way to fail it.
        XCTAssertFalse(StudioEnhancer.conditioningPrompt.isEmpty)
        XCTAssertFalse(StudioEnhancer.negativePrompt.isEmpty)
    }

    func testTheFactoryFallsBackToTheMockWhenNoPackIsInstalled() async {
        // A machine without the 1.2 GB pack is a normal state, not a broken one.
        guard EnhancerFactory.resourcesURL() == nil else {
            return   // the pack IS installed here; the real path is covered by running it
        }
        let photo = await makePhoto()
        let enhancer = EnhancerFactory.make(strength: .subtle, photo: photo)
        XCTAssertTrue(enhancer is MockPhotoEnhancer)
        XCTAssertTrue(EnhancerFactory.isRunningMock)
    }
}

/// The app's own wiring against the real pack, when it happens to be on this machine.
///
/// Skips rather than fails when the pack is absent — a 1.2 GB artefact is not a build dependency,
/// and the app is designed to run the mock without it. No model is loaded here: `plan` is arithmetic,
/// so this costs milliseconds and still proves the translation layer resolves a real ControlNet.
final class RealPackWiringChecks: XCTestCase {

    /// Where the shared pack lives, relative to this file. Not an env var: this asserts the wiring,
    /// and a test that needed configuring to run is a test nobody runs.
    private var packURL: URL? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // studioUnitTests
            .deletingLastPathComponent()          // aisixteen.studio
            .deletingLastPathComponent()          // rootyapps
            .appendingPathComponent("aisixteen.models/models/coreml/sd15cn-3nets/Resources")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @MainActor
    func testTheRealEnhancerResolvesTheTileControlNetAndPlansARunnablePass() throws {
        guard let packURL else {
            throw XCTSkip("the model pack is not on this machine — the app runs the mock")
        }
        XCTAssertNotNil(ControlNetCatalog.name(of: .tile, at: packURL),
                        "the pack must carry the Tile net; Studio conditions on the tile itself")

        let photo = makePhoto(width: 768, height: 512)
        let enhancer = try XCTUnwrap(StudioEnhancer(resources: packURL,
                                                    strength: .subtle,
                                                    photoWidth: photo.width,
                                                    photoHeight: photo.height))
        XCTAssertGreaterThan(enhancer.plan.totalSteps, 0)
        XCTAssertEqual(enhancer.plan.veilBlur(atStep: enhancer.plan.totalSteps), 0, accuracy: 1e-9)
    }

    @MainActor
    func testAtZeroStrengthThereIsNoRealEnhancerToBuild() throws {
        guard let packURL else { throw XCTSkip("no pack") }
        let photo = makePhoto()
        XCTAssertNil(StudioEnhancer(resources: packURL, strength: .zero,
                                    photoWidth: photo.width, photoHeight: photo.height),
                     "at zero the answer is the original; running a model would be theatre")
    }
}
