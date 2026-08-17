import Foundation
import simd
import TensorKit
import RelativityKit
import PortalKit

/// The eighteen demos, as a catalog.
///
/// Each is a Kit call plus a shader configuration — never physics written here. The tier tells you
/// what a demo actually proves:
///
///   * **Tier 1 is camera-only.** It bends what you *see*. A wrench thrown in a Tier 1 scene flies
///     straight. These exist to get the look on screen early and to make the hero frame.
///   * **Tier 2 onward is world-space.** Entity state is (t, r, θ, φ) with covariant p_μ, and light
///     and matter integrate through the *same* function one mass-shell parameter apart. Frame
///     dragging genuinely moves bodies; the renderer projects curved coordinates rather than
///     filtering a flat picture.
///
/// Every demo names the published source its numbers answer to. A demo without an oracle does not
/// ship — the same rule as `kerfcalcTests.everyToolCitesAFormula`, applied to physics.
enum Demo: Int, CaseIterable, Identifiable, Sendable {
    // Tier 1 — screen-space
    case weakLensing = 1
    case gravitationalRedshift
    case dopplerAberration
    case terrellRotation
    case bubbleWall
    // Tier 2 — real geodesics
    case schwarzschildGeodesics
    case photonSphere
    case kerrGeodesics
    case ergosphereDragging
    case accretionBeaming
    case timeDilationState
    // Tier 3 — portals
    case recursivePortals
    case portalPhysics
    case einsteinRosenBridge
    case nonEuclideanStitching
    // Tier 4 — mechanics
    case penroseExtraction
    case warpTransit
    case iscoOrbitalWork

    var id: Int { rawValue }

    var tier: Int {
        switch self {
        case .weakLensing, .gravitationalRedshift, .dopplerAberration,
             .terrellRotation, .bubbleWall: return 1
        case .schwarzschildGeodesics, .photonSphere, .kerrGeodesics,
             .ergosphereDragging, .accretionBeaming, .timeDilationState: return 2
        case .recursivePortals, .portalPhysics, .einsteinRosenBridge,
             .nonEuclideanStitching: return 3
        case .penroseExtraction, .warpTransit, .iscoOrbitalWork: return 4
        }
    }

    var title: String {
        switch self {
        case .weakLensing:            return "Weak-field lensing"
        case .gravitationalRedshift:  return "Gravitational redshift"
        case .dopplerAberration:      return "Doppler & aberration"
        case .terrellRotation:        return "Terrell rotation"
        case .bubbleWall:             return "Warp bubble wall"
        case .schwarzschildGeodesics: return "Schwarzschild geodesics"
        case .photonSphere:           return "Photon sphere & Einstein ring"
        case .kerrGeodesics:          return "Kerr geodesics"
        case .ergosphereDragging:     return "Ergosphere & frame dragging"
        case .accretionBeaming:       return "Disk & Doppler beaming"
        case .timeDilationState:      return "Time dilation as state"
        case .recursivePortals:       return "Recursive stencil portals"
        case .portalPhysics:          return "Portal physics"
        case .einsteinRosenBridge:    return "Einstein–Rosen bridge"
        case .nonEuclideanStitching:  return "Non-euclidean stitching"
        case .penroseExtraction:      return "Penrose extraction"
        case .warpTransit:            return "Warp transit — horizon descent"
        case .iscoOrbitalWork:        return "ISCO orbital work"
        }
    }

    /// The published source this demo's numbers are checked against.
    var oracle: String {
        switch self {
        case .weakLensing:            return "Eddington 1919 — α = 4GM/c²b, 1.75″ at the solar limb"
        case .gravitationalRedshift:  return "Pound & Rebka 1959; GPS 45 µs/day"
        case .dopplerAberration:      return "Closed-form special relativity"
        case .terrellRotation:        return "Terrell & Penrose 1959"
        case .bubbleWall:             return "Alcubierre 1994 — interior exactly Minkowski"
        case .schwarzschildGeodesics: return "→ 4GM/c²b in the weak field"
        case .photonSphere:           return "r = 3M exactly; critical b = 3√3 M"
        case .kerrGeodesics:          return "Carter 1968 — E, L_z, Q conserved"
        case .ergosphereDragging:     return "r_E = M + √(M² − a²cos²θ), closed form"
        case .accretionBeaming:       return "Relativistic beaming, δ⁴"
        case .timeDilationState:      return "dτ/dt = √(1 − 2M/r); E conserved"
        case .recursivePortals:       return "Round-trip identity, exactly I"
        case .portalPhysics:          return "‖p‖ and E preserved across a crossing"
        case .einsteinRosenBridge:    return "Geodesics stay geodesics; E/L_z/Q survive the throat"
        case .nonEuclideanStitching:  return "Designed holonomy; even loops close"
        case .penroseExtraction:      return "Penrose 1969 — 20.7% single decay, 29% reservoir"
        case .warpTransit:            return "Alcubierre 1994 — sub-light egress from r < r+ is impossible"
        case .iscoOrbitalWork:        return "Bardeen–Press–Teukolsky 1972 — r = 6M at a = 0"
        }
    }

