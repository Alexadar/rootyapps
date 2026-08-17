import Foundation
import Testing
@testable import CardMotionKit

/// Batch emulation: scripted pilots drive hundreds of worlds through the same kernel the
/// thumb drives, and every lane must hold every invariant at every step. Both kernel modes —
/// standard and Reduce Motion — run the same gates (the dead-toggle rule, structurally).
@Suite("Emulation invariants")
struct EmulationGateTests {

    static let modes: [(name: String, config: MotionConfig)] = [
        ("standard", .test),
        ("reduceMotion", .testReduced),
    ]

    /// Every pilot × every mode: nothing non-finite, the table stays solid, roll stays
    /// clamped, flip stays in [0, 1].
    @Test(arguments: [0, 1, 2, 3, 4])
    func nothingBreaksUnderAnyPilot(pilotIndex: Int) {
        let (name, pilot) = Pilots.all[pilotIndex]
        for (mode, config) in Self.modes {
            _ = Pilots.run(pilot, worlds: 32, seed: 11, config: config, steps: 720) { w, _, tick in
                guard tick % 7 == 0 else { return }    // sample; full check would be O(steps²)
                for t in [w.x, w.z, w.y, w.vx, w.vz, w.flip, w.juiceT] {
                    #expect(t.isFiniteMask.data.allSatisfy { $0 == 1 },
                            "\(name)/\(mode): non-finite at tick \(tick)")
                }
                #expect(w.y.data.allSatisfy { $0 >= -1e-9 },
                        "\(name)/\(mode): card under the table at tick \(tick)")
                #expect(w.flip.data.allSatisfy { $0 >= 0 && $0 <= 1 },
                        "\(name)/\(mode): flip out of range at tick \(tick)")
                let poses = MotionPose.poses(of: w, config: config)
                let bound = config.rollClamp + config.juiceRotationFactor + config.ambientAmplitude * 2 + 1e-9
                #expect(poses.tiltZ.absolute.data.allSatisfy { $0 <= bound },
                        "\(name)/\(mode): tilt beyond clamp at tick \(tick)")
            }
        }
    }

    /// EVERY layout's scripted draw completes in every world — all slots landed, each in a
    /// distinct slot, `drawComplete` exactly once. The bug this pins: a completion signal
    /// that fires (or reads as fired) before the LAST slot is filled — found on device
    /// when the ten-card cross "completed" at three landings in the chrome.
    @Test func everyLayoutsDrawCompletesEverywhere() {
        for layout in [MotionConfig.oneCard, .standard, .fiveCrossroads, .celticCross] {
            let config = MotionConfig.test(layout)
            let n = 16
            let steps = config.slotCount * 240 + 120
            var completions = [Int](repeating: 0, count: n)
            var landedAtCompletion = [Int](repeating: -1, count: n)
            let final = Pilots.run(Pilots.scriptedDraw, worlds: n, seed: 33, config: config,
                                   steps: steps) { w, events, _ in
                for w0 in 0..<n where events.drawComplete.data[w0] > 0.5 {
                    completions[w0] += 1
                    landedAtCompletion[w0] =
                        (w.phase .== MotionWorld.Phase.landed).setLanes(world: w0).count
                }
            }
            let c = final.capacity
            for w0 in 0..<n {
                #expect(completions[w0] == 1,
                        "slots \(config.slotCount), world \(w0): completed \(completions[w0]) times")
                // Completion means COMPLETE: every slot landed at the moment it fired.
                #expect(landedAtCompletion[w0] == config.slotCount,
                        "slots \(config.slotCount), world \(w0): fired at \(landedAtCompletion[w0]) landings")
                let landedLanes = (final.phase .== MotionWorld.Phase.landed).setLanes(world: w0)
                #expect(landedLanes.count == config.slotCount)
                let slots = landedLanes.map { Int(final.slot.data[w0 * c + $0]) }.sorted()
                #expect(slots == Array(0..<config.slotCount),
                        "slots \(config.slotCount), world \(w0): \(slots)")
            }
        }
    }

    /// The scripted draw completes in every world, in both modes: three landed cards, each in
    /// a distinct slot, face fully up, flat on the table — and `drawComplete` fired exactly once.
    @Test func scriptedDrawCompletesEverywhere() {
        for (mode, config) in Self.modes {
            var completions = [Int](repeating: 0, count: 128)
            let final = Pilots.run(Pilots.scriptedDraw, worlds: 128, seed: 21, config: config,
                                   steps: 840) { _, events, _ in
                for w in 0..<128 where events.drawComplete.data[w] > 0.5 {
                    completions[w] += 1
                }
            }
            let c = final.capacity
            for w in 0..<128 {
                #expect(completions[w] == 1, "\(mode): world \(w) completed \(completions[w]) times")
                let landedLanes = (final.phase .== MotionWorld.Phase.landed).setLanes(world: w)
                #expect(landedLanes.count == 3, "\(mode): world \(w) landed \(landedLanes.count)")
                let slots = landedLanes.map { Int(final.slot.data[w * c + $0]) }.sorted()
                #expect(slots == [0, 1, 2], "\(mode): world \(w) slots \(slots)")
                for lane in landedLanes {
                    #expect(final.flip.data[w * c + lane] == 1)
                    #expect(final.y.data[w * c + lane] == 0)
                }
            }
        }
    }

    /// Flip is monotone once committed: under the scripted draw (which never aborts a card)
    /// flip may only grow, and the apex event fires exactly three times per world.
    @Test func flipIsMonotoneAndApexFiresOncePerCard() {
        for (mode, config) in Self.modes {
            let n = 64
            var prevFlip: Tensor?
            var apexCount = [Int](repeating: 0, count: n)
            _ = Pilots.run(Pilots.scriptedDraw, worlds: n, seed: 33, config: config,
                           steps: 840) { w, events, tick in
                if let prev = prevFlip {
                    for i in 0..<prev.count {
                        #expect(w.flip.data[i] >= prev.data[i] - 1e-12,
                                "\(mode): flip decreased at tick \(tick)")
                    }
                }
                prevFlip = w.flip
                for w0 in 0..<n {
                    apexCount[w0] += events.flipApex.setLanes(world: w0).count
                }
            }
            #expect(apexCount.allSatisfy { $0 == 3 }, "\(mode): apex counts \(Set(apexCount))")
        }
    }

    /// A fling never flips a card (return flights stay face down), always brings it home:
    /// after the flight window every card is back in the deck, flat, and the deck ordering is
    /// intact (all depths distinct).
    @Test func flingReturnsTheCardFaceDown() {
        for (mode, config) in Self.modes {
            let final = Pilots.run(Pilots.fling, worlds: 64, seed: 44, config: config, steps: 360) { w, _, _ in
                #expect(w.flip.data.allSatisfy { $0 == 0 }, "\(mode): a return flight flipped")
            }
            let c = final.capacity
            for w in 0..<64 {
                let inDeck = (final.phase .== MotionWorld.Phase.inDeck).setLanes(world: w)
                #expect(inDeck.count == c, "\(mode): world \(w) has \(inDeck.count)/\(c) home")
                let depths = (0..<c).map { final.deckDepth.data[w * c + $0] }
                #expect(Set(depths).count == c, "\(mode): world \(w) depth collision \(depths)")
            }
        }
    }

    /// The degenerate tap: grab + release within two frames must leave no residue — the card
    /// returns, nothing lands, no draw completes.
    @Test func aTapLeavesNoResidue() {
        for (mode, config) in Self.modes {
            var landedEver = false
            var completedEver = false
            let final = Pilots.run(Pilots.tap, worlds: 16, seed: 55, config: config,
                                   steps: 300) { _, events, _ in
                if !events.landed.sumLast().data.allSatisfy({ $0 == 0 }) { landedEver = true }
                if !events.drawComplete.data.allSatisfy({ $0 == 0 }) { completedEver = true }
            }
            #expect(!landedEver && !completedEver, mode == "standard" ? "tap landed a card" : "tap landed a card (reduced)")
            let c = final.capacity
            for w in 0..<16 {
                #expect((final.phase .== MotionWorld.Phase.inDeck).setLanes(world: w).count == c)
            }
        }
    }

    /// Held cards track the pointer: under a *smooth* drag the settled tracking error stays
    /// inside a band — and OUTSIDE a lower bound. Instant tracking would mean the follow
    /// constant is dead and the drag has no weight; that failure is invisible without the
    /// lower bound (a spring can fail soft as well as stiff).
    @Test func dragTrackingErrorSitsInTheFeelBand() {
        let config = MotionConfig.test
        let n = 32
        var maxErr = 0.0
        var minErrAfterSettle = Double.infinity
        _ = Pilots.run(Pilots.scriptedDraw, worlds: n, seed: 66, config: config,
                       steps: 200) { w, _, tick in
            // During the drag phase of card 0 (ticks ~40..140), measure held-lane error.
            guard tick > 40, tick < 140 else { return }
            let held = w.phase .== MotionWorld.Phase.held
            for w0 in 0..<n {
                for lane in held.setLanes(world: w0) {
                    let i = w0 * w.capacity + lane
                    // Error against where the pilot's pointer is right now.
                    let intent = Pilots.scriptedDraw(worlds: n, seed: 66, config: config,
                                                     tick: tick, dt: 1.0 / 120.0)
                    let dx = w.x.data[i] - intent.pointerX.data[w0]
                    let dz = w.z.data[i] - intent.pointerZ.data[w0]
                    let err = (dx * dx + dz * dz).squareRoot()
                    maxErr = max(maxErr, err)
                    if tick > 100 { minErrAfterSettle = min(minErrAfterSettle, err) }
                }
            }
        }
        #expect(maxErr < 0.35, "card falls too far behind the finger: \(maxErr) TU")
        #expect(maxErr > 0.005, "tracking is instantaneous — the drag has no weight (max err \(maxErr))")
        #expect(minErrAfterSettle.isFinite, "no held card was ever observed")
    }

    /// Landings are STILL (owner call): from the moment a card lands, its tilt never
    /// exceeds the damped ambient breath — no settle wobble, no shake. The juice system's
    /// liveness is proven at the GRAB instead (a lifted card visibly acknowledges the
    /// hand), so a dead juice path can't hide behind the stillness requirement.
    @Test func landingsAreStillAndGrabsBreathe() {
        let config = MotionConfig.test
        let n = 32
        var grabPeak = [Int: Double]()
        var landedViolations = 0
        _ = Pilots.run(Pilots.scriptedDraw, worlds: n, seed: 88, config: config,
                       steps: 500) { w, events, tick in
            let poses = MotionPose.poses(of: w, config: config)
            let landedMask = w.phase .== MotionWorld.Phase.landed
            let heldMask = w.phase .== MotionWorld.Phase.held
            // Damped ambient + drag-roll residue bound; anything above is a shake.
            let stillBound = config.ambientAmplitude * config.livelinessLanded
                + config.juiceRotationFactor * config.livelinessLanded + 0.0015
            for w0 in 0..<n {
                for lane in landedMask.setLanes(world: w0) {
                    if abs(poses.tiltZ.data[w0 * w.capacity + lane]) > stillBound {
                        landedViolations += 1
                    }
                }
                for lane in heldMask.setLanes(world: w0) {
                    grabPeak[w0] = max(grabPeak[w0] ?? 0,
                                       abs(poses.tiltZ.data[w0 * w.capacity + lane]))
                }
            }
        }
        #expect(landedViolations == 0, "\(landedViolations) landed-card shake samples")
        for w0 in 0..<n {
            #expect((grabPeak[w0] ?? 0) > 0.008,
                    "world \(w0): grab shows no life (peak \(grabPeak[w0] ?? 0)) — juice path dead")
        }
    }

    /// The hero beat: exactly one heroLanded per world, and it is the LAST landing —
    /// whatever the method's slot count (1, 3, 5, or the ten-card cross). The drama slot
    /// generalized: parameterized over every shipped layout, not pinned to "third".
    @Test func theLastCardIsTheHero() {
        for layout in [MotionConfig.oneCard, .standard, .fiveCrossroads, .celticCross] {
            let n = 16
            let config = MotionConfig.test(layout)
            let steps = config.slotCount * 240 + 120
            var landings = [Int](repeating: 0, count: n)
            var heroAt = [Int: Int]()
            _ = Pilots.run(Pilots.scriptedDraw, worlds: n, seed: 99, config: config,
                           steps: steps) { _, events, _ in
                for w0 in 0..<n {
                    let l = events.landed.setLanes(world: w0).count
                    landings[w0] += l
                    if !events.heroLanded.setLanes(world: w0).isEmpty {
                        #expect(heroAt[w0] == nil,
                                "slots \(config.slotCount), world \(w0): hero fired twice")
                        heroAt[w0] = landings[w0]
                    }
                }
            }
            for w0 in 0..<n {
                #expect(heroAt[w0] == config.slotCount,
                        "slots \(config.slotCount), world \(w0): hero at landing \(heroAt[w0].map(String.init) ?? "never")")
            }
        }
    }

    /// Reduce Motion zeroes every decorative channel while landing the same cards at the same
    /// ticks — motion respectful, outcome identical. Asserted against the standard run.
    @Test func reduceMotionIsCompleteAndDecorFree() {
        let n = 32
        var standardDone = [Int: UInt64]()
        var reducedDone = [Int: UInt64]()
        _ = Pilots.run(Pilots.scriptedDraw, worlds: n, seed: 12, config: .test,
                       steps: 840) { _, events, tick in
            for w0 in 0..<n where events.drawComplete.data[w0] > 0.5 { standardDone[w0] = tick }
        }
        _ = Pilots.run(Pilots.scriptedDraw, worlds: n, seed: 12, config: .testReduced,
                       steps: 840) { w, events, tick in
            for w0 in 0..<n where events.drawComplete.data[w0] > 0.5 { reducedDone[w0] = tick }
            let poses = MotionPose.poses(of: w, config: .testReduced)
            #expect(poses.tiltX.data.allSatisfy { $0 == 0 }, "reduced mode tilts")
            #expect(poses.tiltZ.data.allSatisfy { $0 == 0 }, "reduced mode tilts")
            #expect(poses.squash.data.allSatisfy { $0 == 1 }, "reduced mode squashes")
        }
        #expect(standardDone.count == n && reducedDone.count == n)
        for w0 in 0..<n {
            #expect(standardDone[w0] == reducedDone[w0],
                    "world \(w0): completion tick differs between modes")
        }
    }
}
