"""STEP-0 — the droneswarm reachability/feasibility gate: is this a control problem at all, or
degenerate? Pure numpy, no torch, no env — runs BEFORE any env code exists (froggo's
gate_reachability.py idiom). It calibrates the WorldConfig (drone thrust envelope, AA dispersion)
the way froggo's gate calibrated launch speed.

Four questions, each an assertable metric (tests/test_gate.py checks all four):

  (a) HOVER MARGIN — can the drone hold position in the worst-case wind? A drone holding station in
      steady wind W tilts to cancel the (linear, mass-normalized) drag accel drag_lin*W; the thrust
      it must produce is g/cos(tilt) = sqrt(g^2 + (drag_lin*W)^2). Margin = a_thrust_max / that.
      Assert >= 1.5 at mean+3sigma wind (headroom to also maneuver, not just survive).

  (b) INTERCEPT FEASIBILITY — a bounded-thrust point-mass drone (sourced envelope: max thrust accel
      = T2W*g, so max horizontal accel holding altitude = g*sqrt(T2W^2-1)) pursuing an evading ground
      target (turns perpendicular to the line of sight at its max speed). Numerically integrate the
      pursuit (PD guidance, double-integrator) over sampled spawn geometries. Assert P(intercept
      within the episode) > 0.95 AND the intercept-time distribution is DISCRIMINATIVE (median not
      ~0 = trivially instant, not ~horizon = barely feasible) — a real skill gradient exists.

  (c) AA SURVIVABILITY — a drone crossing the engagement ring toward a shooter takes N = fire_rate *
      dwell shots; each hits with P = 1 - exp(-r^2 / (2 sigma^2)), sigma = range*sigma_ang inflated
      by the sourced maneuver term (jinking lowers P). Expected loss = 1 - prod(1-P_i). Assert the
      loss fraction at nominal approach is in (0.3, 0.9): AA is lethal enough to matter, survivable
      enough that hunting is not suicide. This is what calibrates aa_sigma_ang.

  (d) CONSTANT-ACTION DEGENERACY — the best CONSTANT thrust-vector (fixed direction+magnitude) must
      NOT systematically intercept an evading target, while a maneuvering pursuer does. If a constant
      action already clears the game, the env is degenerate (froggo's best-constant check). Assert
      maneuvering-intercept-rate - best-constant-intercept-rate > 0.5.

The pursuer/target models use the SOURCED acceleration envelope only (SOURCES quadrotor-ctbr §CTBR;
aa-fire §CEP/lead). Attitude is abstracted to the thrust-vector accel bound — faithful for a
feasibility question, exactly as froggo's gate used the symplectic-Euler closed form, not the env.

Usage:
    python gate_intercept.py                 # full report + calibration recommendation
    python gate_intercept.py --json runs/gate.json
"""
import argparse
import json

import numpy as np

from world_config_drone import WorldConfig


# ---------------------------------------------------------------------------------------------
# (a) hover margin in wind
# ---------------------------------------------------------------------------------------------
def hover_margin(cfg, wind_speed):
    """Thrust-margin holding station in steady wind `wind_speed` [m/s] (array or scalar).
    tilt: tan(theta) = drag_accel/g = drag_lin*W/g ; thrust accel needed = g/cos(theta) =
    sqrt(g^2 + (drag_lin*W)^2). Margin = a_thrust_max / needed. Vectorized."""
    W = np.asarray(wind_speed, np.float64)
    a_thrust_max = cfg.drone_t2w * cfg.gravity                   # T2W*g
    drag_accel = cfg.drag_quad * W * W                           # quadratic drag accel at airspeed W
    needed = np.sqrt(cfg.gravity ** 2 + drag_accel ** 2)         # thrust to cancel gravity + drag
    return a_thrust_max / needed


def worst_wind(cfg):
    """mean+3sigma wind speed = wind_mean_hi * (1 + 3*dryden_sigma_frac)."""
    return cfg.wind_mean_hi * (1.0 + 3.0 * cfg.dryden_sigma_frac)


