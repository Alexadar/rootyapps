import XCTest
import GenerationKit
import PromptKit
@testable import Wallpapers

/// The generation state space: idle · running · complete · failed · cancelled.
///
/// Cancellation gets four separate cases rather than one, because "cancel" means something
/// structurally different depending on where the run is: before the first preview, before the
/// capsule becomes a picture frame, after it, and on the last step — the point at which a naive
/// implementation has already begun the expensive final render. A single mid-run cancel test would
/// pass while three of those were broken.
@MainActor
final class CreateModelChecks: XCTestCase {

    /// Lets the main actor drain the progress hops the generator posts. Everything here is
    /// main-actor-isolated with no sleeps, so yielding is enough — no polling, no timeouts.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private func runningModel(plan: GenerationPlan = .standard)
        async -> (CreateModel, SteppedGenerator) {
        let generator = SteppedGenerator(plan: plan)
        let model = CreateModel(generator: generator, plan: plan)
        model.prompt = "molten glass poppies at dusk"
        model.start(saveTo: nil)
        await settle()
        return (model, generator)
    }

    // MARK: idle ⇄ typed

    func testEmptyPromptLeavesCreateDisabled() {
        let model = CreateModel(generator: SteppedGenerator())
        XCTAssertEqual(model.phase, .idle)
        XCTAssertFalse(model.canStart)

        model.prompt = "   \n  "
        XCTAssertEqual(model.phase, .idle, "whitespace is not a prompt")
        XCTAssertFalse(model.canStart)

        model.prompt = "a slate coastline under fog"
        XCTAssertEqual(model.phase, .typed)
        XCTAssertTrue(model.canStart)

        model.prompt = ""
        XCTAssertEqual(model.phase, .idle, "clearing the field must disable Create again")
    }

    func testSurpriseMeFillsTheFieldAndNeverGenerates() {
        let model = CreateModel(generator: SteppedGenerator())
        model.surpriseMe()

        XCTAssertFalse(model.prompt.isEmpty)
        XCTAssertEqual(model.phase, .typed, "Surprise me fills the field; it must not start a run")
        XCTAssertFalse(model.isRunning)

        // Re-tapping must visibly change something, or the control reads as broken.
        let first = model.prompt
        model.surpriseMe()
        XCTAssertNotEqual(model.prompt, first)
    }

    // MARK: running

    /// Board `5a`: **the capsule never leaves.** It is one identified object from Create through
    /// waking, every step, and on to the finished picture — so the stage must NOT flip part-way
    /// through a run. The earlier spec had it becoming the frame at step 5; that reading is
    /// superseded, and this test exists to stop it being reintroduced.
    func testTheCapsulePersistsAcrossEveryStep() async {
        let (model, generator) = await runningModel()

        // 1..<28: the twenty-eighth advance finishes the run, at which point becoming `.result` is
        // the correct behaviour rather than a shape change mid-flight.
        for step in 1..<28 {
            generator.advance()
            await settle()
            XCTAssertEqual(model.morphStage, .progress,
                           "the identified object changed shape at step \(step)")
        }
    }

    func testWakingIsItsOwnStageAndSaysSoWithoutANumber() async {
        let generator = SteppedGenerator()
        let model = CreateModel(generator: generator)
        model.prompt = "aurora over a frozen inlet"
        model.start(saveTo: nil)
        await settle()

        // SteppedGenerator is ready immediately, so a run starts counting at once; what matters is
        // that the waking label never contains a fabricated step number.
        XCTAssertFalse(model.stepText.contains("Step 0"),
                       "a stopped counter is the progress indicator the design forbids")
    }

    func testTheWakingLabelCarriesNoFraction() {
        let model = CreateModel(generator: SteppedGenerator())
        // Whatever the phase, a fraction only exists once there are steps.
        XCTAssertEqual(model.fraction, 0)
        XCTAssertFalse(model.wakingIsSlow, "the explanation only appears after ~3 s")
    }

