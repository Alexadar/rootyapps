import Testing
@testable import CardMotionKit

/// The single most load-bearing property in the architecture (bigpinkcat's phrasing): if a
/// batch of one is not bit-identical to an element of a batch, the batching is a second
/// implementation and half the oracles cover nothing.
@Suite("Batch invariance")
struct BatchInvarianceTests {

    /// World 0 alone must equal world 0 among 64 — every lane, every channel, bit-for-bit
    /// (`==` on Tensor compares exact Double values).
    @Test func worldZeroSoloEqualsWorldZeroInABatch() {
        let steps = 480
        let solo = Pilots.run(Pilots.scriptedDraw, worlds: 1, seed: 9, config: .test, steps: steps)
        let batch = Pilots.run(Pilots.scriptedDraw, worlds: 64, seed: 9, config: .test, steps: steps)

        let c = solo.capacity
        for (name, a, b) in [("x", solo.x, batch.x), ("z", solo.z, batch.z),
                             ("y", solo.y, batch.y), ("vx", solo.vx, batch.vx),
                             ("phase", solo.phase, batch.phase), ("flip", solo.flip, batch.flip),
                             ("slot", solo.slot, batch.slot),
                             ("deckDepth", solo.deckDepth, batch.deckDepth),
                             ("juiceAmp", solo.juiceAmp, batch.juiceAmp),
                             ("juiceT", solo.juiceT, batch.juiceT)] {
            for lane in 0..<c {
                #expect(a.data[lane] == b.data[lane],
                        "\(name)[lane \(lane)]: solo \(a.data[lane]) vs batched \(b.data[lane])")
            }
        }
    }

    /// …while the 64 must still produce many distinct outcomes, or the batch is 64 copies of
    /// one run and the previous test proves nothing.
    @Test func aBatchIsReallyABatch() {
        // Sampled MID-DRAG, not at the end: landings snap to exact slot centres by design, so
        // final states legitimately converge — divergence lives in the paths.
        var signatures = Set<String>()
        _ = Pilots.run(Pilots.scriptedDraw, worlds: 64, seed: 9, config: .test, steps: 120) { w, _, tick in
            guard tick == 110 else { return }
            let c = w.capacity
            for w0 in 0..<64 {
                let sig = (0..<c).map { String(format: "%.9f", w.x.data[w0 * c + $0]) }.joined()
                signatures.insert(sig)
            }
        }
        #expect(signatures.count > 10, "only \(signatures.count) distinct outcomes across 64 worlds")
    }

    /// Same seed, same pilot → byte-identical state. Twice.
    @Test func sameSeedReproducesTheRunExactly() {
        let a = Pilots.run(Pilots.jerkyDrag, worlds: 8, seed: 77, config: .test, steps: 240)
        let b = Pilots.run(Pilots.jerkyDrag, worlds: 8, seed: 77, config: .test, steps: 240)
        #expect(a.x == b.x && a.z == b.z && a.y == b.y)
        #expect(a.phase == b.phase && a.flip == b.flip && a.juiceT == b.juiceT)
    }

    /// The same kernel at N = 4096: one short smoke pass proving the batch axis carries —
    /// nothing per-world leaks, nothing goes non-finite, outcomes stay diverse.
    @Test func fourThousandWorldsRunTheSameKernel() {
        let final = Pilots.run(Pilots.scriptedDraw, worlds: 4096, seed: 3, config: .test,
                               steps: 48)
        #expect(final.x.isFiniteMask.sumLast().data.allSatisfy { $0 == Double(final.capacity) })
        #expect(final.y.data.allSatisfy { $0 >= -1e-9 })
        // World 4095 got a different jitter than world 0 — the batch is not a broadcast.
        let c = final.capacity
        let first = (0..<c).map { final.x.data[$0] }
        let last = (0..<c).map { final.x.data[4095 * c + $0] }
        #expect(first != last)
    }

    /// Pose derivation is a pure function of the state: deriving twice changes nothing and
    /// returns the same frame.
    @Test func posesArePure() {
        let world = Pilots.run(Pilots.scriptedDraw, worlds: 4, seed: 5, config: .test, steps: 200)
        let before = world.x
        let p1 = MotionPose.poses(of: world, config: .test)
        let p2 = MotionPose.poses(of: world, config: .test)
        #expect(world.x == before)
        #expect(p1.tiltZ == p2.tiltZ && p1.scale == p2.scale && p1.flipAngle == p2.flipAngle)
    }
}