    /// True where the demo curves the *world*, not just the view.
    var isWorldSpace: Bool { tier >= 2 }

    /// The scripted camera for this demo, chosen to reveal what the demo is actually about.
    ///
    /// A static frame of a black disc looks identical for eight of these. Motion is what
    /// distinguishes them: radial structure (a shadow edge, a photon ring) reads on a dolly, an
    /// out-of-plane structure reads on an arc, and a portal only opens up when you swing past its
    /// face. So the move is part of the demo's content, not decoration on top of it.
    var cameraMove: CameraMove {
        switch self {
        case .weakLensing:
            return .dolly(near: 9, far: 26, period: 16,
                          intent: "dolly in and out — deflection grows as impact parameter shrinks")
        case .gravitationalRedshift:
            return .dolly(near: 6, far: 22, period: 18,
                          intent: "descend into the potential and watch the colour ramp")
        case .dopplerAberration:
            return .orbit(radius: 13, elevation: 0.12, period: 20,
                          intent: "circle — the forward hemisphere blueshifts")
        case .terrellRotation:
            return .orbit(radius: 10, elevation: 0.25, period: 14,
                          intent: "circle a fast body — it appears rotated, not contracted")
        case .bubbleWall:
            return .hold(radius: 12, elevation: 0.1,
                         intent: "hold on the boundary — flat inside, curved outside")
        case .schwarzschildGeodesics:
            return .dolly(near: 8, far: 30, period: 20,
                          intent: "approach — straight rays bend into the shadow")
        case .photonSphere:
            return .dolly(near: 6.5, far: 20, period: 22,
                          intent: "close on r = 3M until the ring separates from the shadow")
        case .kerrGeodesics:
            return .orbit(radius: 13, elevation: 0.08, period: 24,
                          intent: "orbit in the equatorial plane — the shadow is asymmetric")
        case .ergosphereDragging:
            return .arc(radius: 12, period: 26,
                        intent: "rise over the pole — the ergosphere is oblate, the horizon is not")
        case .accretionBeaming:
            return .orbit(radius: 15, elevation: 0.06, period: 22,
                          intent: "graze the plane — the approaching side is brighter")
        case .timeDilationState:
            return .hold(radius: 16, elevation: 0.2,
                         intent: "hold on both workers — their clocks diverge")
        case .recursivePortals, .portalPhysics:
            return .orbit(radius: 11, elevation: 0.15, period: 18,
                          intent: "swing past the mouth — the through-view is a real second render")
        case .einsteinRosenBridge:
            return .dolly(near: 6, far: 18, period: 20,
                          intent: "approach the throat — the far side is another region")
        case .nonEuclideanStitching:
            return .orbit(radius: 12, elevation: 0.3, period: 16,
                          intent: "circle the stitch — the loop does not close")
        case .penroseExtraction:
            return .orbit(radius: 11, elevation: 0.18, period: 20,
                          intent: "watch the fragment fall — that mass never comes back")
        case .warpTransit:
            // The descent. In through r+, and back out — which only the bubble makes possible.
            return .descend(from: 20, to: 0.55, period: 30,
                            intent: "dive through r+ and return — the return leg needs the bubble")
        case .iscoOrbitalWork:
            return .arc(radius: 14, period: 24,
                        intent: "tilt over the ISCO ring — the inner edge of anywhere you can park")
        }
    }