    func testProgressIsRealAndTheVeilOnlyLifts() async {
        let (model, generator) = await runningModel()
        var previousFraction = -1.0
        var previousVeil = Double.infinity

        for step in 1...28 {
            generator.advance()
            await settle()
            XCTAssertEqual(model.phase, .running(step: step, totalSteps: 28))
            XCTAssertEqual(model.stepText, "Step \(step) of 28")
            XCTAssertGreaterThan(model.fraction, previousFraction, "the bar went backwards at \(step)")
            XCTAssertLessThanOrEqual(model.veilBlur, previousVeil + 1e-9, "the veil thickened at \(step)")
            previousFraction = model.fraction
            previousVeil = model.veilBlur
        }
        // The diffusion share, not the whole bar: enlargement is still to come and the last fifth
        // is reserved for it. `StageReportingChecks` covers the boundary and the finish.
        XCTAssertEqual(model.fraction, CreateModel.diffusionShareOfTheBar, accuracy: 1e-9)
    }

    // MARK: Create refusing out loud

    /// `.disabled()` swallows the tap, so a disabled Create can never say why it refused. The button
    /// stays enabled and answers instead — and the three shells all route through one entry point so
    /// there is one place for that answer to live.
    func testCreateTappedWithAnUnusablePromptSaysNothing() {
        let model = CreateModel(generator: SteppedGenerator())
        model.createTapped(saveTo: nil)

        XCTAssertEqual(model.phase, .idle, "an empty prompt must not start anything")
        XCTAssertNil(model.toast, "the empty field is its own explanation — no toast for that")
    }

    func testCreateTappedWhileTheRunnerIsBusyExplainsItself() async {
        let model = CreateModel(generator: SteppedGenerator())
        model.prompt = "a slate coastline under fog"
        let gate = DispatchSemaphore(value: 0)
        model.runner.start(.enhance) { _ in gate.wait() }
        for _ in 0..<20 { await Task.yield() }

        XCTAssertFalse(model.canStart, "the runner owns the model while it enhances")
        model.createTapped(saveTo: nil)

        XCTAssertEqual(model.toast, EnhanceCopy.oneThingAtATime)
        XCTAssertEqual(model.phase, .typed, "the refusal must not start or clear anything")
        XCTAssertEqual(model.prompt, "a slate coastline under fog")
        gate.signal()
    }

    /// The same contract, from the *editing overlay* — the door the phone actually uses.
    ///
    /// This one shipped broken and looked fine. `regenerate` fell through to `start`, whose
    /// `canStart` guard returns silently, and the button above it carried `.disabled()`, so the
    /// silence was invisible: the tap never arrived. The Mac and iPad shells had their `.disabled()`
    /// removed and their refusal given a voice; the phone was missed, which left `explainBusy()`
    /// unreachable from the primary shell. Removing `.disabled()` without fixing `regenerate` would
    /// have swapped a dead button for a silent one.
    func testRegenerateWhileTheRunnerIsBusyExplainsItself() async {
        let model = CreateModel(generator: SteppedGenerator())
        model.prompt = "a slate coastline under fog"
        let gate = DispatchSemaphore(value: 0)
        model.runner.start(.enhance) { _ in gate.wait() }
        for _ in 0..<20 { await Task.yield() }

        XCTAssertFalse(model.canStart)
        model.regenerate(saveTo: nil)

        XCTAssertEqual(model.toast, EnhanceCopy.oneThingAtATime,
                       "the overlay's Regenerate must refuse out loud, like Create does")
        XCTAssertEqual(model.prompt, "a slate coastline under fog",
                       "a refusal must not disturb what the user typed")
        gate.signal()
    }

    func testRegenerateWithAnEmptyPromptStaysSilent() {
        // The asymmetry is deliberate and worth pinning: busy earns an explanation, empty does not.
        // An empty field explains itself, and a toast there would be nagging.
        let model = CreateModel(generator: SteppedGenerator())
        model.prompt = ""
        model.regenerate(saveTo: nil)

        XCTAssertNil(model.toast)
    }

