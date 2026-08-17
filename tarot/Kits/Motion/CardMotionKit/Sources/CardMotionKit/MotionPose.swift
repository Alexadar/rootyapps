import Foundation

/// One frame of renderable poses, `[N, C]` per channel. The renderer reads lane values for
/// world 0 and applies them as entity transforms — it runs no motion math of its own
/// ("a renderer and nothing else", froggo2's contract).
public struct PoseFrame: Sendable {
    /// Table-plane position (TU) and height above the table.
    public var x: Tensor
    public var z: Tensor
    public var y: Tensor
    /// Lean about the two table axes (radians): drag roll + juice rotation + ambient idle.
    public var tiltX: Tensor
    public var tiltZ: Tensor
    /// Flip angle in radians, 0 (face down) → π (face up).
    public var flipAngle: Tensor
    /// Yaw about the table normal (radians) — the crossing card of the ten-card cross
    /// turns as it flies (rides the flip ramp) and rests at its slot's yaw. Zero for
    /// every slot of every other layout.
    public var yaw: Tensor
    /// Width squash at the flip apex (multiplies the card's short axis), 1 = none.
    public var squash: Tensor
    /// Uniform scale: held lift plus juice oscillation.
    public var scale: Tensor
    /// The blob shadow's driver — the card's height (renderer maps to shadow size/opacity).
    public var shadowHeight: Tensor
    /// Pass-throughs the renderer needs for ordering and state-keyed presentation.
    public var deckDepth: Tensor
    public var phase: Tensor
    public var slot: Tensor
    /// Smoothed foil light angle, `[N]` per axis.
    public var lightX: Tensor
    public var lightZ: Tensor
}

public enum MotionPose {

    /// Derive the renderable pose of every card from the current state. Pure — calling it
    /// twice changes nothing (a test proves it).
    public static func poses(of w: MotionWorld, config: MotionConfig) -> PoseFrame {
        let c = w.capacity

        // Reduce Motion zeroes every decorative channel in one place; the kernel mode also
        // already flattened the flight. Positions, flip progress and events are untouched —
        // the alternative is complete, not "animations off".
        let decor = config.reduceMotion ? 0.0 : 1.0

        // The stillness law: ONE per-state liveliness lane gates every decorative
        // oscillation below. A landed card is a read card — perfectly still; the deck
        // breathes, a held card is fully alive, a flying card is subdued. Any future
        // decor channel multiplies this same lane.
        let landed = w.phase .== MotionWorld.Phase.landed
        let held = w.phase .== MotionWorld.Phase.held
        let flying = w.phase .== MotionWorld.Phase.flying
        let liveliness = Tensor.which(landed, config.livelinessLanded,
                         Tensor.which(held, config.livelinessHeld,
                         Tensor.which(flying, config.livelinessFlying,
                                      config.livelinessInDeck * Tensor.ones([w.batch, c]))))

        // Juice (Balatro juice_up): scale oscillates at one frequency with cubic decay,
        // rotation at another with quadratic decay, over 0.4 s.
        let e = (1 - w.juiceT / config.juiceDuration).clamped(min: 0, max: 1)
        let scaleOsc = (w.juiceT * config.juiceScaleFrequency).sine
            * (config.juiceScaleFactor * decor) * w.juiceAmp * e.cubed * liveliness
        let rotJuice = (w.juiceT * config.juiceRotationFrequency).sine
            * (config.juiceRotationFactor * decor) * w.juiceAmp * w.juiceSign * (e * e) * liveliness

        // Ambient idle wobble — per-lane phase/frequency so the live parts never freeze.
        let ambientScale = liveliness * (config.ambientAmplitude * decor)
        let theta = w.ambientFrequency * (2 * Double.pi * w.time) + w.ambientPhase
        let ambientA = theta.sine * ambientScale
        let ambientB = (theta + 1.7).sine * (ambientScale * 0.7)

        // Drag roll: lean into the movement, clamped (Balatro 0.015·vel, ±0.3 rad).
        let rollZ = (w.vx * (config.rollPerVelocity * decor))
            .clamped(min: -config.rollClamp, max: config.rollClamp)
        let rollX = (w.vz * (config.rollPerVelocity * decor))
            .clamped(min: -config.rollClamp, max: config.rollClamp)

        // Deck cards stack by depth; everything else carries its own height.
        let inDeck = w.phase .== MotionWorld.Phase.inDeck
        let stackY = (Double(c - 1) - w.deckDepth).maximum(0) * config.deckCardThickness

        // Slot-carried yaw and rest lift ride the flip ramp: 0 leaving the deck, full at
        // landing, unwinding on a return flight. Both are exactly zero when the config's
        // arrays are zero (every layout but the ten-card cross), so the three-card pose
        // stream is bit-identical to before these channels existed — goldens prove it.
        let (_, _, slotYawLane, slotLiftLane) = MotionStep.slotTargets(slot: w.slot, config: config)
        let yawOut = slotYawLane * w.flip
        let slotRestLift = slotLiftLane * w.flip
        let tiltXTotal = rollX + ambientB + rotJuice * 0.6
        let tiltZTotal = rollZ + ambientA + rotJuice
        // Tilt clearance: a card rotated while lying on the table sinks its edge below the
        // surface (seen on device as the landing wobble clipping through). Small-angle edge
        // drop = half-extent × |tilt|; adding it keeps the lowest corner on the surface.
        // Geometry, not decoration — it is zero exactly when the card is level.
        let tiltClearance = tiltZTotal.absolute * (config.cardWidth * 0.5)
            + tiltXTotal.absolute * (config.cardLength * 0.5)
        let yOut = Tensor.which(inDeck, stackY, w.y) + tiltClearance + slotRestLift

        let flipAngle = w.flip * Double.pi
        let squash = 1 - (w.flip * Double.pi).sine * (config.flipSquash * decor)

        let heldScale = Tensor.which(held, config.heldScale, 1.0 * Tensor.ones([w.batch, c]))
        let scale = heldScale + scaleOsc

        return PoseFrame(x: w.x, z: w.z, y: yOut,
                         tiltX: tiltXTotal,
                         tiltZ: tiltZTotal,
                         flipAngle: flipAngle,
                         yaw: yawOut,
                         squash: squash,
                         scale: scale,
                         shadowHeight: yOut,
                         deckDepth: w.deckDepth,
                         phase: w.phase,
                         slot: w.slot,
                         lightX: w.lightX,
                         lightZ: w.lightZ)
    }
}