    /// Build the scene. Tier 1 configures the screen-space pass; Tier 2+ additionally integrates
    /// real geodesics in RelativityKit and places bodies at the result.
    func makeSnapshot(spin: Double, time: Double, camera: Snapshot.Camera) -> Snapshot {
        var snap = Snapshot()
        snap.camera = camera
        snap.coordinateTime = time
        snap.usesGeodesicPass = isWorldSpace

        let a = Tensor(shape: [1], data: [spin])
        let rPlus = Regions.outerHorizon(spin: a).data[0]
        let photon = Regions.photonOrbit(spin: a, prograde: true).data[0]

        snap.relativity.spin = Float(spin)
        snap.relativity.outerHorizon = Float(rPlus)
        snap.relativity.ergosphereEq = 2
        snap.relativity.photonSphere = Float(photon)
        // Both BPT radii, straight from the Kit that already pins them to 1M/4M at extremal spin.
        // The shader never recomputes physics; it reads numbers an oracle has already checked.
        snap.relativity.photonPrograde = Float(Regions.photonOrbit(spin: a, prograde: true).data[0])
        snap.relativity.photonRetro = Float(Regions.photonOrbit(spin: a, prograde: false).data[0])
        snap.relativity.time = Float(time)

        switch self {
        case .bubbleWall:
            // The hero frame: calm flat interior, insane exterior, one shader boundary. Alcubierre's
            // interior really is Minkowski, so drawing it undistorted is correctness, not an effect.
            snap.relativity.bubbleRadiusNDC = 0.42
            snap.relativity.lensStrength = 0.07
            snap.bodies.append(.init(kind: .cosmonaut, position: SIMD3(0, -0.4, 3), scale: 1.6,
                                     yaw: Float(0.5 + 0.2 * sin(time * 0.4))))

        case .weakLensing, .gravitationalRedshift:
            snap.relativity.lensStrength = 0.055
            snap.bodies.append(.init(kind: .cosmonaut, position: SIMD3(-3.2, -0.6, 4), scale: 1.2,
                                     yaw: 0.7))

        case .dopplerAberration, .terrellRotation:
            snap.relativity.lensStrength = 0.02
            snap.bodies.append(.init(kind: .cosmonaut, position: SIMD3(0, -0.5, 4), scale: 1.4,
                                     yaw: Float(time * 0.6)))

        case .ergosphereDragging:
            // World-space: a zero-angular-momentum body still acquires dφ/dt = ω inside the
            // ergosphere. The metric moves it; nothing here animates it by hand.
            snap.relativity.lensStrength = 0.06
            let r = Tensor(shape: [1], data: [1.9])
            let theta = Tensor(shape: [1], data: [Double.pi / 2])
            let omega = Regions.framePickupRate(r: r, theta: theta, spin: a).data[0]
            let phi = Float(omega * time * 12)
            snap.bodies.append(.init(kind: .cosmonaut,
                                     position: SIMD3(cos(phi) * 4.2, -0.3, sin(phi) * 4.2),
                                     scale: 1.1, yaw: -phi))

        case .kerrGeodesics, .schwarzschildGeodesics, .photonSphere:
            snap.relativity.lensStrength = self == .photonSphere ? 0.09 : 0.06
            snap.bodies.append(contentsOf: Self.geodesicMarkers(spin: spin, time: time))

        case .timeDilationState:
            // Two workers at different depths, ageing at different rates. dτ/dt = √(1 − 2M/r).
            snap.relativity.lensStrength = 0.05
            let radii = Tensor(shape: [2], data: [3.0, 12.0])
            let theta = Tensor(shape: [2], data: [Double.pi / 2, Double.pi / 2])
            let rate = Regions.staticRedshiftFactor(r: radii, theta: theta,
                                                    spin: Tensor(repeating: spin, shape: [2]))
            snap.properTimes = [time * rate.data[0], time * rate.data[1]]
            snap.bodies.append(.init(kind: .cosmonaut, position: SIMD3(-3, -0.4, 3), scale: 1.1))
            snap.bodies.append(.init(kind: .cosmonaut, position: SIMD3(3, -0.4, 3), scale: 1.1))

        case .einsteinRosenBridge, .recursivePortals, .portalPhysics, .nonEuclideanStitching:
            snap.relativity.lensStrength = 0.05
            // A portal pair, placed by PortalKit — the same algebra whose round-trip identity is a
            // unit test. #14 differs only in where the destination frame comes from: for the
            // Einstein-Rosen bridge it is the far mouth of the Kerr throat, past the Cauchy
            // horizon, which is why the through-view shows the cat's region rather than this one.
            let src = Portal.frame(
                centerX: Tensor(shape: [1], data: [0]), centerY: Tensor(shape: [1], data: [0]),
                centerZ: Tensor(shape: [1], data: [2]),
                forwardX: Tensor(shape: [1], data: [0]), forwardY: Tensor(shape: [1], data: [0]),
                forwardZ: Tensor(shape: [1], data: [1]),
                upX: Tensor(shape: [1], data: [0]), upY: Tensor(shape: [1], data: [1]),
                upZ: Tensor(shape: [1], data: [0]))
            let dstZ = self == .einsteinRosenBridge ? -Double(rPlus) * 4 : -9.0
            let dst = Portal.frame(
                centerX: Tensor(shape: [1], data: [self == .nonEuclideanStitching ? 5 : 0]),
                centerY: Tensor(shape: [1], data: [0]),
                centerZ: Tensor(shape: [1], data: [dstZ]),
                forwardX: Tensor(shape: [1], data: [self == .nonEuclideanStitching ? 1 : 0]),
                forwardY: Tensor(shape: [1], data: [0]),
                forwardZ: Tensor(shape: [1], data: [self == .nonEuclideanStitching ? 0 : 1]),
                upX: Tensor(shape: [1], data: [0]), upY: Tensor(shape: [1], data: [1]),
                upZ: Tensor(shape: [1], data: [0]))
            let tm = Portal.transform(source: src, destination: dst)

            // The virtual camera IS the real camera pushed through the transform. Computed here,
            // in the Kit's algebra; the renderer only looks from where it is told.
            let eye = snap.camera.eye
            let eyeH = Tensor(shape: [1, 4], data: [Double(eye.x), Double(eye.y), Double(eye.z), 1])
            let moved = Tensor.apply4x4(tm, to: eyeH).unstackLast()
            var vcam = Snapshot.Camera()
            vcam.eye = SIMD3(Float(moved[0].data[0]), Float(moved[1].data[0]),
                             Float(moved[2].data[0]))
            vcam.target = SIMD3(Float(dst.data[3]), Float(dst.data[7]), Float(dst.data[11]))
            snap.portalVirtualCamera = vcam

            snap.bodies.append(.init(kind: .portal, position: SIMD3(0, 0, 2), scale: 1.7,
                                     color: self == .einsteinRosenBridge ? Palette.voidTealBright
                                                                         : Palette.catSignal,
                                     emissive: 0.7))
            snap.bodies.append(.init(kind: .cat, position: SIMD3(0, -1.2, -6), scale: 2.4,
                                     yaw: Float(0.3 + 0.1 * sin(time * 0.3))))

        case .penroseExtraction:
            // The extraction, and the reason it is a mechanic rather than an effect: the Penrose
            // process only works if you THROW SOMETHING IN. A body splits inside the ergosphere,
            // one fragment falls past the horizon on a negative-energy orbit, and the piece that
            // escapes carries out MORE energy than you brought. Extraction requires an
            // irreversible sacrifice, by construction, and that is handed over by the physics.
            //
            // ORACLE: 20.7% maximum single-decay efficiency, 29% total rotational reservoir.
            snap.relativity.lensStrength = 0.07
            let workR = Float(Regions.ergosphereOuter(theta: Tensor(shape: [1], data: [Double.pi / 2]),
                                                      spin: a).data[0]) * 1.6
            let phiP = Float(time * 0.7)
            snap.bodies.append(.init(kind: .cosmonaut,
                                     position: SIMD3(cos(phiP) * workR, -0.2, sin(phiP) * workR),
                                     scale: 1.0, yaw: -phiP))
            // The fragment on its way in — the thing that can never be retrieved.
            let fall = Float(fmod(time * 0.5, 1.0))
            let fallR = workR * (1 - fall) + Float(rPlus) * fall
            snap.bodies.append(.init(kind: .marker,
                                     position: SIMD3(cos(phiP + 0.6) * fallR, -0.2,
                                                     sin(phiP + 0.6) * fallR),
                                     scale: 0.18,
                                     color: Palette.redshift(fall), emissive: 0.9 * (1 - fall)))

        case .warpTransit:
            // Free irreversibility: the bubble's leading edge is spacelike-separated from its
            // centre, so an occupant CANNOT signal forward and cannot steer once superluminal.
            // The trajectory is committed before departure. Causality enforces the theme.
            snap.relativity.lensStrength = 0.03
            snap.relativity.bubbleRadiusNDC = 0.34
            let committed = Float(fmod(time * 0.25, 1.0))
            snap.bodies.append(.init(kind: .cosmonaut, position: SIMD3(0, -0.4, 3), scale: 1.5,
                                     yaw: 0.4))
            // Waypoints, all fixed at launch. None of them can be altered en route.
            for i in 0..<6 {
                let f = Float(i) / 5
                snap.bodies.append(.init(kind: .marker,
                                         position: SIMD3(-6 + f * 12, 2.4, -3),
                                         scale: 0.13,
                                         color: f <= committed ? Palette.amberBright
                                                               : Palette.suitSpecular,
                                         emissive: f <= committed ? 0.95 : 0.15))
            }

        case .iscoOrbitalWork, .accretionBeaming:
            // The work site's inner edge. Below the ISCO no stable orbit exists at all, which is
            // why it bounds the shift rather than being an arbitrary safety line.
            // ORACLE: r = 6M at a = 0; 1M prograde / 9M retrograde at a = 1 (BPT 1972).
            snap.relativity.lensStrength = 0.065
            let iscoR = Regions.isco(spin: a, prograde: true).data[0]
            let phi = Float(time * 0.5)
            snap.bodies.append(.init(kind: .cosmonaut,
                                     position: SIMD3(cos(phi) * Float(iscoR), -0.2,
                                                     sin(phi) * Float(iscoR)),
                                     scale: 1.0, yaw: -phi))
            // The ISCO itself, marked out — the boundary is a number the Kit computes, not art.
            for i in 0..<24 {
                let t2 = Float(i) / 24 * 2 * Float.pi
                snap.bodies.append(.init(kind: .marker,
                                         position: SIMD3(cos(t2) * Float(iscoR), -0.9,
                                                         sin(t2) * Float(iscoR)),
                                         scale: 0.055, color: Palette.amber, emissive: 0.6))
            }
        }

        // The cat presides over every scene it is not already in — it is the consciousness of the
        // neighbouring galaxy, and it is always watching.
        if !snap.bodies.contains(where: { $0.kind == .cat }) {
            snap.bodies.append(.init(kind: .cat, position: SIMD3(0, 3.4, -14), scale: 3.0,
                                     yaw: Float(0.15 * sin(time * 0.2))))
        }
        return snap
    }

