import CardMotionKit
import Foundation
import simd

/// The camera's framing, COMPUTED — never tuned per method (owner, 2026-08-17: "calculate
/// mathematically"). Cards keep their size; the boom slides along its fixed ray until the
/// whole layout fits the current viewport, and every change of the answer is reached by the
/// renderer's smooth lerp, never a cut.
///
/// Pure: (layout config, viewport aspect) → boom distance. The three-card layout is the
/// calibration point — on the reference portrait phone it computes EXACTLY the shipping
/// boom distance (by construction: the calibration factor is derived from it), and no
/// layout is ever framed closer than that shipping distance.
enum CameraFit {

    /// The shipping boom, unchanged since the first build: the fixed ray every fit slides
    /// along, and the minimum distance any fit may choose.
    static let homeLook = SIMD3<Double>(0, 0, 0.05)
    static let homeCamera = SIMD3<Double>(0, 2.75, 1.72)
    /// Must match the PerspectiveCamera in the renderer (vertical FOV).
    static let fovDegrees = 55.0
    /// Margin around the layout's bounding box, TU — room for pool glows and labels.
    static let pad = 0.18
    /// The aspect the calibration is anchored to (390 × 844 portrait phone).
    static let referenceAspect = 390.0 / 844.0

    static var homeDistance: Double { simd_length(homeCamera - homeLook) }

    /// Boom unit vector, look → camera. The fit only ever slides along this ray.
    static var boomDirection: SIMD3<Double> { simd_normalize(homeCamera - homeLook) }

    /// The layout's bounding corners on the table plane: every slot's footprint (a yawed
    /// slot swaps its half-extents — the crossing card lies sideways) plus the deck's.
    static func corners(of config: MotionConfig) -> [(x: Double, z: Double)] {
        var points: [(Double, Double)] = []
        func add(x: Double, z: Double, halfX: Double, halfZ: Double) {
            for sx in [-1.0, 1.0] {
                for sz in [-1.0, 1.0] {
                    points.append((x + sx * (halfX + pad), z + sz * (halfZ + pad)))
                }
            }
        }
        let w = config.cardWidth / 2, l = config.cardLength / 2
        for s in 0..<config.slotCount {
            let yaw = config.slotYaw[s]
            let hx = abs(cos(yaw)) * w + abs(sin(yaw)) * l
            let hz = abs(sin(yaw)) * w + abs(cos(yaw)) * l
            add(x: config.slotX[s], z: config.slotZ[s], halfX: hx, halfZ: hz)
        }
        add(x: config.deckX, z: config.deckZ, halfX: w, halfZ: l)
        return points
    }

    /// The uncalibrated fit: the smallest boom distance at which every corner sits inside
    /// the frustum. Because the boom ray is fixed, each corner's camera-space x and y are
    /// CONSTANT in the distance and only its depth grows — so each frustum constraint
    /// solves to a closed-form minimum distance; the answer is the max over all of them.
    static func rawDistance(config: MotionConfig, aspect: Double) -> Double {
        let u = boomDirection                      // (0, ky, kz)
        let ky = u.y, kz = u.z
        let tanV = tan(fovDegrees * .pi / 360)
        let tanH = tanV * aspect
        var d = 0.0
        for (px, pz) in corners(of: config) {
            let dx = px - homeLook.x
            let dz = pz - homeLook.z
            // Camera space at boom distance t: xCam = dx, yCam = −ky·dz, depth = t − kz·dz.
            let horizontal = abs(dx) / tanH + kz * dz
            let vertical = ky * abs(dz) / tanV + kz * dz
            d = max(d, horizontal, vertical)
        }
        return d
    }

    /// The conservative box math over-frames slightly; anchoring it to the shipping layout
    /// removes the bias without a hand-tuned constant: on the reference phone, the
    /// three-card layout's answer IS the shipping distance.
    static var calibration: Double {
        homeDistance / rawDistance(config: .standard, aspect: referenceAspect)
    }

    /// The fit: calibrated, and never closer than the shipping boom.
    static func distance(config: MotionConfig, aspect: Double) -> Double {
        max(rawDistance(config: config, aspect: aspect) * calibration, homeDistance)
    }

    static func cameraPosition(config: MotionConfig, aspect: Double) -> SIMD3<Double> {
        homeLook + boomDirection * distance(config: config, aspect: aspect)
    }
}
