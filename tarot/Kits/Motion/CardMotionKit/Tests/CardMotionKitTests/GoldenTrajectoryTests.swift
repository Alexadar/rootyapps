import Foundation
import Testing
@testable import CardMotionKit

/// Golden trajectory hashes (bigpinkcat's DeterminismGoldenTests pattern): FNV-1a over the
/// raw IEEE-754 bit patterns of every pose channel at every step. The hash catches silent
/// numeric drift — a refactor that "should be equivalent", a changed evaluation order — which
/// physics assertions cannot see. Each golden is **paired with a physical invariant** in the
/// same test, because bits and correctness are orthogonal: a hash can match a wrong world.
///
/// **Do NOT update a golden to make a failing test pass.** A golden is recorded, not
/// authored: these were re-recorded 2026-08-16 twice, both deliberate tunes: the slot-layout retune (slotX ±0.62 → ±0.52, portrait clipping) the ambient-wobble calm-down (owner: "cards shaking"), the flip-clearance lift, and the pose-layer tilt clearance (device-observed landing-wobble clipping; reduced-mode golden unchanged since its tilts are zero), the scale-juice removal (owner: "jelly"), the deck move (0.40 → 0.47, label clearance), and the liveliness stillness law (landed cards perfectly still; one which-chain gates all decor — reduced mode only moved with the deck, proving the law is decor-only); recorded on this machine (macOS/arm64,
/// where the Kit's `swift test` runs). If one fails, the kernel's arithmetic changed — find
/// out why first. Deliberate feel-tuning changes constants in `MotionConfig`; when tuning is
/// the *intended* change, re-record and say so in the commit.
@Suite("Golden trajectories")
struct GoldenTrajectoryTests {

    struct FNV1a {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        mutating func fold(_ value: Double) {
            // Canonicalize: all NaNs one pattern, -0.0 folds to +0.0.
            let bits = value.isNaN ? UInt64(0x7ff8_0000_0000_0000)
                                   : (value == 0 ? 0 : value.bitPattern)
            var b = bits
            for _ in 0..<8 {
                hash ^= b & 0xFF
                hash = hash &* 0x0000_0100_0000_01B3
                b >>= 8
            }
        }
        mutating func fold(_ tensor: Tensor) {
            for v in tensor.data { fold(v) }
        }
    }

    static func trajectoryHash(pilot: @escaping Pilots.Pilot, worlds: Int, seed: UInt64,
                               config: MotionConfig, steps: Int) -> (hash: UInt64, final: MotionWorld) {
        var hasher = FNV1a()
        let final = Pilots.run(pilot, worlds: worlds, seed: seed, config: config,
                               steps: steps) { w, _, _ in
            let p = MotionPose.poses(of: w, config: config)
            hasher.fold(p.x); hasher.fold(p.z); hasher.fold(p.y)
            hasher.fold(p.tiltX); hasher.fold(p.tiltZ)
            hasher.fold(p.flipAngle); hasher.fold(p.squash); hasher.fold(p.scale)
        }
        return (hasher.hash, final)
    }

    @Test func scriptedDrawGolden() {
        let (hash, final) = Self.trajectoryHash(pilot: Pilots.scriptedDraw, worlds: 2, seed: 424242,
                                                config: .test, steps: 780)
        // Paired invariant: the hashed run really is a completed draw.
        for w in 0..<2 {
            #expect((final.phase .== MotionWorld.Phase.landed).setLanes(world: w).count == 3)
        }
        #expect(hash == 0x015b_943e_e2fc_5089,
                "recorded golden mismatch: 0x\(String(hash, radix: 16))")
    }

    @Test func flingGolden() {
        let (hash, final) = Self.trajectoryHash(pilot: Pilots.fling, worlds: 2, seed: 313131,
                                                config: .test, steps: 300)
        for w in 0..<2 {
            #expect((final.phase .== MotionWorld.Phase.inDeck).setLanes(world: w).count == final.capacity)
        }
        #expect(hash == 0x314b_011b_2bf2_3ee8,
                "recorded golden mismatch: 0x\(String(hash, radix: 16))")
    }

    /// The ten-card cross golden — the one layout that exercises the yaw channel, the
    /// slot rest lift, the shared-centre tie-break and scaled cards, all in one recording.
    /// Recorded 2026-08-17 with the channel list below INCLUDING yaw (the older goldens
    /// deliberately do not fold yaw: their recordings predate the channel, and their yaw
    /// is identically zero — proven by the layout tests). Re-recorded once the same day:
    /// the cross's foundation/crown/passes/approaches arms were permuted onto their
    /// traditional sides (caught reading the rendered German frame) — a deliberate,
    /// stated layout change.
    @Test func celticCrossGolden() {
        var hasher = FNV1a()
        let config = MotionConfig.test(MotionConfig.celticCross)
        let final = Pilots.run(Pilots.scriptedDraw, worlds: 2, seed: 616161,
                               config: config, steps: 2520) { w, _, _ in
            let p = MotionPose.poses(of: w, config: config)
            hasher.fold(p.x); hasher.fold(p.z); hasher.fold(p.y)
            hasher.fold(p.tiltX); hasher.fold(p.tiltZ)
            hasher.fold(p.flipAngle); hasher.fold(p.yaw)
            hasher.fold(p.squash); hasher.fold(p.scale)
        }
        // Paired invariant: all ten slots really filled, in both worlds.
        for w in 0..<2 {
            #expect((final.phase .== MotionWorld.Phase.landed).setLanes(world: w).count == 10)
        }
        #expect(hasher.hash == 0x564e_898d_5564_bc6d,
                "recorded golden mismatch: 0x\(String(hasher.hash, radix: 16))")
    }

    @Test func reducedModeGolden() {
        let (hash, final) = Self.trajectoryHash(pilot: Pilots.scriptedDraw, worlds: 2, seed: 424242,
                                                config: .testReduced, steps: 780)
        for w in 0..<2 {
            #expect((final.phase .== MotionWorld.Phase.landed).setLanes(world: w).count == 3)
        }
        #expect(hash == 0xb383_cd67_1907_1b25,
                "recorded golden mismatch: 0x\(String(hash, radix: 16))")
    }
}
