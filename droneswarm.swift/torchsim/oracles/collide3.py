"""vec3 SDF shape base — the 3D generalization of the family obstacle primitive (froggo _box_sdf /
monstro _shape_sdf_grad). Two shape kinds selected by a per-shape flag (monstro _has_sq torch.where
idiom): axis-aligned BOX (rocks, tanks) and vertical CYLINDER (tree trunks). One code path, no
bespoke per-kind math elsewhere (obstacle-shape-primitives rule). Pure broadcast ops, NO loops.

SDF sign convention: negative inside the shape, positive outside; gradient points OUTWARD (away from
the surface) and is unit-length outside. dvec = point - shape_center. Cylinder axis is world +z;
its `half` packs (radius, radius, half_height) — only half[...,0] (radius) and half[...,2]
(half-height) are read, so a box and a cylinder share the same [...,3] half-extent tensor.
"""
import torch


def _box_sdf(dvec, half):
    """AABB signed distance. dvec [...,3], half [...,3] -> [...]."""
    q = dvec.abs() - half
    outside = torch.clamp(q, min=0.0)
    return torch.sqrt((outside * outside).sum(-1) + 1e-12) + torch.clamp(q.amax(-1), max=0.0)


def _cyl_sdf(dvec, half):
    """Vertical cylinder (axis z) signed distance. radius = half[...,0], half-height = half[...,2].
    Reduce to a 2D box SDF in (radial, axial) space -> exact. dvec [...,3] -> [...]."""
    r = torch.sqrt((dvec[..., :2] * dvec[..., :2]).sum(-1) + 1e-12)   # radial distance
    d_rad = r - half[..., 0]                                          # signed radial
    d_ax = dvec[..., 2].abs() - half[..., 2]                          # signed axial
    q0 = torch.clamp(d_rad, min=0.0)
    q1 = torch.clamp(d_ax, min=0.0)
    return torch.sqrt(q0 * q0 + q1 * q1 + 1e-12) + torch.clamp(torch.maximum(d_rad, d_ax), max=0.0)


def shape_sdf3(dvec, half, is_cyl):
    """SDF of a bundle of shapes at points dvec [...,K,3], half [...,K,3], is_cyl [...,K] (1=cylinder,
    0=box) -> [...,K]. torch.where over the shape flag; one path for physics + line-of-sight."""
    sdf_box = _box_sdf(dvec, half)
    sdf_cyl = _cyl_sdf(dvec, half)
    return torch.where(is_cyl > 0.5, sdf_cyl, sdf_box)


def shape_sdf3_grad(dvec, half, is_cyl, eps=1e-9):
    """SDF + outward unit gradient. dvec [...,K,3], half/is_cyl as above -> (sdf [...,K], grad
    [...,K,3]). Analytic gradient (froggo _box_sdf_grad extended to 3D + cylinder). Safe denominators
    on every norm (mandated idiom). Grad is unit-length outside; inside it points out the nearest face."""
    # ---- BOX ----
    q = dvec.abs() - half                                            # [...,K,3]
    sgn = torch.where(dvec >= 0, torch.ones_like(dvec), -torch.ones_like(dvec))
    qp = torch.clamp(q, min=0.0)
    Lout = torch.sqrt((qp * qp).sum(-1) + eps * eps)                 # [...,K]
    inside_box = q.amax(-1) < 0.0                                    # [...,K]
    sdf_box = torch.where(inside_box, q.amax(-1), Lout)
    grad_box_out = (qp * sgn) / Lout[..., None]                      # outside: normalized outward
    # inside: push out the axis with the largest (closest-to-zero) q -> the nearest face
    amax_axis = q.argmax(-1, keepdim=True)                           # [...,K,1]
    onehot = torch.zeros_like(q).scatter(-1, amax_axis, 1.0)
    grad_box_in = sgn * onehot
    grad_box = torch.where(inside_box[..., None], grad_box_in, grad_box_out)

    # ---- CYLINDER (axis z) ----
    r = torch.sqrt((dvec[..., :2] * dvec[..., :2]).sum(-1) + eps * eps)   # [...,K] radial
    d_rad = r - half[..., 0]
    d_ax = dvec[..., 2].abs() - half[..., 2]
    radial_dir = torch.cat([dvec[..., :2] / r[..., None],                 # outward radial unit (xy)
                            torch.zeros_like(dvec[..., 2:3])], -1)
    axial_dir = torch.cat([torch.zeros_like(dvec[..., :2]),
                           torch.sign(dvec[..., 2:3])], -1)               # +/- z
    q0 = torch.clamp(d_rad, min=0.0)
    q1 = torch.clamp(d_ax, min=0.0)
    Lout_c = torch.sqrt(q0 * q0 + q1 * q1 + eps * eps)
    inside_cyl = torch.maximum(d_rad, d_ax) < 0.0
    sdf_cyl = torch.where(inside_cyl, torch.maximum(d_rad, d_ax), Lout_c)
    grad_cyl_out = (radial_dir * q0[..., None] + axial_dir * q1[..., None]) / Lout_c[..., None]
    use_rad = (d_rad >= d_ax)[..., None]                             # inside: nearest of side vs cap
    grad_cyl_in = torch.where(use_rad, radial_dir, axial_dir)
    grad_cyl = torch.where(inside_cyl[..., None], grad_cyl_in, grad_cyl_out)

    sdf = torch.where(is_cyl > 0.5, sdf_cyl, sdf_box)
    grad = torch.where(is_cyl[..., None] > 0.5, grad_cyl, grad_box)
    return sdf, grad


