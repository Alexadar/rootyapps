import XCTest
import CoreGraphics
@testable import EnhanceKit

/// The mock, driven at `.instant` so the whole state space costs microseconds.
final class MockEnhancerTests: XCTestCase {

    func testAPassReportsEveryStepInOrderAndNeverSkipsOne() async throws {
        let enhancer = MockPhotoEnhancer(speed: .instant)
        let recorder = ProgressRecorder()

        _ = try await enhancer.enhance(photo: makePhoto(), strength: 35, mask: nil, seed: 7) {
            recorder.record($0)
        }

        XCTAssertEqual(recorder.steps, Array(1...20))
        XCTAssertEqual(recorder.previewSteps, EnhancePlan.standard.previewSteps)
    }

    func testTheChosenSeedComesBackSoThePassCanBeReproduced() async throws {
        let enhancer = MockPhotoEnhancer(speed: .instant)
        let result = try await enhancer.enhance(photo: makePhoto(), strength: 55,
                                                mask: nil, seed: 0xC0FFEE) { _ in }
        XCTAssertEqual(result.seed, 0xC0FFEE)
        XCTAssertEqual(result.renderedStrength, 55)
        XCTAssertEqual(result.steps, 20)
    }

    func testAnAbsentSeedIsRolledAndIsNeverZero() async throws {
        let enhancer = MockPhotoEnhancer(speed: .instant)
        let result = try await enhancer.enhance(photo: makePhoto(), strength: 35,
                                                mask: nil, seed: nil) { _ in }
        XCTAssertNotEqual(result.seed, 0,
                          "zero must stay distinguishable from \"no seed\" in a stored recipe")
    }

    func testExplicitCancelStopsThePassAndReportsCancelledNotAFailure() async {
        let enhancer = MockPhotoEnhancer(speed: .fixed(.milliseconds(5)))
        let task = Task {
            _ = try await enhancer.enhance(photo: makePhoto(), strength: 35, mask: nil, seed: 1) { _ in }
        }
        try? await Task.sleep(for: .milliseconds(20))
        enhancer.cancel()

        await XCTAssertThrowsEnhanceError(.cancelled) { try await task.value }
    }

    func testTaskCancellationIsTheOtherDoorToTheSameOutcome() async {
        let enhancer = MockPhotoEnhancer(speed: .fixed(.milliseconds(5)))
        let task = Task {
            _ = try await enhancer.enhance(photo: makePhoto(), strength: 35, mask: nil, seed: 1) { _ in }
        }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()

        await XCTAssertThrowsEnhanceError(.cancelled) { try await task.value }
    }

    func testCancellingBeatsAScheduledFailure() async {
        // A user who stopped the pass was not shown an error and must not be, even if the run was
        // going to fail anyway.
        let enhancer = FailingPhotoEnhancer(failAtStep: 11,
                                            error: .outOfMemory,
                                            speed: .fixed(.milliseconds(5)))
        let task = Task {
            _ = try await enhancer.enhance(photo: makePhoto(), strength: 35, mask: nil, seed: 1) { _ in }
        }
        try? await Task.sleep(for: .milliseconds(15))
        enhancer.cancel()

        await XCTAssertThrowsEnhanceError(.cancelled) { try await task.value }
    }

    func testTheLateFailureHappensAfterThePictureIsAlreadyForming() async {
        let enhancer = FailingPhotoEnhancer(failAtStep: 11, error: .outOfMemory, speed: .instant)
        let recorder = ProgressRecorder()

        await XCTAssertThrowsEnhanceError(.outOfMemory) {
            _ = try await enhancer.enhance(photo: makePhoto(), strength: 35, mask: nil, seed: 1) {
                recorder.record($0)
            }
        }
        XCTAssertEqual(recorder.steps, Array(1...10))
        XCTAssertFalse(recorder.previewSteps.isEmpty,
                       "the interesting failure is one that has to unwind from a picture on screen")
    }

    func testTheEarlyFailureHappensBeforeAnyPictureExists() async {
        let enhancer = FailingPhotoEnhancer(failAtStep: 2,
                                            error: .failed(reason: "The model stopped part-way through."),
                                            speed: .instant)
        let recorder = ProgressRecorder()

        await XCTAssertThrowsEnhanceError(.failed(reason: "The model stopped part-way through.")) {
            _ = try await enhancer.enhance(photo: makePhoto(), strength: 35, mask: nil, seed: 1) {
                recorder.record($0)
            }
        }
        XCTAssertEqual(recorder.steps, [1],
                       "both halves of the failure transition have to be reachable")
    }

