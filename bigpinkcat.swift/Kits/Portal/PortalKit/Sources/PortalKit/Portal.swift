import Foundation
import TensorKit

/// Portal pairs: the transform algebra, crossing detection, and holonomy.
///
/// Pure, stateless. Batched `[N, P, 4, 4]` throughout — N worlds, P portal pairs — so a level and
/// four thousand candidate levels take the same code path.
///
/// # The transform
///
/// A portal pair is two oriented frames. Going in the front of A and out the front of B is
///
///     T = P_B · flip · P_A⁻¹
///
/// where `flip` is a 180° rotation about the frame's up-axis: without it you would exit *walking
/// into* the destination portal's back face. This is exactly Portal's construction, and it is also
/// exactly how an Einstein–Rosen bridge behaves when its two mouths are identified — the difference
/// being where the frames come from, not what the algebra does.
///
/// # Why crossing is arithmetic
///
/// `newlyCrossed = crossedNow * (1 − crossedPrevious)` — the vector form of `if justHappened`. No
/// branch, no per-entity loop, and identical cost whether nothing crossed or everything did.
public enum Portal {

    // MARK: - Frames

    /// Build a portal frame from a centre, a forward normal and an up vector, as `[.., 4, 4]`.
    ///
    /// Row-major, with translation in the last column, matching `Tensor.apply4x4`.
    public static func frame(centerX: Tensor, centerY: Tensor, centerZ: Tensor,
                             forwardX: Tensor, forwardY: Tensor, forwardZ: Tensor,
                             upX: Tensor, upY: Tensor, upZ: Tensor) -> Tensor {
        // right = up × forward, then re-orthogonalise up = forward × right, so a caller's
        // approximate up does not shear the basis. All elementwise; no per-portal loop.
        let fLen = (forwardX * forwardX + forwardY * forwardY + forwardZ * forwardZ).sqrtClamped
        let fx = forwardX / fLen, fy = forwardY / fLen, fz = forwardZ / fLen

        let rx = upY * fz - upZ * fy
        let ry = upZ * fx - upX * fz
        let rz = upX * fy - upY * fx
        let rLen = (rx * rx + ry * ry + rz * rz).sqrtClamped
        let nrx = rx / rLen, nry = ry / rLen, nrz = rz / rLen

        let ux = fy * nrz - fz * nry
        let uy = fz * nrx - fx * nrz
        let uz = fx * nry - fy * nrx

        let zero = Tensor(repeating: 0, shape: centerX.shape)
        let one = Tensor(repeating: 1, shape: centerX.shape)
        // Rows: [right | up | forward | translation]
        return Tensor.stackLast([
            nrx, ux, fx, centerX,
            nry, uy, fy, centerY,
            nrz, uz, fz, centerZ,
            zero, zero, zero, one,
        ]).reshaped(centerX.shape + [4, 4])
    }

    /// Invert a rigid frame `[.., 4, 4]` — transpose the rotation, negate the rotated translation.
    ///
    /// Cheaper and better conditioned than a general inverse, and valid because `frame(...)` only
    /// ever produces orthonormal bases. A general 4×4 inverse here would introduce error that the
    /// round-trip identity test would then have to tolerate, which would blunt the oracle.
    public static func invertRigid(_ m: Tensor) -> Tensor {
        precondition(m.shape.suffix(2) == [4, 4])
        let c = m.reshaped(Array(m.shape.dropLast(2)) + [16]).unstackLast()
        // Row-major indices: rotation is c[0..2], c[4..6], c[8..10]; translation c[3], c[7], c[11].
        let r00 = c[0], r01 = c[1], r02 = c[2], tx = c[3]
        let r10 = c[4], r11 = c[5], r12 = c[6], ty = c[7]
        let r20 = c[8], r21 = c[9], r22 = c[10], tz = c[11]

        // Transposed rotation.
        let i00 = r00, i01 = r10, i02 = r20
        let i10 = r01, i11 = r11, i12 = r21
        let i20 = r02, i21 = r12, i22 = r22
        // -Rᵀ t
        let itx = -(i00 * tx + i01 * ty + i02 * tz)
        let ity = -(i10 * tx + i11 * ty + i12 * tz)
        let itz = -(i20 * tx + i21 * ty + i22 * tz)

        let zero = Tensor(repeating: 0, shape: r00.shape)
        let one = Tensor(repeating: 1, shape: r00.shape)
        return Tensor.stackLast([
            i00, i01, i02, itx,
            i10, i11, i12, ity,
            i20, i21, i22, itz,
            zero, zero, zero, one,
        ]).reshaped(Array(m.shape.dropLast(2)) + [4, 4])
    }

