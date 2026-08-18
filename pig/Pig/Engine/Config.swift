import Foundation

/// Every tunable number in the game, in one place, in SI units.
///
/// Nothing in `Engine/` reads a literal that belongs here, and the renderer reads its geometry from
/// `PigShape` rather than inventing any — so "the pig the physics moves" and "the pig you see" cannot
/// be two different pigs.
///
/// **The loop this game is made of:** the pig drops what it has been carrying, which makes it lighter
/// and faster; what it drops grows into a carrot; the carrot is the only food there is, so the only
/// way to get fat again is to eat what it left behind. Every number below is tuned to keep those four
/// steps in tension, and the dog is what gives the tension stakes.
struct WorldConfig: Sendable {

    // MARK: - Time

    /// Fixed simulation step. The renderer's frame rate never reaches the engine: `MetalGameView`
    /// accumulates real time and advances whole `dt`s, so 60 Hz and 120 Hz produce identical motion.
    var dt: Double = 1.0 / 120.0

    // MARK: - Slots

    /// Droppings and carrots share one slot array: a carrot *is* a dropping that has been sitting
    /// long enough. One array, one lifetime, no hand-off between two systems that could disagree.
    var dropSlots: Int = 16
    /// How many carrots are already grown when a run starts, so there is something to eat before
    /// there is anything to drop.
    var startingCarrots: Int = 3

    // MARK: - Locomotion
    //
    // Fat is the one input that changes how the pig handles, and it changes everything: slower, wider
    // turns, longer to get moving, and a lower cadence. That coupling is the whole game — a fat pig
    // is a rich pig and a slow one, and the dog only catches the slow ones.

    var walkSpeed: Double = 3.35         // m/s at fat = 0
    var speedFatPenalty: Double = 0.55   // fraction of walkSpeed lost at fat = 1
    var turnRate: Double = 4.4           // rad/s at fat = 0
    var turnFatPenalty: Double = 0.55
    /// Time constant of the approach to the intended velocity. Larger = heavier.
    var accelTau: Double = 0.16
    var accelFatPenalty: Double = 0.9    // added fraction of accelTau at fat = 1

    // MARK: - The walk cycle
    //
    // Radians of gait phase per metre travelled. Keyed to DISTANCE, not to time — but that alone does
    // not stop a walk looking like skating, which is what the first version got wrong.
    //
    // A cycle is `2π / cadence` metres of travel, and that IS the stride: the distance a foot covers
    // between one planting and the next. At 4.6 rad/m the pig took 1.37 m strides on 0.32 m legs
    // while its feet swung 0.22 m, so every foot slid a metre per step. The number now comes from the
    // leg instead: `strideOverLeg` × leg length, which is what `ShapeOracleTests` pins.
    //
    // And it **rises** with fat rather than falling. A pig whose legs have shortened from 0.32 m to
    // 0.15 m does not take longer strides more slowly; it takes shorter ones faster, which is most of
    // what makes a fat pig read as a fat pig when it walks.
    var strideOverLeg: Double = 1.75
    /// Fraction of each cycle a given foot spends on the ground. Above 0.5 by definition for a walk —
    /// at 0.5 it is a trot, and at 0.68 there are always two or three feet down, which is what makes
    /// the waddle look stable rather than bouncy.
    var dutyFactor: Double = 0.68

    // MARK: - The paddock

    var paddockRadius: Double = 20.0

    // MARK: - Dropping
    //
    // The slimming move, and deliberately NOT something you can spam: the cooldown is what makes
    // "am I light enough to outrun the dog" a question you have to answer in advance rather than at
    // the moment you need the answer.

    var dropCooldown: Double = 4.5       // seconds between drops
    /// **Fat spent on one drop — deliberately more than one carrot returns.**
    ///
    /// This is the ratio the whole economy turns on: a drop costs about two and a half carrots, so
    /// getting light enough to outrun the dog is something you have to *earn* over several meals, not
    /// something you can do the moment you want it. Raise it and the game is about hoarding; lower it
    /// and dropping becomes free and the fat/speed trade-off disappears.
    var dropFatCost: Double = 0.30
    /// Below this there is nothing left to drop.
    var dropMinFat: Double = 0.10
    /// How far behind the pig it lands.
    var dropBehind: Double = 0.42

    // MARK: - Growing

