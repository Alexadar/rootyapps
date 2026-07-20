"""Anti-air fire oracle — lead-intercept aim + CEP hit probability + deterministic hit resolution
(SOURCES aa-fire; McCoy exterior ballistics, military-OR Rayleigh/CEP, standard intercept quadratic).

Tiered hybrid (see SOURCES): the toy TANK fires a true drag projectile (reuses the env's 3D bullet
integrator; `flat_fire_*` here are its test oracles), the toy SOLDIER uses CEP HITSCAN via `p_hit`.
`lead_solution` gives the constant-velocity intercept aim for both. `resolve_fire` turns a P(hit)
into a deterministic hit using a PREGENERATED uniform roll (schedule table) — the distribution is the
physics; the draw is reproducible (batch-bit-identity preserved). Pure broadcast ops, NO loops.
"""
import torch


def lead_solution(rel_pos, target_vel, muzzle_v, eps=1e-9):
    """Constant-velocity intercept (SOURCES aa-fire §6). rel_pos [...,3] = target - shooter,
    target_vel [...,3], muzzle_v scalar/[...] projectile speed. Solves
        (v.v - s^2) t^2 + 2 (p.v) t + p.p = 0
    for the smallest positive root. Returns (t_hit [...], aim_point [...,3], feasible [...] bool).
    Safe: linear fallback when |a|<eps; masked sqrt on the discriminant."""
    p = rel_pos
    v = target_vel
    s2 = muzzle_v * muzzle_v
    a = (v * v).sum(-1) - s2                                        # [...]
    b = 2.0 * (p * v).sum(-1)
    c = (p * p).sum(-1)
    disc = b * b - 4.0 * a * c
    disc_ok = disc >= 0.0
    sq = torch.sqrt(torch.clamp(disc, min=0.0))
    # roots of a t^2 + b t + c = 0, guarding a->0 (nearly |v|=s) with the linear root -c/b
    lin = (a.abs() < eps)
    a_safe = torch.where(lin, torch.ones_like(a), a)
    t1 = (-b - sq) / (2.0 * a_safe)
    t2 = (-b + sq) / (2.0 * a_safe)
    b_safe = torch.where(b.abs() < eps, torch.ones_like(b), b)
    t_lin = -c / b_safe
    # smallest positive root among {t1, t2}; fall back to linear when a~0
    big = torch.full_like(t1, 1e18)
    t1p = torch.where(t1 > 0, t1, big)
    t2p = torch.where(t2 > 0, t2, big)
    t_quad = torch.minimum(t1p, t2p)
    t_hit = torch.where(lin, t_lin, t_quad)
    feasible = disc_ok & (t_hit > 0) & (t_hit < 1e17)
    t_c = torch.clamp(t_hit, min=0.0)
    aim_point = p + v * t_c[..., None]
    return t_hit, aim_point, feasible


def p_hit(dist, target_radius, sigma_ang, extra_var=0.0):
    """CEP hit probability (military-OR Rayleigh, SOURCES aa-fire §4): P = 1 - exp(-r^2/(2 sigma^2)),
    sigma^2 = (dist*sigma_ang)^2 + extra_var. `extra_var` carries the sourced maneuver/track inflation
    (env passes (0.5 a_perp t_f)^2 * penalty) so jinking lowers P. All args broadcast -> [...]. Safe."""
    sigma2 = (dist * sigma_ang) ** 2 + extra_var
    return 1.0 - torch.exp(-(target_radius * target_radius) / (2.0 * sigma2 + 1e-12))


def maneuver_extra_var(a_perp, t_flight, penalty):
    """The sourced sigma_maneuver^2 term (SOURCES aa-fire error budget): (0.5 a_perp t_f)^2 * penalty.
    a_perp [...] target lateral accel, t_flight [...] projectile time-of-flight -> [...]. This is what
    makes evasion physically reduce P(hit)."""
    return (0.5 * a_perp * t_flight) ** 2 * penalty


def resolve_fire(fire_gate, prob, roll):
    """Deterministic hit resolution. fire_gate [...] (1 = a shot is taken this tick), prob [...] the
    P(hit), roll [...] a PREGENERATED uniform(0,1) (schedule table). hit = fire_gate * (roll < prob).
    Returns float [...]. Determinism: the distribution is physical, the draw reproducible."""
    return fire_gate * (roll < prob).to(fire_gate.dtype)


# ---- exterior-ballistics closed forms (test oracles for the env's 3D drag projectile) --------------
def flat_fire_speed(u0, k, x):
    """Flat-fire downrange speed u(x) = u0 * exp(-k x) (SOURCES aa-fire §3 / McCoy). Test oracle."""
    return u0 * torch.exp(-k * x)


def flat_fire_time(u0, k, x):
    """Flat-fire time of flight t(x) = (exp(k x) - 1)/(k u0). Test oracle."""
    return (torch.exp(k * x) - 1.0) / (k * u0)
