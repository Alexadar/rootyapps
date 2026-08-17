import Foundation
import simd

/// Where the camera is, and how it got there.
///
/// Two modes, and the distinction is the point:
///
///   * **Auto** — each demo carries a scripted orbit chosen to *show what that demo is about*. A
///     lensing demo wants a slow pass across the shadow's edge; a portal demo wants to swing until
///     the through-view opens up. Without this, every scene is a static frame of a black disc and
///     you cannot tell which physics is running.
///   * **Manual** — you drive. Azimuth and elevation by drag, distance by pinch or scroll.
///
/// Both produce the same `Snapshot.Camera`, so the renderer and the geodesic pass never learn which
/// one is in charge. Manual starts from wherever auto had reached, so toggling does not jump.
///
/// Pure: `camera(at:)` is a function of its stored angles and the time passed in. Nothing here
/// accumulates, which is what makes the time slider scrub cleanly in both directions.
struct CameraRig {
    /// Radians around the vertical axis. 0 looks down -Z.
    var azimuth: Float = 0
    /// Radians above the equatorial plane. Clamped short of the poles, where the basis degenerates.
    var elevation: Float = 0.18
    /// Distance from the target, in units of M.
    var distance: Float = 14
    var target = SIMD3<Float>(0, 0, 0)
    var fovRadians: Float = 1.05

    /// The camera may go INSIDE the horizon — the game's premise is a worker platform operating
    /// there in an Alcubierre bubble, so the interior is a place you work, not a wall.
    ///
    /// Floor is just outside the ring singularity (r = 0), which is the only thing here that is
    /// genuinely physical rather than a coordinate artefact.
    static let minDistance: Float = 0.25
    static let maxDistance: Float = 60
    /// Just under π/2. At exactly the pole the up-vector and the view direction become parallel and
    /// the camera basis collapses — the view flips inside out for one frame and then recovers,
    /// which reads as a rendering glitch rather than as gimbal lock.
    static let maxElevation: Float = 1.45

    mutating func orbit(deltaAzimuth: Float, deltaElevation: Float) {
        azimuth += deltaAzimuth
        elevation = min(max(elevation + deltaElevation, -Self.maxElevation), Self.maxElevation)
    }

    mutating func dolly(scale: Float) {
        distance = min(max(distance / max(scale, 0.01), Self.minDistance), Self.maxDistance)
    }

    /// Slide the point being orbited, in the camera's own right/up plane.
    ///
    /// Orbit alone can only ever look *at* the hole. Panning is what lets you put the hole off to
    /// one side and inspect something next to it — a portal mouth, the ISCO ring, the worker — which
    /// is the difference between "I can see it" and "I can tell whether it is right".
    ///
    /// Clamped: the target may not wander so far that the subject leaves the frame entirely, which
    /// is the failure mode of an unbounded pan on a small screen.
    mutating func pan(right dx: Float, up dy: Float) {
        let ce = cos(elevation), se = sin(elevation)
        let forward = SIMD3(-sin(azimuth) * ce, -se, -cos(azimuth) * ce)
        let r = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let u = simd_cross(r, forward)
        // Scale with distance so a drag moves the same number of screen pixels at any zoom.
        let k = distance * 0.02
        let moved = target + r * (dx * k) + u * (dy * k)
        let limit: Float = 24
        target = SIMD3(min(max(moved.x, -limit), limit),
                       min(max(moved.y, -limit), limit),
                       min(max(moved.z, -limit), limit))
    }

    /// Named viewpoints. Being able to jump to a *known* angle is what turns "it looks odd" into
    /// "it is wrong from the side but right from the front", which is the only way to tell a
    /// projection bug from a geometry bug.
    enum Preset: String, CaseIterable {
        case front, side, top, iso, far

        var label: String { rawValue.uppercased() }
    }

    mutating func apply(_ preset: Preset) {
        target = .zero
        switch preset {
        case .front: azimuth = 0;            elevation = 0;    distance = 14
        case .side:  azimuth = .pi / 2;      elevation = 0;    distance = 14
        case .top:   azimuth = 0;            elevation = 1.40; distance = 16
        case .iso:   azimuth = .pi / 4;      elevation = 0.55; distance = 15
        case .far:   azimuth = 0.4;          elevation = 0.20; distance = 34
        }
    }