# ---------------------------------------------------------------------------------------------
# (b),(d) pursuit integration (vectorized double-integrator over M sample geometries)
# ---------------------------------------------------------------------------------------------
def _run_pursuit(cfg, p0, v0, q0, u_dir0, maneuver, seed=0, horizon=None):
    """Vectorized pursuit of M evading ground targets. Point-mass drone with the sourced thrust-accel
    envelope; target moves at soldier/tank-class max speed, evading perpendicular to the line of sight.
    `maneuver=True` => PD lead guidance (a real pursuer); False => a fixed constant thrust vector (the
    degeneracy control). Returns (intercepted[M] bool, t_hit[M] seconds, min_dist[M])."""
    cfg_dt = cfg.dt
    M = p0.shape[0]
    horizon = horizon or cfg.decision_dt * 150               # episode length in seconds
    steps = int(round(horizon / cfg_dt))
    g = cfg.gravity
    a_thrust_max = cfg.drone_t2w * g                          # total thrust accel bound
    a_lat_max = g * np.sqrt(max(cfg.drone_t2w ** 2 - 1.0, 0.0))   # horizontal accel holding altitude
    v_e = cfg.tank_speed_max                                  # hardest ground target speed
    kill = cfg.drone_kill_radius
    ah = cfg.arena_half

    p = p0.astype(np.float64).copy()
    v = v0.astype(np.float64).copy()
    q = q0.astype(np.float64).copy()
    u_dir = u_dir0.astype(np.float64).copy()
    # constant-control branch: one fixed horizontal thrust-vector accel per sample (toward the INITIAL
    # target bearing, full magnitude) — the best a non-maneuvering policy can do.
    rel0 = q0 - p0
    rel0xy = rel0.copy(); rel0xy[:, 2] = 0.0
    const_a = a_lat_max * rel0xy / (np.linalg.norm(rel0xy, axis=1, keepdims=True) + 1e-9)

    intercepted = np.zeros(M, bool)
    t_hit = np.full(M, np.nan)
    min_dist = np.full(M, np.inf)

    for k in range(steps):                                   # GATE-OFFLINE-LOOP-OK (numpy analysis tool, not the sim)
        rel = q - p
        dist = np.linalg.norm(rel, axis=1)
        newly = (~intercepted) & (dist < kill)
        t_hit[newly] = k * cfg_dt
        intercepted |= newly
        min_dist = np.minimum(min_dist, dist)

        if maneuver:
            # PD LEAD guidance: aim at the target's predicted position (lead by time-to-go), clamp
            # horizontal accel. Lead is what lets a fast, limited-turn pursuer intercept a juking target
            # (SOURCES aa-fire §6 constant-velocity intercept, used here as guidance).
            t_go = dist / cfg.drone_speed_max
            q_lead = q + (v_e * u_dir) * t_go[:, None]       # predicted target position
            a_cmd = 3.0 * (q_lead - p) - 2.2 * v             # PD toward the lead point (double integrator)
            a_h = a_cmd.copy(); a_h[:, 2] = 0.0
            hn = np.linalg.norm(a_h, axis=1, keepdims=True)
            a_h = a_h * np.minimum(1.0, a_lat_max / (hn + 1e-9))
            a_z = np.clip(a_cmd[:, 2], -a_lat_max, a_thrust_max - g)   # vertical budget
            a = a_h.copy(); a[:, 2] = a_z
        else:
            a = const_a.copy()                               # fixed thrust vector (constant action)

        v = v + a * cfg_dt
        # sourced QUADRATIC drag terminal = sqrt(a_lat_max/drag_quad); apply the drag accel each step
        vsp = np.linalg.norm(v, axis=1, keepdims=True)
        v = v - cfg.drag_quad * vsp * v * cfg_dt             # quadratic body drag (mass-normalized)
        p_prev = p.copy()
        p = p + v * cfg_dt
        p[:, 2] = np.clip(p[:, 2], 0.5, cfg.ceiling)         # drone stays airborne
        np.clip(p[:, :2], -ah, ah, out=p[:, :2])
        # SWEPT kill test: closest approach of the drone's travel segment p_prev->p to the target,
        # so a fast drone cannot tunnel past the small kill radius between ticks.
        seg = p - p_prev
        seg2 = np.sum(seg * seg, axis=1) + 1e-12
        tt = np.clip(np.sum((q - p_prev) * seg, axis=1) / seg2, 0.0, 1.0)
        closest = p_prev + tt[:, None] * seg
        swept = np.linalg.norm(q - closest, axis=1)
        newly2 = (~intercepted) & (swept < kill)
        t_hit[newly2] = k * cfg_dt
        intercepted |= newly2

        # target evades: turn its heading away from the incoming drone (perpendicular to LOS), max speed
        losxy = (q - p); losxy[:, 2] = 0.0
        ln = np.linalg.norm(losxy, axis=1, keepdims=True) + 1e-9
        losxy = losxy / ln
        perp = np.stack([-losxy[:, 1], losxy[:, 0], np.zeros(M)], axis=1)
        # pick the perpendicular that increases distance (away component), blended with prior heading
        sign = np.sign(np.sum(perp * u_dir, axis=1, keepdims=True) + 1e-9)
        u_dir = 0.8 * (perp * sign) + 0.2 * losxy            # mostly cross, a little retreat
        u_dir = u_dir / (np.linalg.norm(u_dir, axis=1, keepdims=True) + 1e-9)
        q = q + v_e * u_dir * cfg_dt
        q[:, 2] = 0.0
        np.clip(q[:, :2], -ah, ah, out=q[:, :2])

    return intercepted, t_hit, min_dist


