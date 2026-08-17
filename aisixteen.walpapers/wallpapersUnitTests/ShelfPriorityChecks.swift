import XCTest
import TaskKit
import GenerationKit
@testable import Wallpapers

/// ORACLES:
///  • INVARIANT — exactly one slot, or none. Two independent sources want the same strip of screen;
///    without an arbiter they stack, or both animate into one position and whichever renders last
///    wins.
///  • BEHAVIOUR — a resume outranks a toast, and a resume is never offered while the app is already
///    busy, because the runner permits one piece of model work and the user is holding it.
final class ShelfPriorityChecks: XCTestCase {

    private let job = JobManifest(kind: .generate,
                                  prompt: "a slate coastline under fog",
                                  negativePrompt: "",
                                  seed: 7, steps: 28, guidanceScale: 7.5, aspect: .phone,
                                  models: [ModelUse(role: .generate, id: "sd15cn",
                                                    fingerprint: "abc")],
                                  stage: .refining(tile: 2, of: 9),
                                  startedAt: Date(), updatedAt: Date())

    func testAnEmptyShelfShowsNothing() {
        XCTAssertNil(ShelfPriority.slot(resume: nil, toast: nil, isBusy: false))
    }

    func testResumeOutranksTheToast() {
        let slot = ShelfPriority.slot(resume: job, toast: "Stopped", isBusy: false)
        XCTAssertEqual(slot, .resume(job))
    }

    func testTheToastIsTheLastResort() {
        XCTAssertEqual(ShelfPriority.slot(resume: nil, toast: "Stopped", isBusy: false),
                       .toast("Stopped"))
    }

    func testABusyAppIsNeverOfferedAResume() {
        // The gate that used to live in RootView, now asserted rather than remembered: one job owns
        // the model, and an offer that cannot be honoured is worse than no offer.
        XCTAssertNil(ShelfPriority.slot(resume: job, toast: nil, isBusy: true))
        XCTAssertEqual(ShelfPriority.slot(resume: job, toast: "Stopped", isBusy: true),
                       .toast("Stopped"), "the toast still gets through")
    }

    func testTheChipCarriesRealUnits() {
        // Whatever else the chip abbreviates, the count survives.
        XCTAssertEqual(job.stage.chipSummary, "enhancing · 2 of 9")
    }
}
