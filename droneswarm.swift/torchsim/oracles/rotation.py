"""Batched quaternion algebra — the attitude primitive for the quadrotor oracle.

Convention (SOURCES quadrotor-ctbr §1.1): Hamilton, w-FIRST, body->world, unit quaternion
q = [w, x, y, z]. Everything is pure broadcast tensor math over arbitrary leading dims [...]; the
only numerical care is the sinc guard at ||theta||->0 in the exponential map, handled with the
mandated safe-denominator idiom (torch.where evaluates BOTH branches, so a raw 0/0 would NaN-poison
the backward pass — see SOURCES IMPLEMENTATION MANDATES). NO python loops.

Integrator: Sola "Quaternion kinematics for the error-state KF" Eq. (214)-(215) zeroth-order forward
— q_{k+1} = q_k (x) Exp(omega*dt). Exp of a rotation vector phi is a UNIT quaternion by construction,
and for a FIXED rotation axis it is EXACT for any dt (Sola Eq. (228)-(229)) — the property the unit
tests exploit.
"""
import torch


def quat_mul(q1, q2):
    """Hamilton product q1 (x) q2. q1,q2 [...,4] (w-first) -> [...,4]. Broadcasts over [...]."""
    w1, x1, y1, z1 = q1[..., 0], q1[..., 1], q1[..., 2], q1[..., 3]
    w2, x2, y2, z2 = q2[..., 0], q2[..., 1], q2[..., 2], q2[..., 3]
    return torch.stack([
        w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2,
        w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
        w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
        w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2,
    ], dim=-1)


def quat_rotate(q, v):
    """Rotate vector v [...,3] by unit quaternion q [...,4] (body->world). Efficient vector form
    (no matrix): v' = v + 2 w (u x v) + 2 u x (u x v), u = q_xyz. Loop-free."""
    w = q[..., 0:1]                                  # [...,1]
    u = q[..., 1:4]                                  # [...,3]
    uv = torch.cross(u, v, dim=-1)                   # u x v
    return v + 2.0 * (w * uv + torch.cross(u, uv, dim=-1))


def quat_normalize(q, eps=1e-9):
    """Renormalize to unit length. Safe: sqrt(sum + eps^2) never divides by zero."""
    n = torch.sqrt((q * q).sum(-1, keepdim=True) + eps * eps)
    return q / n


def quat_from_rotvec(phi, eps=1e-9):
    """Exponential map Exp(phi): rotation vector phi [...,3] (radians) -> unit quaternion [...,4].
    q = [cos(a/2), (phi/||phi||) sin(a/2)], a = ||phi||. Safe sinc at a->0: xyz factor
    = sin(a/2)/a -> 1/2, selected with torch.where BEFORE the divide (mandated idiom)."""
    a = torch.sqrt((phi * phi).sum(-1, keepdim=True) + eps * eps)     # [...,1] safe norm
    half = 0.5 * a
    w = torch.cos(half)
    # xyz = phi * sin(half)/a ; as a->0 this -> phi * 0.5. safe-denominator:
    small = a < 1e-6
    denom = torch.where(small, torch.ones_like(a), a)
    factor = torch.where(small, torch.full_like(a, 0.5), torch.sin(half) / denom)
    xyz = phi * factor
    return torch.cat([w, xyz], dim=-1)


def quat_integrate(q, omega_body, dt, eps=1e-9):
    """Advance q by body rates omega_body [...,3] over dt (Sola zeroth-order): q (x) Exp(omega*dt),
    renormalized. Exact for a fixed axis; unit by construction. q [...,4] -> [...,4]."""
    dq = quat_from_rotvec(omega_body * dt, eps)
    return quat_normalize(quat_mul(q, dq), eps)


def body_z_axis(q):
    """World-frame direction of the body +z axis (the thrust direction / drone 'up'). q [...,4] ->
    [...,3]. = quat_rotate(q, e_z); closed form of R(q) third column."""
    w, x, y, z = q[..., 0], q[..., 1], q[..., 2], q[..., 3]
    return torch.stack([2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y)], dim=-1)
