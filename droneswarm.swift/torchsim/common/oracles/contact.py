"""Hunt-Crossley compliant contact — the drone<->drone penalty force (audit gap G1).

Hunt & Crossley, "Coefficient of restitution interpreted as damping in vibroimpact", J. Appl. Mech.
42:440-445 (1975): a nonlinear spring-damper whose damping scales with penetration so the contact
force is continuous at touchdown (no impulsive jump, unlike Kelvin-Voigt):

    F(delta, delta_dot) = k * delta^n + lambda * delta^n * delta_dot      (delta > 0, else 0)

delta = penetration depth (>0 when overlapping), delta_dot = penetration RATE (>0 = approaching).
n = 3/2 for Hertzian sphere contact. This is a SINGLE-PASS elementwise law over the penetration
tensor — loop-free by construction (no iterative impulse/Gauss-Seidel solver, which the no-loops
rule forbids). Residual overlap between wide contacts is accepted (stated design decision). The
coefficient of restitution relates to lambda/k and impact speed:  e ~ 1 - (2/3) (lambda/k) v_minus.

Used for soft swarm brushes (drones do NOT instakill each other on contact); drone<->enemy is the
kamikaze kill rule, drone<->terrain/obstacle is a crash, handled in the env, not here.
"""
import torch


def hunt_crossley_force(delta, delta_dot, k, lam, n=1.5):
    """Scalar contact force magnitude along the contact normal. delta [...] penetration depth,
    delta_dot [...] penetration rate (approach positive). Force is zero where delta <= 0. Damping is
    clamped so the force can never become ADHESIVE (negative) during fast separation — Hunt-Crossley
    with the standard non-sticking guard. Elementwise, no loops."""
    active = (delta > 0.0).to(delta.dtype)
    d_n = torch.clamp(delta, min=0.0) ** n
    f = k * d_n + lam * d_n * delta_dot
    return torch.clamp(f, min=0.0) * active            # non-adhesive, only while overlapping


def restitution_from_params(k, lam, v_minus):
    """Closed-form coefficient of restitution for the Hunt-Crossley model at approach speed v_minus
    (Hunt & Crossley 1975, low-loss expansion): e ~ 1 - (2/3)(lambda/k) v_minus. Used by the unit
    test to pin lambda/k against a target restitution. Scalar/tensor."""
    return 1.0 - (2.0 / 3.0) * (lam / k) * v_minus
