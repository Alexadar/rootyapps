import Foundation

/// A pig that plays itself.
///
/// It is the shape any pilot has: **`World → Intent`, fully batched, no host loop, nothing remembered
/// between frames** — so the demo, a difficulty sweep and a replay driver all plug in at the same
/// seam, which is the single `Intent`-building call site in `Game.tick`. Ported in stance from
/// `citypigeon/CityPigeon/Engine/Policy.swift`, down to the idioms: a masked argmin picks a target and
/// a one-hot masked sum reads its position back, which is a gather without a gather primitive.
///
/// This bot exists to demonstrate the game and to give the tests a player, **not to play well**. Where
/// a cleverer rule would make it stronger and the code harder to reason about, it stays stupid.
enum Pilot {

    /// Sentinel for "no candidate", far outside any real squared distance in a 20 m paddock.
    private static let far = 1e12

    /// What the pilot is trying to do this frame. The scenario overrides it beat by beat; left alone,
    /// `.play` is the whole game.
    enum Goal: Equatable {
        /// Eat when there is food, drop when heavy, run when chased.
        case play
        /// Play, but never drop of its own accord. The demo uses it so the drop lands in the beat
        /// that explains it rather than three beats early, which is what the pilot does left alone —
        /// it is a competent pig, and a competent pig drops the moment it is heavy.
        case forage
        /// Walk toward a fixed point and stop there. Used by the scenario to stage a shot.
        case walk(x: Double, z: Double)
        /// Stand still. Used while something the player should watch is happening.
        case wait
        /// Drop on this frame if the engine will allow it.
        case drop
        /// Run from the dog and keep running, however far ahead it gets.
        ///
        /// `.play` is not the same thing: it stops for food the moment the gap opens past
        /// `pilotFleeRadius`, and a pig that stops to eat the carrots it just grew fattens straight
        /// back into catchable range — which is what `ScenarioTests` caught the escape beat doing.
        case flee
    }

    static func intent(_ w: World, goal: Goal = .play) -> Intent {
        let c = w.config
        let n = w.batch, k = w.dropSlots

        // ── The nearest ripe carrot ─────────────────────────────────────────────────────────
        //
        // Nearest rather than biggest or oldest, because a policy that keeps changing its mind never
        // finishes a meal — the same reason citypigeon's pilot commits to the closest target.
        let ripeness = World.ripeness(age: w.dropAge, in: c)
        let edible = (ripeness .>= 1) .&& w.dropAlive

        let dx = w.dropX - w.x.spread(k)
        let dz = w.dropZ - w.z.spread(k)
        let d2 = dx * dx + dz * dz

        let ranked = Tensor.which(edible, d2, far)
        let pick = Tensor.oneHot(ranked.argMinSlots(), slots: k)
        let haveFood = ranked.minSlots() .< far * 0.5

        // A one-hot masked sum IS a gather.
        let foodX = (w.dropX * pick).sumSlots()
        let foodZ = (w.dropZ * pick).sumSlots()

        // ── Fleeing ─────────────────────────────────────────────────────────────────────────
        //
        // Directly away from the dog, and it overrides everything: a pig that stops for a snack with
        // a dog on it is a pig that gets caught, and the dog is the only thing in this game that can
        // take something away.
        let awayX = w.x - w.dogX, awayZ = w.z - w.dogZ
        let dogGap = (awayX * awayX + awayZ * awayZ).squareRoot.maximum(1e-6)

        // ── The goal decides the destination ────────────────────────────────────────────────
        //
        // Every branch is a mask, not an `if`: at `N = 512` the worlds are in different situations and
        // must still run the same instructions.
        let plan = destination(goal, n: n)
        let chased = (w.dogActive .> 0.5)
            .&& ((dogGap .< c.pilotFleeRadius) .|| plan.alwaysFlee)

        // **Fleeing straight away from the dog gets you cornered.** The paddock is a disc: run radially
        // and you reach the fence in six seconds, slide along it, and the dog cuts the chord and has
        // you. Measured — the escape beat was losing a pig that was half a metre per second faster.
        //
        // So the further out the pig is, the more the flee direction turns to run ALONG the fence
        // instead of into it, picking whichever way round agrees with getting away. Blended by
        // distance rather than switched, or the pig would jink at one radius.
        let out = (w.x * w.x + w.z * w.z).squareRoot.maximum(1e-6)
        let tangentX = -w.z / out, tangentZ = w.x / out
        let sameWay = Tensor.which((awayX * tangentX + awayZ * tangentZ) .>= 0, 1.0, -1.0)
        let corner = out.smoothstep(c.paddockRadius * 0.55, c.paddockRadius * 0.92)
        let fleeX = awayX / dogGap * (1 - corner) + tangentX * sameWay * corner
        let fleeZ = awayZ / dogGap * (1 - corner) + tangentZ * sameWay * corner

        // Toward the food, or away from the dog, or wherever the scenario says — in that order of
        // precedence, resolved by two nested `which`es rather than by control flow.
        let wantX = Tensor.which(chased, w.x + fleeX * 10,
                                 Tensor.which(plan.active, plan.x,
                                              Tensor.which(haveFood, foodX, w.x)))
        let wantZ = Tensor.which(chased, w.z + fleeZ * 10,
                                 Tensor.which(plan.active, plan.z,
                                              Tensor.which(haveFood, foodZ, w.z)))

        // ── Steering ────────────────────────────────────────────────────────────────────────
        //
        // Full deflection toward the destination until close enough to be eating it, then nothing:
        // the engine's own mouth reach decides "close enough", so the pilot cannot walk to a spot the
        // mouth cannot reach from.
        let body = PigShape.derive(fat: w.fat)
        let arrive = body.length * 0.5 + c.mouthReach
        let toX = wantX - w.x, toZ = wantZ - w.z
        let range = (toX * toX + toZ * toZ).squareRoot
        let travelling = (range .> arrive) .|| chased
        let step = range.maximum(1e-6)

        let idle = Tensor.which(plan.stop, 0.0, 1.0)
        let moveX = toX / step * travelling * idle
        let moveZ = toZ / step * travelling * idle

        // ── Dropping ────────────────────────────────────────────────────────────────────────
        //
        // Two reasons, both about weight: it is heavy enough that the next dog would catch it, or it
        // is being chased right now and needs the speed this second. The engine enforces the cooldown
        // and the floor, so the pilot may ask freely.
        let heavy = w.fat .>= c.pilotDropAt
        let panic = chased .&& (w.fat .>= c.dropMinFat)
        let wanted = Tensor.which(heavy .|| panic, 1.0, 0.0) * plan.noDrop.not
        let drop = Tensor.maximum(wanted, plan.drop)

        return Intent(moveX: moveX, moveZ: moveZ, drop: drop)
    }

