import Foundation

/// Every tuned constant of the card feel, with its provenance. No gameplay literal appears in
/// the kernel — it reads this. (The anti-drift rule producertycoon established.)
///
/// Units: **table units** (TU) for distance — the card is 0.32 TU wide — and seconds for time.
/// The renderer maps TU → metres exactly once, at the render boundary.
public struct MotionConfig: Sendable, Equatable {

    // MARK: Layout

    /// Cards in a full deck; also the lane capacity of the live game.
    public var cardCapacity = 78
    /// Spread slots. The three-card spread; slot positions below.
    public var slotCount = 3
    /// Deck stack centre. deckZ moved 0.40 → 0.47 (owner, 2026-08-17): more separation
    /// from the middle slot; the pointer clamp (tableExtentZ 0.7) still covers the grab.
    public var deckX = 0.0, deckZ = 0.47
    /// Slot centres (Past, Present, Future), left to right, above the deck.
    /// ±0.52 fits a phone's portrait frustum with the shipping camera; the first cut (±0.62)
    /// clipped the outer cards off-screen — measured in the simulator, retuned deliberately
    /// (goldens re-recorded with this change; see GoldenTrajectoryTests).
    public var slotX: [Double] = [-0.52, 0.0, 0.52]
    public var slotZ: [Double] = [-0.34, -0.34, -0.34]
    /// Per-slot rest yaw about the table normal (radians). Zero everywhere except a layout
    /// that lays a card sideways (the crossing card of the ten-card cross). Kernel-owned:
    /// which slot a lane rests in is kernel state, and a renderer-side yaw would force the
    /// renderer to track occupancy — breaking the dumb-reader contract.
    public var slotYaw: [Double] = [0, 0, 0]
    /// Per-slot rest height (TU). Zero except a slot stacked over another card (the
    /// crossing card rests a couple of thicknesses above the one it crosses).
    public var slotLift: [Double] = [0, 0, 0]
    /// A press within this radius of the deck centre grabs the top card.
    public var deckGrabRadius = 0.30
    /// A release within this radius of a free slot commits the card to it.
    public var snapRadius = 0.30
    /// Stack spacing: each card in the deck sits this far above the one under it.
    public var deckCardThickness = 0.0035
    /// The table's reachable extent; the pointer (and so the card target) clamps to ±this.
    public var tableExtentX = 1.0, tableExtentZ = 0.7

    // MARK: Drag  (Balatro `moveable.lua`, converted from its 60 fps per-frame constants)

    /// Held-card follow rate, as an exponential rate per second. Balatro/Godot-port lerp of
    /// ~0.25 per 60 fps frame ⇒ 1 − exp(−18/60) ≈ 0.26. Time-based so 60 Hz and 120 Hz feel
    /// identical (froggo2's camera lesson).
    public var followRate = 18.0
    /// Smoothing rate for the velocity estimate that drives the roll.
    public var velocityRate = 10.0
    /// Roll into the drag: radians per (TU/s) of pointer-chase velocity. Balatro's
    /// `0.015 · vel.x/dt` with vel in px/frame and a 71 px card ⇒ ≈ 0.055 rad·s/TU at our
    /// 0.32 TU card. The single coefficient that makes cards lean into motion.
    public var rollPerVelocity = 0.055
    /// Roll clamp, radians (Godot-port ±0.3 rad).
    public var rollClamp = 0.30
    /// Held lift height (TU) and its rate; scale while held (Balatro hover 1.05).
    public var heldLift = 0.07
    public var liftRate = 14.0
    public var heldScale = 1.05

    // MARK: Juice  (Balatro `juice_up` verbatim: 0.4 s, mismatched frequencies and decays)