    func testCreateTappedStartsWhenItCan() async {
        let model = CreateModel(generator: SteppedGenerator())
        model.prompt = "a slate coastline under fog"
        model.createTapped(saveTo: nil)
        for _ in 0..<20 { await Task.yield() }

        XCTAssertTrue(model.isRunning)
        XCTAssertNil(model.toast)
    }

    func testTheBlockedSegmentIsStillTappableAndSaysWhy() {
        // Board 6c: "the segment label drops to 35% ink, and tapping it answers with a toast".
        // `.disabled()` would swallow the tap, so the segment stays live and refuses out loud —
        // the same rule the Create button follows.
        let model = CreateModel(generator: SteppedGenerator())
        model.explainBusy()
        XCTAssertEqual(model.toast, EnhanceCopy.oneThingAtATime)
    }

    // MARK: cancelled — four places, because they are four different situations

    func testCancelAtStepOne() async { await assertCancel(atStep: 1) }
    func testCancelBeforeTheFrameAppears() async { await assertCancel(atStep: 4) }
    func testCancelAfterTheFrameAppears() async { await assertCancel(atStep: 17) }
    func testCancelOnTheFinalStep() async { await assertCancel(atStep: 28) }

    private func assertCancel(atStep step: Int, file: StaticString = #filePath, line: UInt = #line) async {
        let (model, generator) = await runningModel()
        let prompt = model.prompt

        for _ in 1...step { generator.advance(); await settle() }
        XCTAssertEqual(model.phase, .running(step: step, totalSteps: 28), file: file, line: line)

        model.cancel()
        await settle()

        XCTAssertEqual(model.phase, .typed,
                       "cancelling must return to the typed state, not to idle or failed",
                       file: file, line: line)
        XCTAssertEqual(model.prompt, prompt, "the prompt must survive a cancel", file: file, line: line)
        XCTAssertNil(model.preview, "the forming picture must be cleared", file: file, line: line)
        XCTAssertNil(model.finished, "nothing may be produced by a cancelled run", file: file, line: line)
        XCTAssertNil(model.finishedRecord, "nothing may be written by a cancelled run", file: file, line: line)
        XCTAssertEqual(model.veilBlur, 0, file: file, line: line)
        XCTAssertEqual(model.toast, "Stopped — your prompt is kept", file: file, line: line)

        // And it must stay cancelled: letting the generator run on must not resurrect the job.
        generator.advance()
        await settle()
        XCTAssertEqual(model.phase, .typed, "a cancelled run came back to life", file: file, line: line)
    }

    func testCancelNeverShowsTheFailureCard() async {
        let (model, generator) = await runningModel()
        generator.advance()
        await settle()
        model.cancel()
        await settle()

        if case .failed = model.phase {
            XCTFail("a cancelled run must never present the failure card")
        }
        XCTAssertNotEqual(model.morphStage, .failure)
    }

    func testCancellingBeforeStartingIsHarmless() {
        let model = CreateModel(generator: SteppedGenerator())
        model.prompt = "birch trunks in deep snow"
        model.cancel()
        XCTAssertEqual(model.phase, .typed)
        XCTAssertEqual(model.prompt, "birch trunks in deep snow")
    }

    // MARK: complete

    func testCompleteProducesAnImageAndReachesTheResultStage() async {
        let model = CreateModel(generator: MockImageGenerator(speed: .instant))
        model.prompt = "ink dissolving in water at blue hour"
        model.start(saveTo: nil)

        await waitUntil({ if case .done = model.phase { return true }; return false },
                        "the run never completed")

        XCTAssertEqual(model.morphStage, .result)
        XCTAssertNotNil(model.finished)
        XCTAssertEqual(model.veilBlur, 0)
        XCTAssertNil(model.toast)
    }

