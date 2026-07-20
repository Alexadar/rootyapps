"""Ground-unit motion oracles — toy tank (unicycle) + toy soldier (Helbing social force) + Tobler
slope-speed factor. SOURCES ground-units.

  * unicycle_step   — differential-drive/unicycle kinematics (LaValle; Siegwart & Nourbakhsh): the
    tank's body-frame (v, omega) integrated to world pose. Constant (v,omega) traces a circle of
    radius v/omega (the unit-test oracle).
  * social_force    — Helbing & Molnar (PRE 1995) / Helbing et al. (Nature 2000): driving term
    (v0 e - v)/tau + agent-agent repulsion A exp((r_ij - d_ij)/B) n_ij + obstacle wall term. Published
    parameter values (A=2000, B=0.08, tau=0.5, m=80). Pairwise over agents (bounded E; top-K for
    large swarms per the audit). The soldier's accel.
  * tobler_factor   — Tobler's hiking function W(S)=exp(-3.5|S+0.05|), normalized to W(0), giving a
    slope-dependent speed multiplier (max at the -2.86% downgrade). Applies to BOTH unit types.

Pure broadcast tensor ops, safe denominators, NO loops.
"""
import torch


def unicycle_step(pos, heading, v_cmd, omega_cmd, slope_fac, dt):
    """Tank unicycle kinematics. pos [...,2], heading [...], v_cmd [...] (m/s), omega_cmd [...] (rad/s),
    slope_fac [...] (Tobler multiplier). Returns (pos, heading). Constant (v,omega) => circle radius
    v/omega. Loop-free."""
    heading = heading + omega_cmd * dt
    v = v_cmd * slope_fac
    step = torch.stack([torch.cos(heading), torch.sin(heading)], dim=-1) * (v * dt)[..., None]
    return pos + step, heading


def tobler_factor(slope_along):
    """Tobler hiking-function speed multiplier, normalized to flat ground. slope_along [...] = terrain
    slope in the direction of travel (dz/d(horizontal), i.e. tan of the grade) -> [...]. W(S)=
    exp(-3.5 |S + 0.05|); factor = W(S)/W(0), W(0)=exp(-0.175). Max ( >1 ) at S=-0.05, falls on climbs
    and steep descents. Loop-free."""
    W = torch.exp(-3.5 * torch.abs(slope_along + 0.05))
    W0 = torch.exp(torch.as_tensor(-0.175, dtype=slope_along.dtype, device=slope_along.device))
    return W / W0


def social_force(pos, vel, desired_vel, alive, A, B, tau, radius,
                 obst_sdf=None, obst_grad=None, A_w=None, B_w=None, eps=1e-6):
    """Helbing social-force acceleration for a set of pedestrians. pos/vel/desired_vel [...,E,2],
    alive [...,E] -> accel [...,E,2]. Driving (v0 e - v)/tau + Σ_j A exp((2r - d_ij)/B) n_ij over
    OTHER alive agents + optional wall term A_w exp((r - sdf)/B_w) grad. Pairwise over E (broadcast,
    no loops); self/dead pairs masked. Safe denominators."""
    drive = (desired_vel - vel) / tau                             # [...,E,2]

    # agent-agent repulsion (pairwise)
    d = pos[..., :, None, :] - pos[..., None, :, :]               # [...,E,E,2] j -> i (points away from j)
    dist = torch.sqrt((d * d).sum(-1) + eps * eps)                # [...,E,E]
    nij = d / dist[..., None]                                     # unit away-from-neighbor
    En = pos.shape[-2]
    eye = torch.eye(En, device=pos.device, dtype=torch.bool).view(*([1] * (pos.dim() - 2)), En, En)
    pair = alive[..., :, None] * alive[..., None, :]              # both alive
    pair = pair * (~eye).to(pair.dtype)                          # not self
    mag = A * torch.exp((2.0 * radius - dist) / B)                # repulsion magnitude [...,E,E]
    rep = (mag[..., None] * nij * pair[..., None]).sum(-2)        # sum over neighbors -> [...,E,2]

    accel = drive + rep
    if obst_sdf is not None:
        aw = A if A_w is None else A_w
        bw = B if B_w is None else B_w
        wall_mag = aw * torch.exp((radius - obst_sdf) / bw)       # [...,E]
        accel = accel + wall_mag[..., None] * obst_grad          # push along +outward SDF gradient
    return accel * alive[..., None]                              # dead agents get zero accel
