import Foundation

// Coordinate convention, stated once and relied on everywhere:
//
//   Right-handed, Y-up (RealityKit's convention). The ground plane is XZ.
//   Yaw is measured about +Y, from -Z toward +X, so yaw 0 faces -Z ("into the screen").
//
// The Kit uses `Double`, not `Float`, and its own vector types rather than `simd`. Two reasons, and
// both are about the oracle rather than taste. First, `simd` is a Darwin SDK module: importing it
// would break the Foundation-only rule that lets this Kit compile for a future watchOS companion.
// Second, reachability is a *boolean* — near the envelope boundary a Float rounding difference does
// not shift an answer slightly, it flips it. Double removes that entire class of flake before the
// batched GPU sim (which is Float) is ever compared against this reference.

/// A point or direction on the ground plane.
public struct Vec2: Hashable, Codable, Sendable {
    public var x: Double
    public var z: Double

    public init(_ x: Double, _ z: Double) {
        self.x = x
        self.z = z
    }

    public static let zero = Vec2(0, 0)

    public var length: Double { (x * x + z * z).squareRoot() }

    /// Yaw of this vector under the convention above.
    public var heading: Double { atan2(x, -z) }

    public func distance(to other: Vec2) -> Double { (self - other).length }

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.z + b.z) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.z - b.z) }
    public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.z * s) }

    /// The unit ground direction for a yaw.
    public static func direction(yaw: Double) -> Vec2 { Vec2(sin(yaw), -cos(yaw)) }
}

/// A point in the world.
public struct Vec3: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vec3(0, 0, 0)

    public var ground: Vec2 { Vec2(x, z) }

    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
}

/// An axis-aligned rectangle on the ground plane — a rooftop footprint.
///
/// Axis-aligned only, deliberately. Every froggo 1 building is an axis-aligned box, and keeping that
/// makes every geometric query here closed-form (a clamp, a corner maximum, a slab test) rather than
/// iterative. A rotated footprint later means adding a yaw and one rotate-into-local-space call; it
/// does not mean a different solver.
public struct Rect2: Hashable, Codable, Sendable {
    public var center: Vec2
    /// Half-extent along +X.
    public var halfX: Double
    /// Half-extent along +Z.
    public var halfZ: Double

    public init(center: Vec2, halfX: Double, halfZ: Double) {
        self.center = center
        self.halfX = halfX
        self.halfZ = halfZ
    }

    public var minX: Double { center.x - halfX }
    public var maxX: Double { center.x + halfX }
    public var minZ: Double { center.z - halfZ }
    public var maxZ: Double { center.z + halfZ }

    public func contains(_ p: Vec2) -> Bool {
        p.x >= minX && p.x <= maxX && p.z >= minZ && p.z <= maxZ
    }

    /// Shrunk on all sides. `nil` when the inset consumes the rectangle — which is the honest answer
    /// for "this roof is too small to be a landing target at this impact speed".
    public func inset(by d: Double) -> Rect2? {
        let hx = halfX - d
        let hz = halfZ - d
        guard hx > 0, hz > 0 else { return nil }
        return Rect2(center: center, halfX: hx, halfZ: hz)
    }

    /// Distance from `p` to the nearest point of the rectangle (0 if inside).
    public func nearestDistance(from p: Vec2) -> Double {
        let dx = max(minX - p.x, 0, p.x - maxX)
        let dz = max(minZ - p.z, 0, p.z - maxZ)
        return (dx * dx + dz * dz).squareRoot()
    }

    /// Distance from `p` to the farthest point of the rectangle — always a corner.
    public func farthestDistance(from p: Vec2) -> Double {
        let dx = max(abs(p.x - minX), abs(p.x - maxX))
        let dz = max(abs(p.z - minZ), abs(p.z - maxZ))
        return (dx * dx + dz * dz).squareRoot()
    }

    public var corners: [Vec2] {
        [Vec2(minX, minZ), Vec2(maxX, minZ), Vec2(maxX, maxZ), Vec2(minX, maxZ)]
    }

    /// Angular width of the rectangle as seen from `p`, in radians.
    ///
    /// This is the *subtended* width, which is an upper bound on how much aiming slack a target
    /// actually offers (the exact tolerance at a given range is the arc of the landing circle that
    /// falls inside the rectangle, and is never wider than this). It is used only as a difficulty
    /// signal, never as part of the reachability decision, so the bound is the right thing: it
    /// cannot make an unreachable roof look reachable.
    public func angularWidth(from p: Vec2) -> Double {
        guard !contains(p) else { return 2 * .pi }
        let headings = corners.map { ($0 - p).heading }
        // Unwrap onto a contiguous span before measuring, so a target straddling ±π is not reported
        // as nearly a full turn wide.
        let base = headings[0]
        let unwrapped = headings.map { h -> Double in
            var d = h - base
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            return d
        }
        return (unwrapped.max() ?? 0) - (unwrapped.min() ?? 0)
    }

    /// Where a ray from `p` along `yaw` enters and leaves the rectangle — the standard slab test.
    /// `nil` when the ray misses. Used to decide whether an intervening tower blocks a jump.
    public func rayEntryExit(from p: Vec2, yaw: Double) -> ClosedRange<Double>? {
        let d = Vec2.direction(yaw: yaw)
        var tMin = -Double.infinity
        var tMax = Double.infinity

        for (origin, dir, lo, hi) in [(p.x, d.x, minX, maxX), (p.z, d.z, minZ, maxZ)] {
            if abs(dir) < 1e-12 {
                if origin < lo || origin > hi { return nil }
            } else {
                var t0 = (lo - origin) / dir
                var t1 = (hi - origin) / dir
                if t0 > t1 { swap(&t0, &t1) }
                tMin = max(tMin, t0)
                tMax = min(tMax, t1)
                if tMin > tMax { return nil }
            }
        }
        guard tMax >= 0 else { return nil }
        return max(tMin, 0)...tMax
    }
}
