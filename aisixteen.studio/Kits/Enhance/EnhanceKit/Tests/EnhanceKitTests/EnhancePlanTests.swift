import XCTest
@testable import EnhanceKit

/// The schedule, without waiting for it.
final class EnhancePlanTests: XCTestCase {

    func testTwentyStepsBecauseThatIsWhatTheProgressLabelSays() {
        // Board 1c: "Enhancing · step 9 of 20".
        XCTAssertEqual(EnhancePlan.standard.totalSteps, 20)
        XCTAssertEqual(EnhancePlan.standard.label(atStep: 9), "Enhancing · step 9 of 20")
    }

    func testProgressIsStepsAndTheOnlyFractionIsTheFill() {
        let progress = EnhanceProgress(step: 9, totalSteps: 20)
        XCTAssertEqual(progress.label, "Enhancing · step 9 of 20")
        XCTAssertFalse(progress.label.contains("%"), "a percentage here would be invented precision")
        XCTAssertEqual(progress.fillFraction, 0.45, accuracy: 1e-12)
    }

    func testTheFillFractionSurvivesADegeneratePlan() {
        XCTAssertEqual(EnhanceProgress(step: 3, totalSteps: 0).fillFraction, 0)
        XCTAssertEqual(EnhanceProgress(step: 40, totalSteps: 20).fillFraction, 1)
    }

    func testPreviewsEveryOtherStepAndAlwaysTheLastOne() {
        let plan = EnhancePlan.standard
        XCTAssertEqual(plan.previewSteps, [1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 20])
        XCTAssertTrue(plan.emitsPreview(atStep: plan.totalSteps),
                      "finishing without decoding the last preview leaves the user looking at the "
                      + "second-to-last picture while the capsule says it is done")
    }

    func testAnEvenCadenceStillEmitsTheFinalStep() {
        let plan = EnhancePlan(totalSteps: 20, previewCadence: 5)
        XCTAssertEqual(plan.previewSteps, [1, 6, 11, 16, 20])
    }

    func testStepsOutsideThePlanEmitNothing() {
        let plan = EnhancePlan.standard
        XCTAssertFalse(plan.emitsPreview(atStep: 0))
        XCTAssertFalse(plan.emitsPreview(atStep: -1))
        XCTAssertFalse(plan.emitsPreview(atStep: 21))
    }

    func testTheVeilLiftsFromTwentySixToZeroAndOnlyWhenAPictureArrives() {
        let plan = EnhancePlan.standard
        XCTAssertEqual(plan.veilBlur(atStep: 1), 26, accuracy: 1e-9)
        XCTAssertEqual(plan.veilBlur(atStep: plan.totalSteps), 0, accuracy: 1e-9)

        // Step 4 decodes nothing, so the veil must hold exactly where step 3 left it — a veil that
        // eased on a timer would be animating over a still frame.
        XCTAssertEqual(plan.veilBlur(atStep: 4), plan.veilBlur(atStep: 3), accuracy: 1e-12)
        XCTAssertLessThan(plan.veilBlur(atStep: 5), plan.veilBlur(atStep: 3))
    }

    func testTheVeilNeverGoesBackwards() {
        let plan = EnhancePlan.standard
        let blurs = (1...plan.totalSteps).map(plan.veilBlur(atStep:))
        for (earlier, later) in zip(blurs, blurs.dropFirst()) {
            XCTAssertLessThanOrEqual(later, earlier + 1e-12)
        }
    }

    func testTheVeilOpacityIsTheHandoffsTwentyTwoPercent() {
        XCTAssertEqual(EnhancePlan.standard.veilOpacity, 0.22, accuracy: 1e-12)
        XCTAssertEqual(EnhancePlan.standard.initialVeilBlur, 26, accuracy: 1e-12)
    }

    func testTheScheduleIsTheSameNumbersTheUIReads() {
        let schedule = EnhanceSchedule()
        XCTAssertEqual(schedule.steps.count, 20)
        XCTAssertEqual(schedule.steps.first?.index, 1)
        XCTAssertEqual(schedule.steps.last?.index, 20)
        XCTAssertEqual(schedule.steps.last?.veilBlur ?? 1, 0, accuracy: 1e-9)
        XCTAssertEqual(schedule.steps.filter(\.emitsPreview).map(\.index),
                       EnhancePlan.standard.previewSteps)
    }

    func testTheDeviceSpeedActuallyMakesYouWait() {
        // A mock that returned instantly would let a waiting-state design ship untested against the
        // only condition it was drawn for.
        var total = Duration.zero
        for _ in 0..<EnhancePlan.standard.totalSteps {
            total += EnhanceSpeed.device.stepDuration()
        }
        XCTAssertGreaterThan(total, Duration.seconds(10))
        XCTAssertLessThan(total, Duration.seconds(35))
        XCTAssertEqual(EnhanceSpeed.instant.stepDuration(), .zero)
    }
}