    /// Seconds from dropping to an edible carrot. The waiting is the point: what you drop to escape
    /// the dog is also your next meal, so the panic drop costs you twice.
    var growTime: Double = 9.0
    /// **One drop grows this many separate carrots**, scattered around where it landed.
    ///
    /// Separate, not one big carrot: it is the number of *trips* that has to exceed one, or "several
    /// meals per drop" would be a single walk-up that simply took longer.
    var carrotsPerDrop: Int = 3
    /// Mass of one carrot.
    var carrotUnit: Double = 0.30
    /// How far from the drop point the carrots come up.
    var carrotSpread: Double = 0.75

    // MARK: - Eating

    /// How far in front of the snout the pig can reach, on top of its own body length.
    var mouthReach: Double = 0.30
    /// Carrot units consumed per second.
    var eatRate: Double = 0.55
    /// Fat gained per carrot unit eaten.
    var fatPerCarrotUnit: Double = 0.40
    /// Eating pins the pig in place for this fraction of its speed — it slows to a waddle to feed.
    var eatSpeedFactor: Double = 0.25

    /// Fat burned per second just being awake. Small: dropping is the mechanism, this is only a drift.
    var walkBurn: Double = 0.002

    // MARK: - The dog
    //
    // It arrives occasionally, runs straight at the pig, and gives up after a while. Its speed sits
    // BETWEEN a lean pig's and a fat one's, which is the whole design: it cannot catch you if you
    // have been dropping, and it cannot miss you if you have been greedy.

    var dogSpeed: Double = 2.55
    var dogHunt: ClosedRange<Double> = 8.0...13.0      // seconds it keeps chasing
    var dogRest: ClosedRange<Double> = 14.0...26.0     // seconds before it comes back
    var dogSpawnDistance: Double = 12.0
    var dogCatchRadius: Double = 0.9
    /// Fat shaken loose when it catches you — which lands on the ground as a dropping, so the
    /// punishment is also, eventually, lunch.
    var dogFright: Double = 0.22
    var dogCadence: Double = 5.4

    // MARK: - Wobble
    //
    // A second-order spring, in the ENGINE rather than the renderer. It is feel maths, and feel maths
    // that lives in the renderer cannot be tested, replayed, or swept.

    var wobbleFrequency: Double = 8.5    // rad/s
    var wobbleDamping: Double = 0.42     // fraction of critical
    /// Impulse delivered to the spring by each footfall.
    var wobbleFootfall: Double = 0.9
    /// Impulse per m/s² of change in the pig's own speed.
    var wobbleAccel: Double = 0.11
    /// Impulse from a drop leaving, and from the fright of being caught.
    var wobbleDrop: Double = 3.5

    // MARK: - The scripted pilot
    //
    // Only the demo and the tests read these. They are here rather than in `Pilot.swift` because they
    // are tuning, and tuning lives in one file — the same reason no other number in the game is
    // written where it is used.

    /// How close the dog has to be before the pilot abandons whatever it was doing.
    var pilotFleeRadius: Double = 7.0
    /// Fat at which the pilot drops on principle, rather than in a panic.
    var pilotDropAt: Double = 0.72

    static let shipping = WorldConfig()

    // MARK: - Derived

    func maxSpeed(atFat f: Double) -> Double { walkSpeed * (1 - speedFatPenalty * f) }
    func turnRate(atFat f: Double) -> Double { turnRate * (1 - turnFatPenalty * f) }

    /// Metres of travel per full leg cycle — the stride. Derived from the leg, so it cannot drift
    /// away from the animal the way an authored constant did.
    func stride(atFat f: Double) -> Double { PigShape.scalar(fat: f).legLength * strideOverLeg }

    /// Radians of gait phase per metre. The renderer plants the feet against this exact number, so
    /// the two must be the same formula — `StepTests` checks the batched form in `Step` agrees.
    func cadence(atFat f: Double) -> Double { 2 * Double.pi / stride(atFat: f) }

    /// Fat returned by eating one whole carrot.
    var fatPerCarrot: Double { carrotUnit * fatPerCarrotUnit }
    /// Fat returned by the whole patch one drop grows.
    var fatPerDrop: Double { fatPerCarrot * Double(carrotsPerDrop) }
    /// **How many carrots one drop costs.** The number the economy is stated in: above 1 you must eat
    /// several times to afford dropping once, and below `carrotsPerDrop` the cycle still comes out
    /// ahead, so playing the loop is not slow starvation. `StepTests` pins both ends.
    var carrotsPerDropCost: Double { dropFatCost / fatPerCarrot }
}