def sample_geometry(cfg, M, seed=0):
    """M pursuit setups: drone spawned at altitude on the arena rim, target on the ground inside."""
    rng = np.random.default_rng(seed)
    ah = cfg.arena_half
    ang = rng.uniform(0, 2 * np.pi, M)
    rad = rng.uniform(0.6 * ah, 0.95 * ah, M)
    p0 = np.stack([rad * np.cos(ang), rad * np.sin(ang),
                   rng.uniform(0.4 * cfg.ceiling, 0.9 * cfg.ceiling, M)], axis=1)
    v0 = np.zeros((M, 3))
    tr = rng.uniform(0.0, 0.5 * ah, M)
    ta = rng.uniform(0, 2 * np.pi, M)
    q0 = np.stack([tr * np.cos(ta), tr * np.sin(ta), np.zeros(M)], axis=1)
    ud = rng.uniform(-1, 1, (M, 3)); ud[:, 2] = 0.0
    ud = ud / (np.linalg.norm(ud, axis=1, keepdims=True) + 1e-9)
    return p0, v0, q0, ud


# ---------------------------------------------------------------------------------------------
# (c) AA survivability
# ---------------------------------------------------------------------------------------------
def aa_loss_fraction(cfg, approach_speed, jink_accel=0.0, n_shooters=1):
    """Expected fraction of drones lost on a straight radial approach from aa_range to kill_radius,
    against `n_shooters` shooters. Shots modelled as a POISSON process at rate lambda = 1/cooldown
    (standard air-defense OR): expected hits = (lambda/v) * integral_{kill}^{range} P_hit(r) dr, since
    substituting r = R - v*t gives dt = dr/v (the v-dependence is exactly the 1/v dwell factor). P_hit(r)
    = 1 - exp(-target_r^2/(2 sigma^2)), sigma^2 = (r*sigma_ang)^2 + maneuver term (0.5*jink*t_f)^2 (SOURCES
    aa-fire error budget). loss = 1 - exp(-expected_hits). Continuous form -> STRICTLY monotone in v
    (no floor() shot-count staircase). Fully vectorized over the range grid."""
    v = max(float(approach_speed), 1e-6)
    R0, R1 = cfg.drone_kill_radius, cfg.aa_range
    if R1 <= R0:
        return 0.0
    r = np.linspace(R0, R1, 256)
    t_f = r / cfg.aa_muzzle_soldier
    sigma2 = (r * cfg.aa_sigma_ang) ** 2 + (0.5 * jink_accel * t_f) ** 2 * cfg.aa_maneuver_penalty
    p_hit = 1.0 - np.exp(-(cfg.aa_target_radius ** 2) / (2.0 * sigma2 + 1e-12))
    lam = 1.0 / cfg.aa_cooldown                                    # shots/s (Poisson rate)
    integral = np.trapezoid(p_hit, r)                              # ∫ P_hit(r) dr  (v-independent)
    expected_hits = (lam / v) * integral * n_shooters
    return float(1.0 - np.exp(-expected_hits))