def segment_clearance(p0, d, xy, half, is_cyl, mask, radius, eps=1e-9):
    """Min signed clearance of the SEGMENT p0 -> p0+d past a bundle of shapes, inflated by `radius`.
    <0 => the segment enters a shape. THE shared line-of-fire / line-of-SIGHT rule (monstro
    _rock_margin generalized to 3D) — reused by the AA projectile occlusion AND the sensor-channel
    line-of-sight test, so perception can never lie about the sim. p0,d [...,3]; xy [...,K,3];
    half/is_cyl/mask [...,K] -> [...]. Single-point form: SDF at the segment point closest to each
    shape CENTER, minus radius. Loop-free (broadcast over K)."""
    f = xy - p0[..., None, :]                                        # [...,K,3] p0 -> shape center
    dd = (d * d).sum(-1, keepdim=True) + eps                         # [...,1]
    t = ((f * d[..., None, :]).sum(-1) / dd).clamp(0.0, 1.0)         # [...,K] closest-approach param
    closest = t[..., None] * d[..., None, :] - f                     # shape center -> closest segment point
    marg = shape_sdf3(closest, half, is_cyl) - radius                # [...,K]
    return (marg + (1.0 - mask) * 1e9).amin(-1)                      # padded shapes -> +inf


def raycast_aabb(o, d, centers, halfs, mask, max_range, eps=1e-6):
    """Nearest-surface distance along each ray, treating every obstacle as its AXIS-ALIGNED BOUNDING BOX
    (a box IS its AABB; a cylinder's `half`=(r,r,hz) already IS its AABB). Analytic slab method — exact,
    NO march loop. This is the drone's egocentric depth sensor (a mini-LiDAR): it sees raw geometry, not
    obstacle types (prefer-learnable-features). Loop-free, broadcast over the K rays and O obstacles.

    o [...,3] ray origins, d [...,K,3] unit ray dirs, centers/halfs [...,O,3], mask [...,O] (1=valid).
    Returns [...,K] the nearest hit distance along each ray, clamped to max_range (no hit -> max_range)."""
    o2 = o[..., None, None, :]                                       # [...,1,1,3]  origin (broadcast K,O)
    d2 = d[..., :, None, :]                                          # [...,K,1,3]  ray dir  (broadcast O)
    d2 = torch.where(d2.abs() < eps, torch.full_like(d2, eps), d2)   # avoid 0*inf on axis-parallel components
    inv = 1.0 / d2                                                   # [...,K,1,3]
    lo = (centers - halfs)[..., None, :, :]                          # [...,1,O,3]  box min corner
    hi = (centers + halfs)[..., None, :, :]                          # [...,1,O,3]  box max corner
    t1 = (lo - o2) * inv                                             # [...,K,O,3]  slab entry/exit per axis
    t2 = (hi - o2) * inv
    t_near = torch.minimum(t1, t2).amax(-1)                          # [...,K,O]  ray enters the box here
    t_far = torch.maximum(t1, t2).amin(-1)                           # [...,K,O]  ray exits the box here
    valid = mask[..., None, :] > 0.5                                 # [...,1,O] -> [...,K,O]
    hit = (t_far >= torch.clamp(t_near, min=0.0)) & (t_far >= 0.0) & valid    # slab overlap AND box ahead
    far = torch.full_like(t_near, max_range)
    dist = torch.where(hit, torch.clamp(t_near, min=0.0), far)       # inside a box (t_near<0) -> 0 distance
    return dist.amin(-1).clamp(max=max_range)                        # [...,K] nearest obstacle per ray