    func testCancelledCarriesNoSentenceForTheFailureCard() {
        XCTAssertNil(EnhanceError.cancelled.displayReason)
        XCTAssertNotNil(EnhanceError.outOfMemory.displayReason)
        XCTAssertEqual(EnhanceError.failed(reason: "no room").displayReason, "no room")
        XCTAssertTrue(EnhanceError.failureReassurance.contains("exactly as it was"))
    }

    // MARK: The pass itself

    func testThePassChangesThePhotoSoTheComparisonHasSomethingToShow() async throws {
        let enhancer = MockPhotoEnhancer(speed: .instant)
        let photo = makePhoto()
        let result = try await enhancer.enhance(photo: photo, strength: 80, mask: nil, seed: 1) { _ in }

        XCTAssertEqual(result.image.width, photo.width)
        XCTAssertEqual(result.image.height, photo.height)
        XCTAssertNotEqual(bytes(of: result.image), bytes(of: photo),
                          "a split handle over two identical pictures shows nothing")
    }

    func testStrengthActuallyMovesThePassSoTheFourDetentsAreJudgeable() async throws {
        let enhancer = MockPhotoEnhancer(speed: .instant)
        let photo = makePhoto()

        var previous: [UInt8]?
        var distances: [Int] = []
        let original = bytes(of: photo)

        for strength in [15.0, 35, 55, 80] {
            let result = try await enhancer.enhance(photo: photo, strength: strength,
                                                    mask: nil, seed: 1) { _ in }
            let rendered = bytes(of: result.image)
            if let previous { XCTAssertNotEqual(rendered, previous, "at \(strength)") }
            previous = rendered
            distances.append(distance(original, rendered))
        }

        XCTAssertEqual(distances.sorted(), distances,
                       "a louder detent must not produce a quieter picture: \(distances)")
        XCTAssertGreaterThan(distances.last!, distances.first!)
    }

    func testAPassAtZeroLeavesThePhotoAlone() async throws {
        // The UI never offers Enhance at zero, but if it ever did, the honest answer is "nothing".
        let enhancer = MockPhotoEnhancer(speed: .instant)
        let photo = makePhoto()
        let result = try await enhancer.enhance(photo: photo, strength: 0, mask: nil, seed: 1) { _ in }

        XCTAssertEqual(bytes(of: result.image), bytes(of: photo))
    }

    func testTheMaskIsIgnoredBecauseTheCompositeAppliesIt() async throws {
        // Masking here as well would apply it twice and darken the subject edge on every render.
        let enhancer = MockPhotoEnhancer(speed: .instant)
        let photo = makePhoto()

        let masked = try await enhancer.enhance(photo: photo, strength: 55,
                                                mask: makePhoto(), seed: 1) { _ in }
        let unmasked = try await enhancer.enhance(photo: photo, strength: 55,
                                                  mask: nil, seed: 1) { _ in }
        XCTAssertEqual(bytes(of: masked.image), bytes(of: unmasked.image))
    }

    func testPreviewsAreSmallerThanTheFinalImage() async throws {
        let enhancer = MockPhotoEnhancer(speed: .instant)
        let photo = makePhoto(width: 320, height: 320)
        let recorder = ProgressRecorder()

        _ = try await enhancer.enhance(photo: photo, strength: 55, mask: nil, seed: 1) {
            recorder.record($0)
        }
        let widths = recorder.previewWidths
        XCTAssertFalse(widths.isEmpty)
        for width in widths {
            XCTAssertLessThan(width, photo.width,
                              "a preview is a small image being upscaled, not a shrunk full frame")
        }
    }

    func testTheEffectCurveIsMonotonicAcrossTheWholeRail() {
        let amounts = stride(from: 0.0, through: 100.0, by: 5)
            .map(ProceduralEnhancement.effectAmount(strength:))
        for (earlier, later) in zip(amounts, amounts.dropFirst()) {
            XCTAssertLessThan(earlier, later)
        }
        XCTAssertEqual(ProceduralEnhancement.effectAmount(strength: 0), 0)
        XCTAssertEqual(ProceduralEnhancement.effectAmount(strength: 100), 1, accuracy: 1e-12)
    }
}