    /// The goal as `[N]` tensors.
    ///
    /// A `switch` over the enum is legal here and is not a branch over worlds: it chooses one plan per
    /// frame for the WHOLE batch, and everything it hands back is a tensor, so the caller downstream
    /// stays branchless. `stop` is separate from `active` because "walk to here" and "stand still" are
    /// different instructions, and only one of them has a destination.
    private struct Plan {
        var x: Tensor, z: Tensor, active: Tensor, stop: Tensor, drop: Tensor, noDrop: Tensor
        var alwaysFlee: Tensor
    }

    private static func destination(_ goal: Goal, n: Int) -> Plan {
        switch goal {
        case .play:
            return Plan(x: .zeros([n]), z: .zeros([n]), active: .zeros([n]),
                        stop: .zeros([n]), drop: .zeros([n]), noDrop: .zeros([n]), alwaysFlee: .zeros([n]))
        case .forage:
            return Plan(x: .zeros([n]), z: .zeros([n]), active: .zeros([n]),
                        stop: .zeros([n]), drop: .zeros([n]), noDrop: .ones([n]), alwaysFlee: .zeros([n]))
        case .walk(let x, let z):
            return Plan(x: Tensor(repeating: x, shape: [n]), z: Tensor(repeating: z, shape: [n]),
                        active: .ones([n]), stop: .zeros([n]), drop: .zeros([n]),
                        noDrop: .ones([n]), alwaysFlee: .zeros([n]))
        case .wait:
            return Plan(x: .zeros([n]), z: .zeros([n]), active: .ones([n]),
                        stop: .ones([n]), drop: .zeros([n]), noDrop: .ones([n]), alwaysFlee: .zeros([n]))
        case .drop:
            return Plan(x: .zeros([n]), z: .zeros([n]), active: .zeros([n]),
                        stop: .ones([n]), drop: .ones([n]), noDrop: .zeros([n]),
                        alwaysFlee: .zeros([n]))
        case .flee:
            return Plan(x: .zeros([n]), z: .zeros([n]), active: .zeros([n]),
                        stop: .zeros([n]), drop: .zeros([n]), noDrop: .zeros([n]),
                        alwaysFlee: .ones([n]))
        }
    }
}
