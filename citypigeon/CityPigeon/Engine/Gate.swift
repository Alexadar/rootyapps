import Foundation
import MLX

/// Day-1 viability gate for the mlx-swift dependency, kept permanently.
///
/// Two questions have to be answered before a line of game code is written, because the whole
/// architecture rests on both and neither is recoverable late:
///
///  1. **Does the batched vocabulary exist and evaluate on this SDK?** `smoke()` touches every MLX
///     operation the engine is planned to use. If one of them is missing or renamed, this fails at
///     compile time rather than three files into `Step.swift`.
///
///  2. **Does one step cost less than a frame at `B = 1`?** This is the real risk, and it is the
///     one place where "MLX is the game logic" could turn out to be the wrong call. MLX is built to
///     amortise per-op dispatch across large batches; a game step is dozens of tiny ops on arrays of
///     length 8 to 16. At 120 Hz the budget is 8.33 ms for *everything*, engine and renderer both.
///     `syntheticStep` is shaped like the real step — same array count, same op sequence, same
///     `[B,P,C]` collision cube — so its cost is a truthful forecast rather than a microbenchmark.
///
/// If (2) fails, the Structure-of-Arrays layout means a scalar backend slots in behind the same
/// interface with a parity test, exactly as froggo2 did with `SolverParityTests`. That is the reason
/// to measure now: the fallback is cheap only while nothing has been built on top.
public enum Gate {

    /// Fixed capacities, matching the planned engine. Nothing is allocated after init.
    public static let maxPayloads = 8
    public static let maxCars = 12
    public static let maxPedestrians = 16

    /// Touches the whole planned vocabulary once. Returns a scalar so the graph cannot be
    /// optimised away, and so the caller is forced through an actual device evaluation.
    public static func smoke(batch B: Int = 1) -> Float {
        let P = maxPayloads, C = maxCars

        // Construction and shape vocabulary.
        let payX = MLXArray.zeros([B, P])
        let payAlive = MLXArray.ones([B, P])
        let carX = MLXArray.ones([B, C]) * 3.0
        let pigeonX = MLXArray.zeros([B])

        // Broadcasting a [B] against a [B,P].
        let rel = payX - pigeonX.expandedDimensions(axis: 1)

        // Elementwise maths.
        let dist = sqrt(maximum(rel * rel, MLXArray(Float(0)))) + 1e-9

        // Comparison + logical vocabulary, and the branchless ternary that replaces `if`.
        let live = greater(payAlive, 0.5)
        let near = less(dist, 100.0)
        let usable = which(logicalAnd(live, near), MLXArray(Float(1)), MLXArray(Float(0)))

        // The collision cube: [B,P,1] against [B,1,C] -> [B,P,C]. This is the only quadratic op in
        // the engine and the one whose cost scales with capacity rather than with live entities.
        let d = payX.expandedDimensions(axis: 2) - carX.expandedDimensions(axis: 1)
        let hits = which(less(abs(d), MLXArray(Float(0.5))), MLXArray(Float(1)), MLXArray(Float(0)))
        let perPayload = hits.sum(axis: 2)

        // Reductions along a capacity axis.
        let score = (perPayload * usable).sum(axis: 1)

        // The free-slot idiom: argMax over a mask, one-hot, masked write. This is what replaces a
        // variable-length list, and it is the single most important thing to prove works.
        let freeF = which(logicalNot(live), MLXArray(Float(1)), MLXArray(Float(0)))
        let slot = freeF.argMax(axis: 1)
        let lane = MLXArray.arange(P, dtype: .int32)
        let oneHot = which(equal(slot.expandedDimensions(axis: 1), lane.expandedDimensions(axis: 0)),
                           MLXArray(Float(1)), MLXArray(Float(0)))
        let written = which(greater(oneHot, 0.5), MLXArray(Float(7)), payX)

        let total = score.sum() + written.sum()
        total.eval()
        return total.item(Float.self)
    }