# ---------------------------------------------------------------------------------------------
# report
# ---------------------------------------------------------------------------------------------
def run_gate(cfg, M=4096, seed=0):
    Ww = worst_wind(cfg)
    m_hover = float(hover_margin(cfg, Ww))
    m_nom = float(hover_margin(cfg, cfg.wind_mean_hi * 0.5))

    p0, v0, q0, ud = sample_geometry(cfg, M, seed)
    hit_man, t_man, _ = _run_pursuit(cfg, p0, v0, q0, ud, maneuver=True, seed=seed)
    hit_con, _, _ = _run_pursuit(cfg, p0, v0, q0, ud, maneuver=False, seed=seed)
    p_inter = float(hit_man.mean())
    p_const = float(hit_con.mean())
    tt = t_man[np.isfinite(t_man)]
    horizon = cfg.decision_dt * 150
    t_p10, t_p50, t_p90 = (float(np.percentile(tt, q)) for q in (10, 50, 90)) if tt.size else (0, 0, 0)

    a_lat_max = cfg.gravity * np.sqrt(max(cfg.drone_t2w ** 2 - 1.0, 0.0))
    jink = a_lat_max                                                 # a jinking drone uses its full lateral accel
    dive_speed = 0.8 * cfg.drone_speed_max                          # a kamikaze drone dives at ITS speed, not the tank's
    loss_straight = aa_loss_fraction(cfg, dive_speed, jink_accel=0.0)
    loss_jink = aa_loss_fraction(cfg, dive_speed, jink_accel=jink)
    loss_nominal = 0.5 * (loss_straight + loss_jink)

    rep = {
        "hover_margin_worst_wind": m_hover, "hover_margin_nominal": m_nom, "worst_wind": Ww,
        "intercept_rate_maneuver": p_inter, "intercept_rate_constant": p_const,
        "intercept_advantage": p_inter - p_const,
        "intercept_time_p10": t_p10, "intercept_time_p50": t_p50, "intercept_time_p90": t_p90,
        "episode_horizon_s": horizon,
        "aa_loss_straight": loss_straight, "aa_loss_jink": loss_jink, "aa_loss_nominal": loss_nominal,
        "drone_a_lat_max": float(a_lat_max), "drone_vmax_est": float(np.sqrt(a_lat_max / cfg.drag_quad)),
    }
    return rep


def verdict(rep):
    checks = {
        "hover_margin>=1.5": rep["hover_margin_worst_wind"] >= 1.5,
        "intercept_rate>0.95": rep["intercept_rate_maneuver"] > 0.95,
        "intercept_time_discriminative": 0.05 * rep["episode_horizon_s"] < rep["intercept_time_p50"]
                                         < 0.85 * rep["episode_horizon_s"],
        "non_degenerate_advantage>0.5": rep["intercept_advantage"] > 0.5,
        "aa_loss_in(0.3,0.9)": 0.3 < rep["aa_loss_nominal"] < 0.9,
    }
    return checks, all(checks.values())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", default=None)
    ap.add_argument("--samples", type=int, default=4096)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()
    cfg = WorldConfig()
    rep = run_gate(cfg, args.samples, args.seed)
    checks, ok = verdict(rep)

    print("=" * 72)
    print("STEP-0 GATE — droneswarm feasibility / calibration")
    print("=" * 72)
    print(f"(a) hover margin @ worst wind {rep['worst_wind']:.1f} m/s : "
          f"{rep['hover_margin_worst_wind']:.2f}   (nominal {rep['hover_margin_nominal']:.2f})")
    print(f"(b) intercept rate (maneuvering)          : {rep['intercept_rate_maneuver']*100:.1f}%")
    print(f"    intercept time p10/p50/p90 (of {rep['episode_horizon_s']:.0f}s): "
          f"{rep['intercept_time_p10']:.1f}/{rep['intercept_time_p50']:.1f}/{rep['intercept_time_p90']:.1f} s")
    print(f"    drone a_lat_max {rep['drone_a_lat_max']:.1f} m/s^2, v_max~{rep['drone_vmax_est']:.1f} m/s")
    print(f"(c) AA loss fraction straight/jink/nominal : "
          f"{rep['aa_loss_straight']*100:.0f}% / {rep['aa_loss_jink']*100:.0f}% / {rep['aa_loss_nominal']*100:.0f}%")
    print(f"(d) DEGENERACY: maneuver {rep['intercept_rate_maneuver']*100:.0f}% vs "
          f"best-constant {rep['intercept_rate_constant']*100:.0f}%  (advantage {rep['intercept_advantage']*100:.0f}pts)")
    print("-" * 72)
    for name, passed in checks.items():
        print(f"  [{'PASS' if passed else 'FAIL'}] {name}")
    print(f"VERDICT: {'PASS — non-degenerate control problem' if ok else 'FAIL — retune WorldConfig'}")

    if args.json:
        import os
        os.makedirs(os.path.dirname(args.json) or ".", exist_ok=True)
        json.dump({"report": rep, "checks": checks, "ok": ok}, open(args.json, "w"), indent=2)
        print(f"wrote {args.json}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