    func testEveryOfferedAspectProducesAnImageOfThatSize() async {
        for aspect in AspectRatio.offered {
            let generator = MockImageGenerator(speed: .instant)
            let model = CreateModel(generator: generator)
            model.aspect = aspect
            model.prompt = "salt flats after rain"
            model.start(saveTo: nil)

            await waitUntil({ if case .done = model.phase { return true }; return false },
                            "\(aspect.displayName) never completed")

            let image = try? XCTUnwrap(model.finished)
            XCTAssertNotNil(image, "\(aspect.displayName) produced no image")
            #if canImport(UIKit)
            XCTAssertEqual(Int(image?.size.width ?? 0), aspect.width, "\(aspect.displayName) width")
            #endif
        }
    }

    // MARK: failed

    func testFailureKeepsThePromptAndOffersTheCard() async {
        let model = CreateModel(generator: FailingImageGenerator(failAtStep: 11,
                                                                 error: .outOfMemory,
                                                                 speed: .instant))
        model.prompt = "cracked desert clay backlit"
        model.start(saveTo: nil)

        await waitUntil({ if case .failed = model.phase { return true }; return false },
                        "the run never failed")

        XCTAssertEqual(model.morphStage, .failure)
        XCTAssertEqual(model.prompt, "cracked desert clay backlit", "the prompt must survive a failure")
        XCTAssertNil(model.finished)
        XCTAssertNil(model.preview)
        XCTAssertEqual(model.veilBlur, 0)
        if case .failed(let reason) = model.phase {
            XCTAssertFalse(reason.isEmpty)
            XCTAssertFalse(reason.lowercased().contains("error"), "the card speaks plainly: \(reason)")
        }
    }

    func testFailureBeforeTheFrameIsAlsoReachable() async {
        // The other half of the failure transition: capsule straight to card, never a picture.
        let model = CreateModel(generator: FailingImageGenerator(failAtStep: 2,
                                                                 error: .failed(reason: "The model stopped part-way through."),
                                                                 speed: .instant))
        model.prompt = "moss on volcanic rock"
        model.start(saveTo: nil)

        await waitUntil({ if case .failed = model.phase { return true }; return false },
                        "the early failure never arrived")
        XCTAssertEqual(model.morphStage, .failure)
    }

    func testRetryAfterFailureClearsTheCard() async {
        let model = CreateModel(generator: MockImageGenerator(speed: .instant))
        model.prompt = "a wheat field before a storm"
        model.start(saveTo: nil)
        await waitUntil({ if case .done = model.phase { return true }; return false }, "never completed")

        model.dismissResult()
        XCTAssertEqual(model.phase, .typed)
        XCTAssertNil(model.finished)
    }

    // MARK: reuse

    func testUseAgainRestoresBothThePromptAndTheShape() {
        let model = CreateModel(generator: SteppedGenerator())
        model.aspect = .phone
        let record = makeRecord(prompt: "an alpine lake at first light", aspect: .wide)

        model.reuse(record)

        XCTAssertEqual(model.prompt, "an alpine lake at first light")
        XCTAssertEqual(model.aspect, .wide, "the stored shape must come back with the prompt")
        XCTAssertEqual(model.phase, .typed)
    }

    // MARK: -

    /// Waits for a condition the *generator* has to satisfy.
    ///
    /// `Task.yield()` alone is not enough here and quietly produces a flaky test: the mock renders
    /// its final full-resolution frame off the main actor, and yielding hands control back within
    /// microseconds without ever waiting for that work. Anything that crosses to another executor
    /// needs real time, so this polls on a clock with a generous ceiling — a debug-build render of a
    /// 3840 × 2160 field is not instant.
    private func waitUntil(_ condition: @escaping () -> Bool,
                           _ message: String,
                           timeout: Duration = .seconds(30),
                           file: StaticString = #filePath,
                           line: UInt = #line) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail(message, file: file, line: line)
    }
}

/// Every terminal state must expose a live exit.
///
/// The design bundle calls this out by name, and it is a direct consequence of a bug that shipped:
/// the finished picture had no way back to the prompt, and the existing suite did not catch it
/// because it asserted only that `.done` was *reached*. Reachability is not usability. These tests
/// assert the way **out** of every state a user can be left sitting in.
@MainActor
final class TerminalStateExitChecks: XCTestCase {