    /// A 180° rotation about the up (Y) axis, as `[.., 4, 4]`.
    ///
    /// The half-turn that makes you exit *out* of the destination portal rather than into its back.
    /// Exact — all entries are ±1 or 0 — so it contributes no error to the round-trip identity.
    public static func flip(shape: [Int]) -> Tensor {
        let zero = Tensor(repeating: 0, shape: shape)
        let one = Tensor(repeating: 1, shape: shape)
        let minusOne = Tensor(repeating: -1, shape: shape)
        return Tensor.stackLast([
            minusOne, zero, zero, zero,
            zero, one, zero, zero,
            zero, zero, minusOne, zero,
            zero, zero, zero, one,
        ]).reshaped(shape + [4, 4])
    }

    /// The pair transform `T = P_dst · flip · P_src⁻¹`.
    public static func transform(source: Tensor, destination: Tensor) -> Tensor {
        let shape = Array(source.shape.dropLast(2))
        let f = flip(shape: shape)
        return Tensor.matmul4x4(destination, Tensor.matmul4x4(f, invertRigid(source)))
    }

    // MARK: - Crossing

    /// Signed distance of points `[.., 4]` (homogeneous) from each portal plane.
    ///
    /// Positive in front of the portal, negative behind. The plane's normal is the frame's forward
    /// axis, which is column 2 of the rotation.
    public static func signedDistance(points p: Tensor, frame m: Tensor) -> Tensor {
        let c = m.reshaped(Array(m.shape.dropLast(2)) + [16]).unstackLast()
        let fx = c[2], fy = c[6], fz = c[10]
        let tx = c[3], ty = c[7], tz = c[11]
        let v = p.unstackLast()
        return (v[0] - tx) * fx + (v[1] - ty) * fy + (v[2] - tz) * fz
    }

    /// Edge detection: which entities crossed a portal plane *this tick*.
    ///
    /// `newly = now · (1 − previous)`. This is froggo2's rule verbatim and it is the whole reason
    /// there is no `if justTeleported` anywhere in this codebase.
    public static func newlyCrossed(distanceNow: Tensor, distancePrevious: Tensor) -> Tensor {
        let now = distanceNow .< 0.0
        let before = distancePrevious .< 0.0
        return Tensor.newlySet(now: now, previous: before)
    }

    /// Teleport positions through a portal, gated by a mask — a masked matrix multiply, never a
    /// branch. Entities that did not cross are returned unchanged, at identical cost.
    public static func teleport(points p: Tensor, transform tm: Tensor, mask: Tensor) -> Tensor {
        let moved = Tensor.apply4x4(tm, to: p)
        let m4 = mask.expandedLast(4)
        return Tensor.which(m4, moved, p)
    }

    /// Transform a velocity through a portal: the rotation part only, no translation.
    ///
    /// Momentum magnitude is preserved because the rotation is orthonormal — which is asserted, not
    /// assumed, by `PortalOracleTests`.
    public static func rotateVector(_ v: Tensor, transform tm: Tensor, mask: Tensor) -> Tensor {
        let c = tm.reshaped(Array(tm.shape.dropLast(2)) + [16]).unstackLast()
        let x = v.unstackLast()
        let nx = c[0] * x[0] + c[1] * x[1] + c[2] * x[2]
        let ny = c[4] * x[0] + c[5] * x[1] + c[6] * x[2]
        let nz = c[8] * x[0] + c[9] * x[1] + c[10] * x[2]
        let rotated = Tensor.stackLast([nx, ny, nz, x.count > 3 ? x[3] : nx * 0])
        let m4 = mask.expandedLast(x.count)
        return Tensor.which(m4, rotated, v)
    }

    // MARK: - Holonomy

    /// Compose a loop of transforms and report how far it misses the identity.
    ///
    /// In flat space a closed loop of portals composes to I. In a deliberately non-euclidean
    /// stitching it does not, and the amount by which it fails **is the design** — you specify the
    /// rotation a lap should impart and then assert the geometry delivers exactly that. Which makes
    /// even the impossible architecture oracle-backed: the expected value comes from the level
    /// design document, not from whatever the code happens to emit.
    public static func holonomy(_ transforms: [Tensor]) -> Tensor {
        precondition(!transforms.isEmpty, "an empty loop has no holonomy")
        var acc = transforms[0]
        for i in 1..<transforms.count {
            acc = Tensor.matmul4x4(transforms[i], acc)
        }
        return acc
    }

    /// Frobenius distance of `[.., 4, 4]` from the identity — zero iff the loop closes.
    public static func deviationFromIdentity(_ m: Tensor) -> Tensor {
        let identity = Tensor.identity4x4(batches: Array(m.shape.dropLast(2)))
        let d = m - identity
        return (d * d).reshaped(Array(m.shape.dropLast(2)) + [16]).sumLast().sqrtClamped
    }
}
