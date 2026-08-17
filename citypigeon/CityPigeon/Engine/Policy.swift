import Foundation
import MLX

/// A scripted pilot, built entirely out of the same functions the oracle certifies.
///
/// It exists for three reasons, and the third is the important one:
///
///  1. It drives the demo capture, so the recording shows real play rather than a puppet.
///  2. It is the end-to-end test. If the policy can reliably score, then the config, the closed
///     form, the interception window, the spawner and the step all agree with each other — which no
///     unit test can establish on its own.
///  3. It is the shape any pilot has: `World → Intent`, fully batched, no host loop — so an attract
///     mode, a difficulty sweep and a replay driver all plug in at the same seam.
///
/// It aims with `Interception.window`, the *same* function the spawner's guarantee is written in
/// terms of. That is deliberate: if the HUD, the AI and the oracle ever disagree about what is
/// hittable, the bug is one place rather than three.
public enum Policy {

    /// Hold to charge until the charge reaches the middle of the best available window, then let go.
    ///
    /// The release is implicit — `hold` going false *is* the release edge the step looks for — which
    /// keeps the policy a pure function of state with nothing to remember between frames.
    public static func autopilot(_ w: World) -> Intent {
        let c = w.config
        let B = w.batch, M = w.targetSlots, K = w.flockSlots
        let t = Float(w.frame) * Float(c.dt)

        // Where every target is right now.
        let tgtNow = w.tgtX0 + w.tgtV * (MLXArray(t) - w.tgtT0)

        // **When** to let go, not merely which charge would work this instant.
        //
        // The instantaneous solver was the wrong question for a pilot: it answers "if I release
        // now", then the pilot holds for up to 0.9 s to reach that charge, by which time it has flown
        // 11 m and the traffic has moved. `releaseWindow` solves for the release *time* directly,
        // with the charge ramp and both bodies' motion already in it.
        let win = Interception.releaseWindow(
            pigeonX: w.pigeonX.expandedDimensions(axis: 1),
            pigeonY: w.pigeonY.expandedDimensions(axis: 1),
            forwardSpeed: w.pigeonVX.expandedDimensions(axis: 1),
            climb: w.pigeonVY.expandedDimensions(axis: 1),
            charge: w.charge.expandedDimensions(axis: 1),
            targetX: tgtNow, targetSpeed: w.tgtV,
            targetTopY: w.targetTopY, radius: w.targetRadius, in: c)

        // Only consider live, unhit targets that are still ahead.
        let gap = tgtNow - w.pigeonX.expandedDimensions(axis: 1)
        var eligible = logicalAnd(logicalAnd(win.valid, w.tgtAlive),
                                  logicalAnd(logicalNot(w.tgtHit), greater(gap, MLXArray(Float(0)))))

        // Reachable on the RAMPING branch only.
        //
        // `w.charge` is this pilot's entire memory — it is the hold clock, which is what keeps the
        // policy a pure function of state. But the clock saturates at `chargeCeiling`, so it cannot
        // express "keep holding past full charge", which is what a solution on the saturated branch
        // would require. Rather than give the pilot a timer, drop those shots: the target is simply
        // too far for now, and since this re-solves every frame, the shot becomes available on its
        // own as the target closes and the required impact time falls into the ramp.
        let ceilingReach = (MLXArray(Float(c.chargeCeiling)) - w.charge).expandedDimensions(axis: 1)
            * Float(c.chargeTime)
        eligible = logicalAnd(eligible, lessEqual(win.lo, ceilingReach))

        // Commit to the nearest eligible one. Nearest rather than highest-scoring, because a
        // policy that keeps switching targets never finishes a charge.
        let far = MLXArray(Float(1e9))
        let ranked = which(eligible, gap, far)
        let chosen = ranked.argMin(axis: 1)                              // [B]
        let haveTarget = less(ranked.min(axis: 1), 1e8)                  // [B]

        let lane = MLXArray.arange(M, dtype: .int32).expandedDimensions(axis: 0)
        let pick = which(equal(chosen.expandedDimensions(axis: 1), lane),
                         MLXArray(Float(1)), MLXArray(Float(0)))         // [B,M] one-hot
        // A one-hot masked sum IS a gather, without needing a gather primitive.
        let clampedHi = minimum(win.hi, ceilingReach)
        let wantTau = ((win.lo + clampedHi) / 2 * pick).sum(axis: 1)
        // Convert the release *time* back into the charge the meter will read at that moment — the
        // one number a stateless pilot can compare against.
        let wantCharge = Interception.chargeAtRelease(wantTau, chargeNow: w.charge, in: c)

        // Hold while still short of the charge this shot needs; release on reaching it.
        let hold = logicalAnd(haveTarget, less(w.charge, wantCharge))

        // Fly level at cruise. The guarantee band is computed around this state, so the pilot has
        // no reason to leave it — and staying inside it is what makes a demo representative.
        let altitudeError = (MLXArray(Float(c.cruiseAltitude)) - w.pigeonY) * 0.35
        let level = clip(altitudeError, min: MLXArray(Float(-1)), max: MLXArray(Float(1)))

        // ── Avoid the flock, which overrides everything else ─────────────────────────────────
        //
        // Without this the pilot flies straight into birds and freezes, and every measurement taken
        // through it becomes a measurement of dying rather than of playing: two of eight worlds in
        // the scoring test came back with a score of zero, and the odometer test recorded 44 m of
        // travel instead of 800. A scripted pilot that cannot survive the game cannot demonstrate it.
        //
        // Deliberately crude — nearest threat, climb or dive away from it. A pilot that dodges
        // *elegantly* would be a pilot whose scores say more about the dodging than about the
        // shooting, and the shooting is what the rest of this file is for.
        let fGap = w.flockX - w.pigeonX.expandedDimensions(axis: 1)
        let fClose = w.pigeonVX.expandedDimensions(axis: 1) - w.flockV
        let fDy = w.flockY - w.pigeonY.expandedDimensions(axis: 1)

        // Threats come from BOTH sides now: head-on and slower-ahead birds close from in front,
        // overtakers close from behind. Take the absolute closing geometry rather than assuming the
        // danger is always ahead — a pilot that only looks forward is a pilot that gets rear-ended.
        let closing = greater(fGap * fClose, MLXArray(Float(0)))   // gap and closure same sign
        let ttc = abs(fGap) / maximum(abs(fClose), MLXArray(Float(0.5)))
        let vertRisk = less(abs(fDy), MLXArray(Float(c.crashRadiusY * 2.2)))
        let threat = logicalAnd(logicalAnd(w.flockAlive, closing),
                                logicalAnd(vertRisk, less(ttc, MLXArray(Float(2.0)))))

        // Most urgent threat, by one-hot gather — the same idiom target selection uses.
        //
        // Deliberately simple: steer away from the nearest. Two "obvious" refinements were tried and
        // both made it measurably worse, so they are recorded here rather than left to be rediscovered:
        //
        //  - Weighing pressure from *all* threats and steering toward the emptier side: 6 deaths in
        //    10 runs against this version's 4. With no hysteresis the balance flips frame to frame and
        //    the pilot dithers in the middle instead of committing to one side.
        //  - Refusing to dodge into the ceiling or the floor (`nearTop`/`nearBottom` overrides): also
        //    6 in 10, on its own. It fires exactly when the pilot is already displaced by an earlier
        //    dodge, and reverses the escape it was halfway through completing.
        //
        // Both were measured with `testDodgingIsWhatSeparatesSurvivalFromDeath`, one change at a time.
        // This bot exists to demonstrate the game and give the tests a pilot, not to play well.
        let far2 = MLXArray(Float(1e9))
        let urgency = which(threat, ttc, far2)
        let worst = urgency.argMin(axis: 1)
        let haveThreat = less(urgency.min(axis: 1), 1e8)
        let fLane = MLXArray.arange(K, dtype: .int32).expandedDimensions(axis: 0)
        let fPick = which(equal(worst.expandedDimensions(axis: 1), fLane),
                          MLXArray(Float(1)), MLXArray(Float(0)))
        let threatDy = (fDy * fPick).sum(axis: 1)

        // Break away from whichever side it is on. When it is dead level, prefer climbing: there is
        // more sky above the cruise band than below it, and diving spends altitude the drop needs.
        let dodge = which(greater(threatDy, MLXArray(Float(0))),
                          MLXArray(Float(-1)), MLXArray(Float(1)))

        let moveY = which(haveThreat, dodge, level)

        // Do not throw while taking evasive action — a shot released mid-dodge is aimed from a state
        // the solver assumed was steady, and the release solver says so in its preconditions.
        let safeHold = logicalAnd(hold, logicalNot(haveThreat))

        return Intent(moveX: MLXArray.zeros([B]), moveY: moveY, hold: safeHold)
    }
}
