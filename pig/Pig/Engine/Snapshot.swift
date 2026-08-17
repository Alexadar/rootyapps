import Foundation

/// A plain-data, host-side view of one world, for drawing.
///
/// This is the entire boundary between the engine and the renderer. The engine never names a Metal or
/// SwiftUI type; the renderer never touches a `Tensor`.
///
/// **Flat arrays, not structs.** Marshalling each live slot into a Swift struct would mean a loop
/// living in `Engine/` purely to serve drawing. Handing the flat rows across instead moves that
/// iteration to the renderer, where building an instance buffer is inherently a loop and is decor
/// rather than simulation.
///
/// Slots are handed over **whole, including the dead ones**, with their alive mask. Compacting them
/// here would be a gather, and a gather is the thing the whole SoA layout exists to avoid.
struct Snapshot {

    var time: Float = 0
    var x: Float = 0
    var z: Float = 0
    var heading: Float = 0
    var speed: Float = 0
    var fat: Float = 0
    var gait: Float = 0
    var wob: Float = 0
    /// A slow idle rise and fall. A pure function of the tick, so it can never drift out of phase
    /// with itself the way an accumulator would over a long session.
    var breath: Float = 0
    var eating = false
    var eaten: Int = 0

    /// 0 while the drop is on cooldown, 1 when it is ready. The HUD ring is a straight read of this.
    var dropReadiness: Float = 1
    var canDrop = false
    /// True on the frame something hit the ground.
    var dropped = false

    /// The animal itself, derived from `fat` by the one function allowed to decide body dimensions.
    var shape: BodyShape = PigShape.scalar(fat: 0)

    // MARK: - Droppings and carrots, whole slots

    var dropAlive: [Double] = []
    var dropX: [Double] = []
    var dropZ: [Double] = []
    /// 0 = just landed, 1 = a carrot. Everything the renderer needs to know about which it is.
    var dropRipeness: [Double] = []
    var dropRadius: [Double] = []
    /// How much of the carrot is left, 0…1.
    var dropFullness: [Double] = []
    var dropLook: [Double] = []

    // MARK: - The dog

    var dogActive = false
    var dogX: Float = 0
    var dogZ: Float = 0
    var dogHeading: Float = 0
    var dogGait: Float = 0
    /// How close it is, in metres. The HUD turns this into how alarmed to look.
    var dogDistance: Float = .greatestFiniteMagnitude
    var caught = false
}

extension World {

    /// Read world `index` back to the host.
    func snapshot(world index: Int = 0) -> Snapshot {
        let c = config
        var s = Snapshot()
        s.time = Float(time)
        s.x = Float(x[index])
        s.z = Float(z[index])
        s.heading = Float(heading[index])
        s.speed = Float(speed[index])
        s.fat = Float(fat[index])
        s.gait = Float(gait[index])
        s.wob = Float(wob[index])
        s.breath = Float(sin(time * 2 * Double.pi * 0.32))
        s.eating = eating[index] > 0.5
        s.eaten = Int(eaten[index])
        s.dropped = dropped[index] > 0.5
        s.dropReadiness = Float(1 - min(1, dropTimer[index] / c.dropCooldown))
        s.canDrop = dropTimer[index] <= 0 && fat[index] >= c.dropMinFat
        s.shape = PigShape.scalar(fat: fat[index])

        let ripeness = World.ripeness(age: dropAge, in: c)
        s.dropAlive = dropAlive.row(index)
        s.dropX = dropX.row(index)
        s.dropZ = dropZ.row(index)
        s.dropRipeness = ripeness.row(index)
        s.dropRadius = World.dropRadius(amount: dropAmount, ripeness: ripeness, in: c).row(index)
        s.dropFullness = (dropAmount / c.carrotUnit).clamped(min: 0, max: 1).row(index)
        s.dropLook = dropLook.row(index)

        s.dogActive = dogActive[index] > 0.5
        s.dogX = Float(dogX[index])
        s.dogZ = Float(dogZ[index])
        s.dogGait = Float(dogGait[index])
        // The dog always faces what it is chasing, so its heading is a fact about the two positions
        // rather than a fourth piece of state that could disagree with them.
        s.dogHeading = Float(atan2(x[index] - dogX[index], z[index] - dogZ[index]))
        let dx = x[index] - dogX[index], dz = z[index] - dogZ[index]
        s.dogDistance = Float((dx * dx + dz * dz).squareRoot())
        s.caught = dogCaught[index] > 0.5
        return s
    }
}
