import simd

/// Where the camera is, and which way is "right".
///
/// **One definition, used by both the input layer and the renderer.** It exists because the two had
/// their own, and they disagreed: the renderer placed the eye from `(sin yaw, cos yaw)` while the
/// stick mapped strafe onto `(cos yaw, −sin yaw)`, which is the negation of screen-right. Pressing D
/// moved the pig to the left of the screen, and nothing could catch it, because each half was
/// self-consistent.
///
/// The convention, stated once:
///
///  * `yaw` is the direction the camera LOOKS along, on the ground, measured from +z toward −x.
///  * `pitch` is the camera's elevation above the thing it is looking at. Larger = higher up, looking
///    further down. "Looking up" therefore means a *smaller* pitch.
///  * Right-handed, +y up. Screen-right is `cross(forward, up)`, and for a camera looking along +z
///    that is **−x** — which is the fact the original strafe got backwards.
enum CameraFrame {

    /// Ground-projected direction the camera looks along.
    static func forward(yaw: Float) -> SIMD2<Float> { SIMD2(sin(yaw), cos(yaw)) }

    /// Ground-projected screen-right. `cross(forward, up)` with `up = +y`.
    static func right(yaw: Float) -> SIMD2<Float> { SIMD2(-cos(yaw), sin(yaw)) }

    /// Where the eye sits: back along `forward`, and up by the pitch.
    static func eye(focus: SIMD3<Float>, yaw: Float, pitch: Float,
                    distance: Float, lift: Float = 0) -> SIMD3<Float> {
        let f = forward(yaw: yaw)
        let flat = cos(pitch) * distance
        return focus + SIMD3(-f.x * flat, sin(pitch) * distance + lift, -f.y * flat)
    }

    /// A camera-relative stick, in world space. `x` is screen-right, `y` is away from the camera.
    static func worldDirection(stick: SIMD2<Float>, yaw: Float) -> SIMD2<Float> {
        forward(yaw: yaw) * stick.y + right(yaw: yaw) * stick.x
    }

    /// Shortest signed angle from `a` to `b`, in (−π, π].
    static func shortestTurn(from a: Float, to b: Float) -> Float {
        let twoPi = 2 * Float.pi
        let d = b - a
        return d - (d / twoPi).rounded() * twoPi
    }
}