    /// Oscillation frequencies, rad/s — scale at ~8.1 Hz, rotation at ~6.5 Hz. The deliberate
    /// mismatch (and the different decay powers below) is what reads organic, not springy.
    public var juiceScaleFrequency = 50.8
    public var juiceRotationFrequency = 40.8
    /// Envelope duration; scale decays with the cube of remaining time, rotation the square.
    public var juiceDuration = 0.4
    /// Amplitude → scale factor. Balatro ships 0.6, but size-pulsing read as "jelly, not
    /// serious" on device (owner call, 2026-08-17) — zeroed; the rotational settle below
    /// carries the landing weight on its own.
    public var juiceScaleFactor = 0.0
    /// Event amplitudes (Balatro's semantic weights, unchanged): events CARRY amplitude;
    /// whether it is ever SEEN is the liveliness law's decision below. One general gate,
    /// not per-event surgery.
    public var grabJuice = 0.3
    public var landJuice = 0.5
    public var heroLandJuice = 1.0
    /// Rotation amplitude in radians at amplitude 1 (Balatro r_amt ≈ ±0.6 · amount, sign
    /// randomized per event — the sign comes from LaneNoise).
    public var juiceRotationFactor = 0.12

    // MARK: Ambient idle  (Balatro `ambient_tilt` — cards never sit dead still)

    /// Idle tilt amplitude, radians, and the per-lane frequency band, Hz.
    /// First cut (0.010 rad at 0.55–1.15 Hz) read as "cards shaking" on the recorded reel
    /// (owner's words) — retuned to a slower, smaller breath.
    public var ambientAmplitude = 0.0042
    public var ambientFrequencyMin = 0.22
    public var ambientFrequencySpan = 0.3

    // MARK: The stillness law (owner, 2026-08-17: "no shake on land — general approach")
    //
    // ONE per-state liveliness factor multiplies EVERY decorative oscillation (juice
    // rotation, ambient breath, and any future decor channel) in the pose layer. A landed
    // card is a read card: perfectly still. The landing beat lives in haptics, particles
    // and hitstop — events, not wobble. Built as a which-chain over phase lanes, so it is
    // batch-vectorized like everything else and impossible to apply to one channel but
    // forget on another.
    public var livelinessInDeck = 1.0
    public var livelinessHeld = 1.0
    public var livelinessFlying = 0.6
    public var livelinessLanded = 0.0

    // MARK: Flight & flip  (Hearthstone pack-opening: user-paced, committed on release)

    /// Fixed flight duration from release to slot (and back to deck). Deterministic and
    /// testable; the incoming drag velocity shapes the path via the Hermite tangent.
    public var flightDuration = 0.55
    /// Arc height added at mid-flight (TU).
    public var flightArc = 0.12
    /// Card dimensions in TU (must match the renderer's card mesh — 0.32 × 0.55). Drive
    /// the flip clearance below and the pose layer's tilt clearance.
    public var cardWidth = 0.32
    public var cardLength = 0.55
    /// Extra height while the card is edge-on mid-flip, as a multiple of cardWidth.
    /// 0.62 > the geometric half-width (0.5), so the swinging corners clear the table with
    /// margin — measured on device: without this, corners clip through the surface and
    /// render as intersection triangles. NOT a decoration (never Reduce-Motion-gated):
    /// it's what keeps the card out of the table. Vanishes as the flip completes
    /// (∝ sin(flip·π)), so landings stay flush.
    public var flipClearance = 0.62
    /// Flip runs inside the flight window: starts at this normalized time and spans this
    /// fraction; apex (face passes edge-on) at the middle. Squash at apex scales the card's
    /// width down to 1 − `flipSquash` (Balatro-style squash-and-stretch, ~0.85 at apex).
    public var flipStart = 0.12
    public var flipSpan = 0.72
    public var flipSquash = 0.15

    // MARK: Foil light input

    /// Smoothing rate of the light-angle input (device gravity / cursor) fed to the shader.
    public var lightRate = 8.0

    // MARK: Modes

    /// Reduce Motion as a *kernel mode*, not a UI branch: zeroes roll, juice, ambient tilt and
    /// the flight arc, and replaces the eased flight with a linear one. Positions, lift, flip
    /// progress and every semantic event still happen — a complete presentation, not "off".
    public var reduceMotion = false

    public init() {}