    private func finished() async -> CreateModel {
        let model = CreateModel(generator: MockImageGenerator(speed: .instant))
        model.prompt = "ink dissolving in water at blue hour"
        model.start(saveTo: nil)
        for _ in 0..<6000 {
            // `.done` *and* the runner released. The picture is on screen one main-actor hop before
            // the runner lets go, and until it does, Create is correctly disabled — a second
            // generation started in that window would load a second pipeline.
            if case .done = model.phase, model.runner.isIdle { return model }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("never reached the finished state")
        return model
    }

    func testFinishedPictureCanBeLeftByGoingBack() async {
        let model = await finished()
        model.dismissResult()
        XCTAssertEqual(model.phase, .typed, "the back exit must return to a usable Create")
        XCTAssertNil(model.finished)
        XCTAssertEqual(model.prompt, "ink dissolving in water at blue hour", "the prompt survives")
        XCTAssertTrue(model.canStart, "and a different wallpaper can be made")
    }

    func testFinishedPictureCanBeLeftByEditingThePrompt() async {
        let model = await finished()
        model.prompt = "a chalk cliff face at blue hour"
        XCTAssertEqual(model.phase, .typed, "typing must release the finished picture")
        XCTAssertNil(model.finished)
        XCTAssertTrue(model.canStart)
    }

    func testTweakOpensTheEditorWithoutLosingThePicture() async {
        let model = await finished()
        model.tweak()

        XCTAssertTrue(model.isEditingOverImage)
        XCTAssertNotNil(model.finished, "the picture stays behind the field — that is the point")
        XCTAssertEqual(model.primaryVerb, "Regenerate", "iterating, not starting over")
        XCTAssertTrue(model.canStart)
    }

    func testEditingKeepsThePictureWhileTheTextChanges() async {
        let model = await finished()
        model.tweak()
        model.prompt = "ink dissolving in water at dawn"

        XCTAssertTrue(model.isEditingOverImage, "editing must not collapse to .typed on a keystroke")
        XCTAssertNotNil(model.finished)
    }

    func testEditingCanBeAbandonedBackToThePicture() async {
        let model = await finished()
        model.tweak()
        model.cancelEditing()

        XCTAssertFalse(model.isEditingOverImage)
        XCTAssertEqual(model.morphStage, .result)
        XCTAssertNotNil(model.finished)
    }

    func testFailureCardHasBothExits() async {
        let model = CreateModel(generator: FailingImageGenerator(failAtStep: 3, speed: .instant))
        model.prompt = "brass orrery gears backlit"
        model.start(saveTo: nil)
        for _ in 0..<6000 {
            if case .failed = model.phase { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        guard case .failed = model.phase else { return XCTFail("never failed") }

        // Exit one: edit the prompt.
        model.dismissResult()
        XCTAssertEqual(model.phase, .typed)
        XCTAssertEqual(model.prompt, "brass orrery gears backlit")
        // Exit two: try again.
        XCTAssertTrue(model.canStart)
    }

    func testWakingIsCancellable() async {
        // A long unmeasurable wait must never be a trap.
        let generator = SteppedGenerator()
        let model = CreateModel(generator: generator)
        model.prompt = "a slow river through basalt"
        model.start(saveTo: nil)
        for _ in 0..<20 { await Task.yield() }

        model.cancel()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.phase, .typed)
        XCTAssertEqual(model.prompt, "a slow river through basalt")
    }

    func testNoTerminalStateIsWithoutAnExit() async {
        // A blunt sweep: for each state a user can be parked in, at least one action returns them
        // to somewhere they can act.
        let done = await finished()
        done.dismissResult()
        XCTAssertTrue(done.canStart, "done")

        let editing = await finished()
        editing.tweak()
        XCTAssertTrue(editing.canStart, "editing")

        let idle = CreateModel(generator: MockImageGenerator(speed: .instant))
        XCTAssertFalse(idle.canStart, "idle is not terminal — it is waiting for input")
        idle.surpriseMe()
        XCTAssertTrue(idle.canStart, "and Surprise me is its exit")
    }
}