    /// Markers placed along genuinely integrated null geodesics.
    ///
    /// This is the world-space path: RelativityKit integrates, the renderer only places boxes where
    /// the physics says photons are. Nothing about the shape of these curves is authored.
    private static func geodesicMarkers(spin: Double, time: Double) -> [Snapshot.Body] {
        let n = 6
        let a = Tensor(repeating: spin, shape: [n])
        let bs = (0..<n).map { 4.0 + Double($0) * 1.6 }
        let y0 = InitialConditions.fromConstants(
            r: Tensor(repeating: 22, shape: [n]),
            theta: Tensor(repeating: Double.pi / 2, shape: [n]),
            phi: Tensor(repeating: 0, shape: [n]),
            t: Tensor(repeating: 0, shape: [n]),
            energy: Tensor(repeating: 1, shape: [n]),
            axialAngularMomentum: Tensor(shape: [n], data: bs),
            pTheta: Tensor(repeating: 0, shape: [n]),
            spin: a, restMass: Tensor(repeating: 0, shape: [n]), outward: false)

        // A bounded number of steps, advancing with the demo clock — bounded algorithmic depth,
        // which is one of the three places a loop is allowed.
        //
        // MONOTONIC and clamped. The first version was `40 + Int(time * 30) % 400`, which wraps:
        // scrubbing the time slider forward made the markers leap backwards every ~13 seconds. A
        // time control turns any non-monotonic function of t into a visible defect, which is a
        // useful side effect of having one.
        let steps = min(40 + Int(time * 30), 900)
        let y = Geodesic.integrate(y0, spin: a,
                                   dLambda: Tensor(repeating: 0.05, shape: [n]), steps: steps)
        let c = y.unstackLast()
        return (0..<n).map { i in
            let r = Float(c[Geodesic.S.r].data[i])
            let phi = Float(c[Geodesic.S.phi].data[i])
            return Snapshot.Body(kind: .marker,
                                 position: SIMD3(cos(phi) * r * 0.35, 0, sin(phi) * r * 0.35 - 4),
                                 scale: 0.10,
                                 color: Palette.redshift(Float(i) / Float(n - 1)),
                                 emissive: 0.85)
        }
    }
}