    /// The shipping configuration — the three-card layout, which is also the calibration
    /// reference every other method's layout is judged against.
    public static let standard = MotionConfig()

    /// The shipping configuration with Reduce Motion on.
    public static var reduced: MotionConfig {
        var c = MotionConfig()
        c.reduceMotion = true
        return c
    }

    // MARK: Per-method layouts (2026-08-17)
    //
    // A method IS a config: the kernel never learns method identity, it reads slot
    // geometry. Every layout keeps the deck at (0, 0.47) and is sized against the
    // three-card reference row (z = −0.34, x = ±0.52, 0.32×0.55 cards). The camera fit is
    // COMPUTED from these arrays by the renderer (CameraFit) — nothing here is framed by
    // hand, so a slot moved here reframes the shot automatically.

    /// One card, centred where the middle of the three would sit, pulled slightly toward
    /// the viewer so a single card doesn't float in the table's dead centre.
    public static let oneCard: MotionConfig = {
        var c = MotionConfig()
        c.slotCount = 1
        c.slotX = [0.0]
        c.slotZ = [-0.22]
        c.slotYaw = [0]
        c.slotLift = [0]
        return c
    }()

    /// The three-card layout under its method name.
    public static let threeCard = standard

    /// Five cards as a literal crossroads — an X. Centre card, two roads ahead (NW/NE),
    /// two grounds behind (SW/SE). Horizontal neighbours are 0.50 apart (> 0.32 card
    /// width); the rows are 0.58 apart (> 0.55 card length); the SE ground stays 0.68 from
    /// the deck centre (> 0.30 grab radius).
    public static let fiveCrossroads: MotionConfig = {
        var c = MotionConfig()
        c.slotCount = 5
        c.slotX = [0.0, -0.50, 0.50, -0.50, 0.50]
        c.slotZ = [-0.28, -0.57, -0.57, 0.01, 0.01]
        c.slotYaw = [Double](repeating: 0, count: 5)
        c.slotLift = [Double](repeating: 0, count: 5)
        return c
    }()

    /// The ten-card cross-and-staff. Cards scale to 0.60 (0.192 × 0.33 TU) — the owner's
    /// rule is cards never shrink *to fit the camera* (the camera computes its own fit);
    /// this scale is the method's own character: ten small cards, one dense terrain.
    /// Cross centred at x = −0.38; slot 1 (index 1) lies ACROSS slot 0: same centre,
    /// yaw π/2, resting two thicknesses up. Staff at x = 0.68, spaced 0.36 (> 0.33 card
    /// length). tableExtentZ grows so the pointer clamp reaches the staff's far slots.
    /// Slots 0/1 share a centre: the release chooser's strict `<` keeps the earlier free
    /// slot, so the heart fills before the crossing card — asserted in a test.
    public static let celticCross: MotionConfig = {
        var c = MotionConfig()
        c.slotCount = 10
        c.cardWidth = 0.192
        c.cardLength = 0.33
        c.tableExtentZ = 0.85
        // Slot order follows the METHOD's position order (heart, crossing, foundation,
        // what-passes, crown, what-approaches, then the staff): foundation lies BELOW the
        // heart (+z, toward the viewer), the crown ABOVE, what-passes behind-left,
        // what-approaches ahead-right — the traditional arms. (First cut had
        // foundation/crown swapped onto the wrong arms — caught reading the rendered
        // German frame, fixed 2026-08-17; the Celtic golden was re-recorded for it.)
        //           heart  cross  below   left  above  right   staff ↓
        c.slotX = [-0.38, -0.38, -0.38, -0.78, -0.38, 0.02, 0.68, 0.68, 0.68, 0.68]
        c.slotZ = [-0.18, -0.18, 0.22, -0.18, -0.58, -0.18, 0.30, -0.06, -0.42, -0.78]
        c.slotYaw = [0, Double.pi / 2, 0, 0, 0, 0, 0, 0, 0, 0]
        c.slotLift = [0, 0.007, 0, 0, 0, 0, 0, 0, 0, 0]
        return c
    }()
}
