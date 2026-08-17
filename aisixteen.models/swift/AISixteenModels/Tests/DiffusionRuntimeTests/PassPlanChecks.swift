import XCTest
import CoreGraphics
@testable import DiffusionRuntime

/// ORACLES:
///  • INVARIANT — the total a caller can compute **before** the pass is the total the loop runs.
///    They are one expression, so this asserts they cannot be edited apart.
///  • BOUNDARY — `strength × steps` flooring to zero is not a gentle no-op. It walks one past the end
///    of the timestep array inside Apple's scheduler, which traps. The pass must refuse it, and must
///    refuse it *before* loading 870 MB of models.
final class PassPlanChecks: XCTestCase {

    // MARK: The total was never actually unknowable

    func testTheWholePlanIsArithmeticWithNoModelAndNoDisk() {
        // The whole point. Both consuming apps designed around a total that could not exist until
        // the first step landed; neither input needs anything but numbers.
        let settings = TiledControlNetPass.Settings(strength: 0.35, steps: 12)
        let plan = TiledControlNetPass.plan(for: settings, width: 1024, height: 1024)

        XCTAssertEqual(plan.totalTiles, 9)
        XCTAssertEqual(plan.stepsPerTile, 4, "a nominal 12 at strength 0.35 runs four")
        XCTAssertEqual(plan.totalSteps, 36)
    }

    func testThePlannedTileCountIsTheGridTheLoopWalks() {
        // Not a restatement: `plan` could plausibly have divided spans instead of reusing `grid`,
        // and the pull-back of the final origin makes those two disagree at exactly the awkward
        // sizes. 1536 is one such — even division says 3, the real grid says 4.
        for (w, h) in [(1024, 1024), (1536, 1024), (512, 512), (2048, 1152), (900, 700)] {
            let settings = TiledControlNetPass.Settings()
            let planned = TiledControlNetPass.plan(for: settings, width: w, height: h).totalTiles
            let actual = TiledControlNetPass.grid(width: w, height: h,
                                                 tile: settings.tile, overlap: settings.overlap).count
            XCTAssertEqual(planned, actual, "plan and grid disagree at \(w)×\(h)")
        }
    }

    func testThePlannedStepCountIsWhatTheSchedulerReducesTo() {
        // Pinned measurements, not a formula copied from the implementation. If Apple changes
        // `calculateTimesteps`, these change and the apps that print them must be told.
        let measured: [(strength: Float, steps: Int, expected: Int)] = [
            (0.18, 12, 2), (0.28, 12, 3), (0.35, 12, 4), (0.42, 12, 5), (0.50, 32, 16),
        ]
        for case let (strength, steps, expected) in measured {
            let settings = TiledControlNetPass.Settings(strength: strength, steps: steps)
            let plan = TiledControlNetPass.plan(for: settings, width: 1024, height: 1024)
            XCTAssertEqual(plan.stepsPerTile, expected,
                           "strength \(strength) of a nominal \(steps)")
            XCTAssertLessThan(plan.stepsPerTile, steps,
                              "image-to-image always runs fewer than nominal — a caller printing "
                              + "the nominal count would show a bar that stalls then jumps")
        }
    }

    // MARK: The cliff at strength × steps < 1

    func testAStrengthTooLowForTheStepCountIsRefusedRatherThanRun() {
        // The gentlest preset is the one that breaks, which is the wrong way round for discovering
        // it: 0.08 × 12 floors to zero, so the schedule is empty and `addNoise` indexes one past
        // the end of `timeSteps`.
        let doomed = TiledControlNetPass.Settings(strength: 0.08, steps: 12)
        XCTAssertFalse(TiledControlNetPass.plan(for: doomed, width: 1024, height: 1024).isRunnable)

        // ...and the same strength is perfectly fine at a higher step count. The invalid thing is
        // the *pair*, which is why the error names both.
        let fine = TiledControlNetPass.Settings(strength: 0.08, steps: 20)
        let plan = TiledControlNetPass.plan(for: fine, width: 1024, height: 1024)
        XCTAssertTrue(plan.isRunnable)
        XCTAssertEqual(plan.stepsPerTile, 1)
    }

