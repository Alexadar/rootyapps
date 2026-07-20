"""Aerodynamics oracle — body drag + ground effect for the quadrotor.

DRAG: the single ACTIVE model is QUADRATIC body drag (SOURCES aero §1; conflict-#2 resolution). All
coefficients are MASS-NORMALIZED so the oracle returns ACCELERATION (force/mass):
    a_drag = -(c2 |v_air|) v_air  -  c1 v_air         [c2 = 0.5 rho Cd A / m ; c1 = linear rotor drag]
with v_air = v - v_wind the air-relative velocity. In the game c1 (drag_lin) = 0 (SOURCES: the
ICRA22 lumped-linear fit is a near-hover model; at cruise the quadratic term dominates). c1 is kept
only for the gym-pybullet-drones parity path. Do NOT stack both against the same platform.

GROUND EFFECT: Cheeseman-Bennett thrust augmentation (SOURCES aero §1; conflict-#3 AUGMENTATION
convention): T_IGE/T_OGE = 1/(1 - (R/4z)^2) >= 1, -> 1 as z -> inf. The pole at z = R/4 is removed by
clamping the altitude floor. Returned as a thrust MULTIPLIER (>= 1).

Pure broadcast tensor ops, NO loops. Safe sqrt/denominators throughout.
"""
import torch


def drag_accel(v_air, drag_quad, drag_lin=0.0, eps=1e-9):
    """Mass-normalized drag acceleration. v_air [...,3] -> [...,3]. Quadratic (active) + optional
    linear. a = -(c2 |v_air|) v_air - c1 v_air. Safe speed norm."""
    speed = torch.sqrt((v_air * v_air).sum(-1, keepdim=True) + eps * eps)   # [...,1]
    return -(drag_quad * speed) * v_air - drag_lin * v_air


def ground_effect_factor(z_agl, rotor_radius, ge_coef=1.0, floor_frac=0.35, ge_max=4.0):
    """Cheeseman-Bennett thrust multiplier (>= 1). z_agl [...] height above ground level [m] ->
    [...]. ratio = 1/(1 - (R/4z)^2); altitude floored at floor_frac*R to skip the pole; blended by
    ge_coef and capped at ge_max. -> 1 as z -> inf. Safe."""
    R = rotor_radius
    z = torch.clamp(z_agl, min=floor_frac * R)
    x = (R / (4.0 * z)) ** 2                                        # (R/4z)^2 in [0, ~0.51]
    ratio = 1.0 / torch.clamp(1.0 - x, min=1.0 - (1.0 / (4.0 * floor_frac)) ** 2)
    factor = 1.0 + ge_coef * (ratio - 1.0)
    return torch.clamp(factor, min=1.0, max=ge_max)
