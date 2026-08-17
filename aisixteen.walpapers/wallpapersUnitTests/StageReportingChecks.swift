import XCTest
import GenerationKit
@testable import Wallpapers

/// How a two-stage job reports itself.
///
/// This exists because of a bug the user hit: a 28-step generation announced **"Step 37 of 37"**.
/// Stage 2's nine ESRGAN tiles were being added onto the diffusion step counter, so the app
/// contradicted the number the user had set in Advanced — and on a resumed run, an inflated total is
/// the first thing anyone would suspect of being the resume's fault.
///
/// Two properties, and the second is the one that is easy to break while fixing the first:
///
/// * the **text** names the unit it is counting and never exceeds the number that was configured;
/// * the **bar** never goes backwards, because a bar that fills and then drops reads as the job
///   starting over — which is the same lie in a different place.
@MainActor
final class StageReportingChecks: XCTestCase {

    private func running(_ steps: Int) -> CreateModel {
        let model = CreateModel(generator: MockImageGenerator(speed: .instant))
        model.prompt = "a slate coastline under fog"
        return model
    }

    // MARK: What the text says

    func testDiffusionCountsStepsAndStopsAtTheNumberThatWasSet() {
        let model = running(28)
        model.receiveForTest(.init(step: 9, totalSteps: 28, preview: nil, stage: .generating))
        XCTAssertEqual(model.stepText, "Step 9 of 28")

        model.receiveForTest(.init(step: 28, totalSteps: 28, preview: nil, stage: .generating))
        XCTAssertEqual(model.stepText, "Step 28 of 28", "the count must not run past what was set")
    }

    func testEnlargementCountsTilesAndSaysSo() {
        let model = running(28)
        model.receiveForTest(.init(step: 28, totalSteps: 28, preview: nil, stage: .generating))
        model.receiveForTest(.init(step: 3, totalSteps: 9, preview: nil, stage: .enlarging))

        XCTAssertEqual(model.stepText, "Enlarging… tile 3 of 9")
        XCTAssertFalse(model.stepText.contains("37"), "the two stages were added together again")
        XCTAssertFalse(model.stepText.hasPrefix("Step"), "tiles are not steps")
    }

    func testEnlargementIsStillTheSameRunningJob() {
        // Same glass object, still cancellable, still not finished. A separate phase must not read
        // as a separate job.
        let model = running(28)
        model.receiveForTest(.init(step: 1, totalSteps: 9, preview: nil, stage: .enlarging))
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.morphStage, .progress)
        XCTAssertFalse(model.canStart, "a running job must not offer to start another")
    }

    // MARK: What the bar does

    func testTheBarNeverGoesBackwardsAcrossTheStageBoundary() {
        let model = running(28)
        model.settings.upscaleEnabled = true
        var readings: [Double] = []
        for step in 1...28 {
            model.receiveForTest(.init(step: step, totalSteps: 28, preview: nil, stage: .generating))
            readings.append(model.fraction)
        }
        for tile in 1...9 {
            model.receiveForTest(.init(step: tile, totalSteps: 9, preview: nil, stage: .enlarging))
            readings.append(model.fraction)
        }

        for (earlier, later) in zip(readings, readings.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later, earlier,
                                        "the bar dropped from \(earlier) to \(later)")
        }
        XCTAssertEqual(readings.last ?? 0, 1.0, accuracy: 0.001, "enlargement must finish full")
    }

    func testDiffusionDoesNotFillTheWholeBarWhenEnlargementWillFollow() {
        // If it did, the drop at the stage boundary would be unavoidable.
        let model = running(28)
        model.settings.upscaleEnabled = true
        model.receiveForTest(.init(step: 28, totalSteps: 28, preview: nil, stage: .generating))
        XCTAssertEqual(model.fraction, CreateModel.diffusionShareOfTheBar, accuracy: 0.001)
        XCTAssertLessThan(model.fraction, 1.0)
    }

    func testDiffusionFillsTheWholeBarWhenItIsTheWholeJob() {
        // Enlargement off in Advanced: reserving the last fifth for a stage that never runs leaves
        // a finished wallpaper sitting at 82 %.
        let model = running(28)
        model.settings.upscaleEnabled = false
        model.receiveForTest(.init(step: 28, totalSteps: 28, preview: nil, stage: .generating))
        XCTAssertEqual(model.fraction, 1.0, accuracy: 0.001)
    }

    func testTheSplitReflectsMeasuredTimeNotTileCount() {
        // 25.4 s of diffusion against 5.4 s of enlargement, measured. Weighting the two stages by
        // their unit counts instead would park the bar at four-fifths for a stage that is a fifth of
        // the wait.
        XCTAssertEqual(CreateModel.diffusionShareOfTheBar, 25.4 / (25.4 + 5.4), accuracy: 0.02)
    }

    func testAStageWithNoWorkInItDoesNotStallTheBar() {
        let model = running(28)
        model.settings.upscaleEnabled = true
        model.receiveForTest(.init(step: 0, totalSteps: 0, preview: nil, stage: .enlarging))
        XCTAssertEqual(model.fraction, CreateModel.diffusionShareOfTheBar, accuracy: 0.001)
    }
}