    func testMinimumStrengthActuallyClearsTheCliffAtEveryStepCount() {
        // The boundary is a floating multiply, so the safe value is asserted by construction rather
        // than reasoned about: for every step count an app might pick, the advertised minimum must
        // run at least one step, and a hair under it must not.
        for steps in 1...64 {
            let minimum = TiledControlNetPass.minimumStrength(forSteps: steps)
            let atMinimum = TiledControlNetPass.Settings(strength: minimum, steps: steps)
            XCTAssertTrue(TiledControlNetPass.plan(for: atMinimum, width: 512, height: 512).isRunnable,
                          "the advertised minimum \(minimum) does not run at \(steps) steps")

            if steps > 1 {
                let below = TiledControlNetPass.Settings(strength: minimum.nextDown.nextDown,
                                                         steps: steps)
                XCTAssertFalse(TiledControlNetPass.plan(for: below, width: 512, height: 512).isRunnable,
                               "the minimum is not tight at \(steps) steps — anything below it "
                               + "should fail, or the guard is guarding nothing")
            }
        }
    }

    func testTheRefusalHappensBeforeAnyModelIsTouched() throws {
        // The negative verification that matters. This URL holds no models at all, so if the guard
        // were placed after the pipeline load — the natural place to put it — this would throw a
        // file error instead, and the test would catch that rather than pass vacuously.
        let nowhere = URL(fileURLWithPath: "/var/empty/no-such-pack")
        let pass = TiledControlNetPass(resourcesAt: nowhere, controlNet: "NotThere")
        let source = try XCTUnwrap(Self.image(side: 1024))

        XCTAssertThrowsError(try pass.run(source,
                                          request: .init(prompt: "x", seed: 1,
                                                         settings: .init(strength: 0.08, steps: 12)),
                                          conditioning: .theTileItself)) { error in
            guard case TiledControlNetPass.RuntimeError
                .strengthTooLowForStepCount(let strength, let steps, let minimum) = error else {
                return XCTFail("expected the strength refusal, got \(error)")
            }
            XCTAssertEqual(strength, 0.08)
            XCTAssertEqual(steps, 12)
            XCTAssertGreaterThan(minimum, strength, "the fix offered must actually be a fix")
        }
    }

    // MARK: A continuous control, which a preset table cannot protect

    func testEnumeratingPresetsWouldNotHaveCaughtThis() {
        // The point of the whole clamp, asserted rather than argued. Four named detents corrected to
        // safe values, and the rail they sit on still full of positions that trap — which is the
        // original defect's shape: valid where someone enumerated, fatal where they didn't.
        let detents: [Float] = [0.10, 0.18, 0.28, 0.42]
        for detent in detents {
            XCTAssertTrue(TiledControlNetPass.plan(for: .init(strength: detent, steps: 12),
                                                   width: 1024, height: 1024).isRunnable)
        }

        let reachable = (0...1000).map { Float($0) / 1000.0 }
        let trapping = reachable.filter {
            !TiledControlNetPass.plan(for: .init(strength: $0, steps: 12),
                                      width: 1024, height: 1024).isRunnable
        }
        XCTAssertEqual(trapping.count, 84,
                       "every named detent passes and 84 reachable positions still trap — a table "
                       + "assertion goes green and the crash ships")
    }

    func testTheClampMakesEveryReachablePositionRunnable() {
        // The sweep an app with a slider should own, proven here so it does not have to be rewritten
        // — and correct at every step count, not just the one that exposed the bug.
        for steps in [8, 12, 20, 24, 32, 50] {
            for i in 0...1000 {
                let requested = Float(i) / 1000.0
                let safe = TiledControlNetPass.clamped(strength: requested, forSteps: steps)
                XCTAssertTrue(TiledControlNetPass.plan(for: .init(strength: safe, steps: steps),
                                                       width: 512, height: 512).isRunnable,
                              "rail \(requested) clamped to \(safe) still runs nothing at \(steps)")
            }
        }
    }

    func testTheClampOnlyEverRaisesAndNeverMovesASafeValue() {
        // A clamp that quietly rewrote settings an app deliberately chose would be worse than the
        // crash: the picture would differ from the request with nothing reporting why.
        for steps in [12, 24, 32] {
            for i in 0...1000 {
                let requested = Float(i) / 1000.0
                let safe = TiledControlNetPass.clamped(strength: requested, forSteps: steps)
                XCTAssertGreaterThanOrEqual(safe, requested, "the clamp must never lower strength")
                if TiledControlNetPass.plan(for: .init(strength: requested, steps: steps),
                                            width: 512, height: 512).isRunnable {
                    XCTAssertEqual(safe, requested,
                                   "an already-valid \(requested) was moved at \(steps) steps")
                }
            }
        }
    }