    /// The camera this rig currently describes.
    func camera() -> Snapshot.Camera {
        var c = Snapshot.Camera()
        let ce = cos(elevation), se = sin(elevation)
        c.eye = target + SIMD3(sin(azimuth) * ce, se, cos(azimuth) * ce) * distance
        c.target = target
        c.fovRadians = fovRadians
        return c
    }

    /// Apply a demo's scripted move at time `t`. Absolute, not incremental, so scrubbing the time
    /// slider backwards retraces the same path instead of drifting.
    mutating func applyScripted(_ move: CameraMove, at t: Double) {
        azimuth = move.azimuth(t)
        elevation = move.elevation(t)
        distance = move.distance(t)
        target = move.target
        fovRadians = move.fov
    }
}

/// A scripted camera move: three closures of time, plus a fixed target.
///
/// Written as functions of absolute time rather than as an animation that plays, because the time
/// slider must be able to land anywhere — including backwards — and get the same frame every time.
struct CameraMove {
    var azimuth: (Double) -> Float
    var elevation: (Double) -> Float
    var distance: (Double) -> Float
    var target: SIMD3<Float> = .zero
    var fov: Float = 1.05
    /// One sentence on what this move is trying to reveal. Shown in the readout, so the camera is
    /// self-explaining rather than mysterious.
    var intent: String

    /// A slow orbit at fixed radius. The default reveal for anything radially symmetric.
    static func orbit(radius: Float, elevation e: Float, period: Double,
                      intent: String) -> CameraMove {
        CameraMove(azimuth: { Float($0 / period * 2 * .pi) },
                   elevation: { _ in e },
                   distance: { _ in radius },
                   intent: intent)
    }

    /// A dolly in and out between two radii, which is what shows a *radial* structure — the shadow
    /// edge, a photon ring, the ergosphere boundary — far better than circling it does.
    static func dolly(near: Float, far: Float, period: Double, azimuth az: Float = 0.4,
                      elevation e: Float = 0.2, intent: String) -> CameraMove {
        CameraMove(azimuth: { az + Float($0 * 0.08) },
                   elevation: { _ in e },
                   distance: { t in
                       let phase = (sin(t / period * 2 * .pi) + 1) * 0.5   // 0…1
                       return near + (far - near) * Float(phase)
                   },
                   intent: intent)
    }

    /// A slow arc that rises over the pole, for anything whose structure is out of the plane.
    static func arc(radius: Float, period: Double, intent: String) -> CameraMove {
        CameraMove(azimuth: { Float($0 / period * .pi) },
                   elevation: { t in Float(sin(t / period * 2 * .pi)) * 0.9 },
                   distance: { _ in radius },
                   intent: intent)
    }

    /// **The descent.** From well outside, down through the event horizon, and back out.
    ///
    /// This is the game's whole thesis as a camera move. Nothing else in the catalogue shows it,
    /// and nothing else can: crossing r+ inward is free, and coming back out is impossible for
    /// anything sub-light — so the return leg is only physical *because* the platform rides an
    /// Alcubierre bubble. The move is the argument.
    ///
    /// Slows near the crossing, where the interesting thing happens and where the chart stiffens.
    static func descend(from outer: Float, to inner: Float, period: Double,
                        intent: String) -> CameraMove {
        CameraMove(azimuth: { 0.35 + Float($0 * 0.05) },
                   elevation: { _ in 0.10 },
                   distance: { t in
                       // Triangle wave 0→1→0: in, then out. Eased so the crossing is unhurried.
                       let raw = (t.truncatingRemainder(dividingBy: period)) / period
                       let tri = raw < 0.5 ? raw * 2 : (1 - raw) * 2
                       let eased = Float(tri * tri * (3 - 2 * tri))    // smoothstep
                       return outer + (inner - outer) * eased
                   },
                   intent: intent)
    }

    /// Nearly still, drifting just enough that the frame is not a photograph.
    static func hold(radius: Float, elevation e: Float = 0.15,
                     intent: String) -> CameraMove {
        CameraMove(azimuth: { Float(sin($0 * 0.08) * 0.28) },
                   elevation: { t in e + Float(sin(t * 0.05)) * 0.05 },
                   distance: { _ in radius },
                   intent: intent)
    }
}