    /// One step's worth of work, shaped like the real thing.
    ///
    /// Deliberately not simplified: the point is to measure the dispatch cost of the *number* of
    /// operations a real step performs, which at `B = 1` dominates the arithmetic entirely.
    public static func syntheticStep(batch B: Int) -> MLXArray {
        let P = maxPayloads, C = maxCars, W = maxPedestrians
        let dt = MLXArray(Float(1.0 / 120.0))
        let g = MLXArray(Float(24.0))

        var pigeonX = MLXArray.zeros([B]), pigeonY = MLXArray.ones([B]) * 12
        var pigeonVX = MLXArray.ones([B]) * 6, pigeonVY = MLXArray.zeros([B])
        var charge = MLXArray.zeros([B])
        var payX = MLXArray.zeros([B, P]), payY = MLXArray.ones([B, P]) * 12
        var payVX = MLXArray.zeros([B, P]), payVY = MLXArray.zeros([B, P])
        var payAlive = MLXArray.zeros([B, P])
        var carX = MLXArray.arange(C, dtype: .float32).expandedDimensions(axis: 0) * 4
        let carV = MLXArray.ones([B, C]) * -3
        var pedX = MLXArray.arange(W, dtype: .float32).expandedDimensions(axis: 0) * 3
        let pedV = MLXArray.ones([B, W]) * 1.2
        let hold = MLXArray.ones([B])

        // --- pigeon: inertial approach to the intent, then integrate
        let intentVX = MLXArray.ones([B]) * 6, intentVY = MLXArray.zeros([B])
        pigeonVX = pigeonVX + (intentVX - pigeonVX) * 0.12
        pigeonVY = pigeonVY + (intentVY - pigeonVY) * 0.12
        pigeonX = pigeonX + pigeonVX * dt
        pigeonY = clip(pigeonY + pigeonVY * dt, min: MLXArray(Float(6)), max: MLXArray(Float(18)))

        // --- charge, and the release edge
        charge = clip(charge + dt * 0.85, min: MLXArray(Float(0)), max: MLXArray(Float(1)))
        let releasing = which(less(hold, 0.5), MLXArray(Float(1)), MLXArray(Float(0)))

        // --- spawn a payload into a free slot, branchlessly
        let freeF = which(less(payAlive, 0.5), MLXArray(Float(1)), MLXArray(Float(0)))
        let hasFree = freeF.max(axis: 1)
        let slot = freeF.argMax(axis: 1)
        let lane = MLXArray.arange(P, dtype: .int32)
        let oneHot = which(equal(slot.expandedDimensions(axis: 1), lane.expandedDimensions(axis: 0)),
                           MLXArray(Float(1)), MLXArray(Float(0)))
        let write = oneHot * (releasing * hasFree).expandedDimensions(axis: 1)
        let wr = greater(write, 0.5)
        payX = which(wr, broadcast(pigeonX.expandedDimensions(axis: 1), to: [B, P]), payX)
        payY = which(wr, broadcast(pigeonY.expandedDimensions(axis: 1), to: [B, P]), payY)
        payVX = which(wr, broadcast(pigeonVX.expandedDimensions(axis: 1), to: [B, P]), payVX)
        payVY = which(wr, broadcast((pigeonVY - charge * 8).expandedDimensions(axis: 1), to: [B, P]), payVY)
        payAlive = maximum(payAlive, write)

        // --- integrate payloads
        payVY = payVY - g * dt
        payX = payX + payVX * dt
        payY = payY + payVY * dt

        // --- impact against the street plane, with the sub-step crossing correction
        let crossed = logicalAnd(greater(payAlive, 0.5), lessEqual(payY, 0.0))
        let over = maximum(-payY, MLXArray(Float(0)))
        let backT = over / maximum(abs(payVY), MLXArray(Float(1e-6)))
        let impactX = payX - payVX * backT

        // --- collision cubes, one per target kind
        let dCar = impactX.expandedDimensions(axis: 2) - carX.expandedDimensions(axis: 1)
        let carHit = logicalAnd(less(abs(dCar), MLXArray(Float(1.1))),
                                crossed.expandedDimensions(axis: 2))
        let carHitF = which(carHit, MLXArray(Float(1)), MLXArray(Float(0)))

        let dPed = impactX.expandedDimensions(axis: 2) - pedX.expandedDimensions(axis: 1)
        let pedHit = logicalAnd(less(abs(dPed), MLXArray(Float(0.5))),
                                crossed.expandedDimensions(axis: 2))
        let pedHitF = which(pedHit, MLXArray(Float(1)), MLXArray(Float(0)))

        // --- scoring, and the streak reset on a payload that hit nothing
        let anyHit = clip(carHitF.sum(axis: 2) + pedHitF.sum(axis: 2), max: MLXArray(Float(1)))
        let scored = (anyHit * 100).sum(axis: 1)
        let whiffed = which(logicalAnd(crossed, less(anyHit, 0.5)),
                            MLXArray(Float(1)), MLXArray(Float(0))).sum(axis: 1)

        // --- despawn and advance traffic
        payAlive = which(crossed, MLXArray(Float(0)), payAlive)
        carX = carX + carV * dt
        pedX = pedX + pedV * dt

        let out = scored - whiffed + payAlive.sum(axis: 1) + carX.sum(axis: 1) + pedX.sum(axis: 1)
        out.eval()
        return out
    }
}