    func testARailHasAtMostAsManyOutcomesAsItHasSteps() {
        // The dead zone the clamp exposes but does not fix, pinned as a measurement so nobody
        // rediscovers it as "the slider is broken at the bottom". A thousand rail positions cannot
        // buy more than `steps` distinguishable results.
        for steps in [12, 24, 32] {
            let outcomes = Set((0...1000).map {
                TiledControlNetPass.plan(for: .init(strength: Float($0) / 1000.0, steps: steps),
                                         width: 1024, height: 1024).stepsPerTile
            })
            XCTAssertEqual(outcomes.count, steps + 1,
                           "at \(steps) nominal steps a continuous rail yields \(steps) usable "
                           + "outcomes plus the unrunnable one — resolution beyond that is a lie")
        }
    }

    func testCappingTheRangeCostsResolutionInProportion() {
        // The correction to the line above: "at most `steps`" holds over the full range and flatters
        // any app that caps its own. An enhance app capping at 0.5 gets HALF the resolution, which
        // is a different conversation with its designer than the one the old note implied.
        XCTAssertEqual(TiledControlNetPass.distinctOutcomes(forSteps: 12, strengthFrom: 0, to: 1), 12)
        XCTAssertEqual(TiledControlNetPass.distinctOutcomes(forSteps: 12, strengthFrom: 0, to: 0.5), 6,
                       "a hundred-position dial capped at 0.5 offers six pictures")
        XCTAssertEqual(TiledControlNetPass.distinctOutcomes(forSteps: 24, strengthFrom: 0, to: 0.5), 12,
                       "doubling steps buys back what the cap cost, at roughly double the wait")
    }

    func testTheOutcomeCountMatchesAnExhaustiveSweepOfTheRail() {
        // `distinctOutcomes` reads only the endpoints. That is sound only while `stepsPerTile` is
        // monotonic in strength — so rather than assert monotonicity abstractly, this walks every
        // reachable position and counts what a user could actually reach.
        for steps in [8, 12, 24, 32] {
            for cap in [Float(0.25), 0.5, 0.75, 1.0] {
                // 400 samples, not 1000: `plan` builds the scheduler's beta tables on every call
                // (~0.7 ms in Debug), and the narrowest band is the top one, which `i == samples`
                // hits exactly. Density beyond that buys nothing but seconds.
                let samples = 400
                let swept = Set((0...samples).map { i -> Int in
                    let requested = Float(i) / Float(samples) * cap
                    return TiledControlNetPass.stepsPerTile(
                        strength: TiledControlNetPass.clamped(strength: requested, forSteps: steps),
                        steps: steps)
                })
                XCTAssertEqual(TiledControlNetPass.distinctOutcomes(forSteps: steps,
                                                                    strengthFrom: 0, to: cap),
                               swept.count,
                               "endpoint arithmetic disagrees with the rail at \(steps) steps, "
                               + "cap \(cap) — stepsPerTile is not monotonic and the shortcut is void")
            }
        }
    }

    func testStepsPerTileNeverFallsAsStrengthRises() {
        // The property the shortcut rests on, asserted directly as well: if a higher strength ever
        // ran fewer steps, both `distinctOutcomes` and every progress bar built on it would be wrong.
        for steps in [12, 24, 32] {
            var previous = 0
            for i in 0...1000 {
                let current = TiledControlNetPass.stepsPerTile(strength: Float(i) / 1000.0,
                                                               steps: steps)
                XCTAssertGreaterThanOrEqual(current, previous,
                                            "strength \(Float(i) / 1000.0) ran fewer steps than the "
                                            + "value below it at \(steps) nominal")
                previous = current
            }
        }
    }

    // MARK: Plan and Progress agree

    func testProgressNeverExceedsTheTotalThePlanAdvertised() {
        // The contract an interface depends on: a bar sized from `plan` before the run must not be
        // overrun by the `steps:` callback during it.
        let settings = TiledControlNetPass.Settings(strength: 0.35, steps: 12)
        let plan = TiledControlNetPass.plan(for: settings, width: 1024, height: 1024)

        for tile in 0..<plan.totalTiles {
            for step in 1...plan.stepsPerTile {
                let progress = TiledControlNetPass.Progress(tile: tile, totalTiles: plan.totalTiles,
                                                            stepInTile: step,
                                                            stepsPerTile: plan.stepsPerTile)
                XCTAssertEqual(progress.totalSteps, plan.totalSteps)
                XCTAssertLessThanOrEqual(progress.step, plan.totalSteps)
            }
        }
    }

    private static func image(side: Int) -> CGImage? {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setFillColor(CGColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return context?.makeImage()
    }
}
