import Foundation

/// Per-frame input, `[N]`-shaped: a pointer, a press, and a light angle. A thumb, a mouse, and
/// a scripted pilot all present exactly this — which is what keeps the kernel ignorant of who
/// is driving (froggo2's `AimController` lesson, citypigeon's `Intent`).
public struct MotionIntent: Sendable {
    /// Pointer position in table units.
    public var pointerX: Tensor
    public var pointerZ: Tensor
    /// 0/1: is the pointer down.
    public var press: Tensor
    /// Foil light-angle input in [-1, 1] per axis (device gravity on iOS, cursor on Mac).
    public var lightX: Tensor
    public var lightZ: Tensor

    public init(pointerX: Tensor, pointerZ: Tensor, press: Tensor,
                lightX: Tensor, lightZ: Tensor) {
        self.pointerX = pointerX
        self.pointerZ = pointerZ
        self.press = press
        self.lightX = lightX
        self.lightZ = lightZ
    }

    public static func idle(worlds n: Int) -> MotionIntent {
        MotionIntent(pointerX: .zeros([n]), pointerZ: .zeros([n]), press: .zeros([n]),
                     lightX: .zeros([n]), lightZ: .zeros([n]))
    }
}

/// The semantic events of one step, as 0/1 masks. Everything presentational — haptics,
/// particles, hitstop, sound — binds to these, never to animation frames (the Marvel Snap
/// patch-note lesson, enforced by architecture). All `[N, C]` except `drawComplete` (`[N]`).
public struct MotionEvents: Sendable {
    public var grabbed: Tensor
    public var releasedToSlot: Tensor
    public var releasedToReturn: Tensor
    /// The face passes edge-on — the reveal instant.
    public var flipApex: Tensor
    public var landed: Tensor
    /// Landed AND it was the final empty slot — the hero beat (biggest juice, the reserved
    /// haptic, the longest hitstop).
    public var heroLanded: Tensor
    public var returnedToDeck: Tensor
    /// `[N]`: all slots filled, on the edge.
    public var drawComplete: Tensor

    /// True if any world fired any event this step — the cheap "anything to present?" gate.
    public var isEmpty: Bool {
        grabbed.sumLast().data.allSatisfy { $0 == 0 }
            && releasedToSlot.sumLast().data.allSatisfy { $0 == 0 }
            && releasedToReturn.sumLast().data.allSatisfy { $0 == 0 }
            && flipApex.sumLast().data.allSatisfy { $0 == 0 }
            && landed.sumLast().data.allSatisfy { $0 == 0 }
            && returnedToDeck.sumLast().data.allSatisfy { $0 == 0 }
            && drawComplete.data.allSatisfy { $0 == 0 }
    }
}

/// The whole game state, structure-of-arrays, batch axis first.
///
/// `MotionWorld(batch: 1)` is the live game; `MotionWorld(batch: 4096)` is the test harness.
/// There is no other path. Cards are fixed-capacity lanes — never appended, never removed,
/// only masked — and phases are numeric codes gated by masks, never branches.
public struct MotionWorld: Sendable {
    public enum Phase {
        public static let inDeck = 0.0
        public static let held = 1.0
        public static let flying = 2.0
        public static let landed = 3.0
    }

    public let batch: Int
    public let capacity: Int
    public let seed: UInt64
    public private(set) var tick: UInt64 = 0
    /// Simulation time in seconds — accumulated from the dt the caller supplies; the kernel
    /// never reads a clock.
    public internal(set) var time: Double = 0

    // Card lanes, [N, C].
    public internal(set) var x: Tensor
    public internal(set) var z: Tensor
    /// Height above the table. Never negative — the table is solid; a test proves it.
    public internal(set) var y: Tensor
    public internal(set) var vx: Tensor
    public internal(set) var vz: Tensor
    public internal(set) var phase: Tensor
    /// Stack order in the deck: smaller is nearer the top. Returned cards go on top by taking
    /// (current minimum − 1); the value is an order, not an index, so negatives are fine.
    public internal(set) var deckDepth: Tensor
    /// Committed slot index, or −1.
    public internal(set) var slot: Tensor
    public internal(set) var flightT: Tensor
    public internal(set) var startX: Tensor
    public internal(set) var startZ: Tensor
    public internal(set) var startVX: Tensor
    public internal(set) var startVZ: Tensor
    /// Flip progress, 0 (face down) → 1 (face up). Monotone once a slot flight commits;
    /// a test proves it.
    public internal(set) var flip: Tensor
    public internal(set) var juiceAmp: Tensor
    public internal(set) var juiceT: Tensor
    public internal(set) var juiceSign: Tensor
    /// Per-lane ambient wobble phase and frequency — fixed at init from the seed, so idle
    /// cards drift out of sync with each other but identically across runs.
    public let ambientPhase: Tensor
    public let ambientFrequency: Tensor

    // World lanes, [N].
    public internal(set) var lightX: Tensor
    public internal(set) var lightZ: Tensor
    var prevPress: Tensor
    var prevFlipHalf: Tensor
    var prevDone: Tensor

    public init(batch: Int, config: MotionConfig = .standard, seed: UInt64) {
        let n = batch
        let c = config.cardCapacity
        self.batch = n
        self.capacity = c
        self.seed = seed

        x = Tensor(repeating: config.deckX, shape: [n, c])
        z = Tensor(repeating: config.deckZ, shape: [n, c])
        y = .zeros([n, c])
        vx = .zeros([n, c])
        vz = .zeros([n, c])
        phase = Tensor(repeating: Phase.inDeck, shape: [n, c])
        // Lane order is deck order until the app assigns a shuffle permutation.
        deckDepth = Tensor(shape: [n, c],
                           data: (0..<(n * c)).map { Double($0 % c) })
        slot = Tensor(repeating: -1, shape: [n, c])
        flightT = .zeros([n, c])
        startX = .zeros([n, c])
        startZ = .zeros([n, c])
        startVX = .zeros([n, c])
        startVZ = .zeros([n, c])
        flip = .zeros([n, c])
        juiceAmp = .zeros([n, c])
        // Start past the envelope so a fresh world has no residual wobble.
        juiceT = Tensor(repeating: config.juiceDuration * 2, shape: [n, c])
        juiceSign = .ones([n, c])

        let phaseNoise = LaneNoise.uniforms(seed: seed, tick: 0, stream: 0, worlds: n, lanes: c)
        let freqNoise = LaneNoise.uniforms(seed: seed, tick: 0, stream: 1, worlds: n, lanes: c)
        ambientPhase = phaseNoise * (2 * Double.pi)
        ambientFrequency = freqNoise * config.ambientFrequencySpan + config.ambientFrequencyMin

        lightX = .zeros([n])
        lightZ = .zeros([n])
        prevPress = .zeros([n])
        prevFlipHalf = .zeros([n, c])
        prevDone = .zeros([n])
    }

    mutating func advanceTick() { tick &+= 1 }

    /// Boundary marshalling: the app hands one world the shuffle permutation from TarotKit
    /// (lane i gets stack position `order[i]`). Presentation replays the shuffle the Kit
    /// already decided — it never generates its own.
    public mutating func assignDeckOrder(_ order: [Int], world w: Int) {
        precondition(order.count == capacity)
        for (lane, position) in order.enumerated() {
            deckDepth.data[w * capacity + lane] = Double(position)
        }
    }
}
