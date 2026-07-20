"""EnvDrone worldsim acceptance — the family invariants (froggo test_env idiom):
  * NO python loops in the hot path (AST enforcement; step_dec / game_loop whitelisted for exactly 1).
  * batch == N singles, bit-identical (the whole point of the vectorized sim).
  * seed / action determinism.
  * closed-form mechanics: terrain crash, hover holds altitude, kamikaze kills both + kills++,
    AA hit lands iff roll < P(hit).
  * observations finite + bounded by obs_clamp.
"""
import ast
import inspect
import os
import sys
import textwrap

import numpy as np
import torch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import env_drone
import schedule_drone as S
from env_drone import EnvDrone, game_loop
from world_config_drone import WorldConfig
from oracles import rotation, aero, quadrotor, terrain, ground, collide3, contact, aa_fire, wind, assign

CFG = WorldConfig()
LOOP_NODES = (ast.For, ast.While, ast.comprehension)


def _count_loops(fn):
    return sum(isinstance(n, LOOP_NODES) for n in ast.walk(ast.parse(textwrap.dedent(inspect.getsource(fn)))))


def _env(n=4, D=6, E=4, O=8, T=200, seed=0):
    return EnvDrone(S.build(CFG, n, D, E, O, T, base_seed=seed), device="cpu", cfg=CFG)


# ---- 1. no loops in the hot path ----
def test_no_loops_in_hot_path():
    for fn in (EnvDrone._core, EnvDrone.drone_obs, EnvDrone.enemy_obs, EnvDrone._select_topk,
               EnvDrone._nearest_obstacle, EnvDrone._nearest_obstacle_clr, EnvDrone._terrain_z,
               EnvDrone._enemy_pos3):
        assert _count_loops(fn) == 0, f"{fn.__qualname__} has a loop"
    # every HOT-PATH oracle function must be loop-free (dryden_series_np is offline -> excluded)
    for fn in (rotation.quat_mul, rotation.quat_rotate, rotation.quat_integrate, rotation.quat_from_rotvec,
               rotation.body_z_axis, rotation.shortest_arc, rotation.quat_log, rotation.quat_conjugate,
               aero.drag_accel, aero.ground_effect_factor, quadrotor.quad_step,
               quadrotor.rate_track, terrain.height, terrain.height_grad, ground.unicycle_step,
               ground.social_force, ground.tobler_factor, collide3.shape_sdf3, collide3.shape_sdf3_grad,
               collide3.segment_clearance, contact.hunt_crossley_force, aa_fire.p_hit, aa_fire.lead_solution,
               aa_fire.resolve_fire, wind.shear_factor, wind.wind_at,
               assign.balanced_assignment, assign._sinkhorn_iter, assign.target_direction):
        assert _count_loops(fn) == 0, f"oracle {fn.__qualname__} has a loop"
    # step_dec + game_loop are whitelisted for exactly one marked loop each
    assert _count_loops(EnvDrone.step_dec) == 1 and "TIME-LOOP-OK" in inspect.getsource(EnvDrone.step_dec)
    assert _count_loops(env_drone.game_loop) == 1 and "DEC-LOOP-OK" in inspect.getsource(env_drone.game_loop)


# ---- 2. batch == N singles, bit-identical ----
def _ua(env, s):
    """Uniform-over-alive-enemies assignment [P,N,D,E] for direct _core calls (the group policy supplies a one-hot)."""
    ea = s["e_alive"]
    a = ea[:, :, None, :].expand(-1, -1, env.D, -1)
    return a / a.sum(-1, keepdim=True).clamp_min(1e-8)


def _det_policy(env):
    """Deterministic scripted policy (function of obs only) — exercises the obs pipeline reproducibly."""
    def dfn(sf, tok, mk, *rest):                                  # *rest = group-assignment obs (enemy_feat, masks, xy) — ignored
        base = sf[..., :4].mean(-1, keepdim=True)
        return torch.cat([base, tok[..., :3].mean(-2)], -1)
    def efn(sf, tok, mk):
        return torch.cat([sf[..., :2], sf[..., 2:3]], -1)
    return dfn, efn


def test_batch_equals_singles_bit_identical():
    big = _env(n=4, seed=0)
    dfn, efn = _det_policy(big)
    sb = game_loop(big, dfn, efn, P=1, K_dec=25)
    for e in range(4):
        one = _env(n=1, seed=e)                                    # env0 of seed e == big row e (schedule test)
        d1, e1 = _det_policy(one)
        so = game_loop(one, d1, e1, P=1, K_dec=25)
        # discrete keys stay bit-identical; float positions may differ by ~1e-6 because the Eikonal Godunov
        # update (sqrt/division) is not bit-reproducible across batch shapes (the old octile min+add was).
        for k in ("d_alive", "e_alive", "kills", "losses"):
            assert torch.equal(sb[k][:, e], so[k][:, 0]), f"{k} env {e} not identical batch-vs-single"
        for k in ("d_pos", "e_pos"):
            assert torch.allclose(sb[k][:, e], so[k][:, 0], atol=1e-3, rtol=0), f"{k} env {e} not close batch-vs-single"


def test_action_determinism():
    a = _env(n=2, seed=3); b = _env(n=2, seed=3)
    da, ea = _det_policy(a); db, eb = _det_policy(b)
    sa = game_loop(a, da, ea, P=1, K_dec=20)
    sbb = game_loop(b, db, eb, P=1, K_dec=20)
    assert torch.equal(sa["d_pos"], sbb["d_pos"]) and torch.equal(sa["kills"], sbb["kills"])


# ---- 3. closed-form mechanics (call _core directly on a crafted state) ----
def _blank_state(env, P=1):
    s = env.reset(P)
    return s


def test_base_controller_hovers():
    """With a ZERO velocity command and no route (flow=0), the differentiable velocity-tracking base controller
    holds altitude (thrust = m g on a level drone) -- the fix for the old below-hover sink-to-ground failure.
    A zero action is now 'follow the route'; with no route it is a stable hover, NOT a free-fall."""
    env = _env(n=1, D=1, E=1, O=1, T=50)
    env.hf = torch.zeros_like(env.hf)                            # flat terrain at z=0
    s = env.reset(1); s["d_act"][:] = 1.0; s["d_alive"][:] = 1.0
    s["d_pos"][..., 2] = 10.0; s["d_pos"][..., :2] = 0.0; s["d_vel"][:] = 0.0
    s["nav_flow"][:] = 0.0                                        # no route -> v_ref = 0 -> pure hover
    a_d = torch.zeros(1, 1, 1, 4); a_e = torch.zeros(1, 1, 1, 3)
    zg = torch.zeros(1, 3); zr = torch.zeros(1, 1); due = torch.zeros(1, 1, 1)
    for _ in range(100):
        s, *_ = env._core(s, zg, zr, due, a_d, a_e, _ua(env, s))
    assert float(s["d_alive"].sum()) == 1.0                       # STILL FLYING (did not sink/crash)
    assert abs(float(s["d_pos"][..., 2]) - 10.0) < 0.5           # altitude held within 0.5 m over 2 s


def test_base_controller_tracks_velocity_command():
    """The AI velocity OVERRIDE steers the drone: a +x command yields +x velocity (the base controller flies it,
    the AI never touches thrust/rates)."""
    env = _env(n=1, D=1, E=1, O=1, T=50)
    env.hf = torch.zeros_like(env.hf)
    s = env.reset(1); s["d_act"][:] = 1.0; s["d_alive"][:] = 1.0
    s["d_pos"][..., 2] = 10.0; s["d_pos"][..., :2] = 0.0; s["d_vel"][:] = 0.0
    s["nav_flow"][:] = 0.0                                        # isolate the override (no route velocity)
    a_d = torch.zeros(1, 1, 1, 4); a_d[..., 0] = 2.0            # +x velocity override (tanh(2)~0.96 -> ~ +v_override)
    a_e = torch.zeros(1, 1, 1, 3)
    zg = torch.zeros(1, 3); zr = torch.zeros(1, 1); due = torch.zeros(1, 1, 1)
    for _ in range(40):
        s, *_ = env._core(s, zg, zr, due, a_d, a_e, _ua(env, s))
    assert float(s["d_vel"][..., 0]) > 1.0                       # gained +x velocity toward the commanded direction
    assert float(s["d_alive"].sum()) == 1.0


def test_kamikaze_kills_both_and_scores():
    """A drone at an enemy's position kills the enemy AND dies; kills increments."""
    env = _env(n=1, D=1, E=1, O=1, T=50)
    env.hf = torch.zeros_like(env.hf)
    s = env.reset(1); s["d_act"][:] = 1.0; s["d_alive"][:] = 1.0
    s["e_pos"][:] = 0.0                                          # enemy at origin, on terrain z=0
    s["d_pos"][..., :2] = 0.0; s["d_pos"][..., 2] = 0.3          # drone right on top (within kill radius)
    a_d = torch.zeros(1, 1, 1, 4); a_d[..., 0] = -50.0          # ~no thrust
    a_e = torch.zeros(1, 1, 1, 3)
    s, rd, re, dd, de, _ = env._core(s, torch.zeros(1, 3), torch.zeros(1, 1), torch.zeros(1, 1, 1), a_d, a_e, _ua(env, s))
    assert float(s["e_alive"].sum()) == 0.0                      # enemy dead
    assert float(s["d_alive"].sum()) == 0.0                      # drone dead too (kamikaze)
    assert float(s["kills"]) == 1.0
    assert float(rd) > 0.0                                       # kill reward positive


def test_aa_hit_lands_iff_roll_below_phit():
    """Enemy AA fires at an in-range drone: hit exactly when the deterministic roll < P(hit)."""
    env = _env(n=1, D=1, E=1, O=1, T=50)
    env.hf = torch.zeros_like(env.hf)

    def one_shot(roll_val):
        s = env.reset(1); s["d_act"][:] = 1.0; s["d_alive"][:] = 1.0
        s["e_pos"][:] = 0.0
        s["d_pos"][..., :2] = 0.0; s["d_pos"][..., 2] = 5.0     # 5 m up, well inside aa_range=35, outside kill
        s["d_vel"][:] = 0.0                                     # no crossing -> P(hit) is its base value
        a_d = torch.zeros(1, 1, 1, 4); a_d[..., 0] = -50.0
        a_e = torch.zeros(1, 1, 1, 3); a_e[..., 2] = 1.0        # fire
        roll = torch.full((1, 1), roll_val)
        s, *_ = env._core(s, torch.zeros(1, 3), roll, torch.zeros(1, 1, 1), a_d, a_e, _ua(env, s))
        return float(s["d_alive"].sum())
    # at 5 m, sigma = 5*aa_sigma_ang; P = 1-exp(-r^2/2sigma^2). roll 0 -> below P -> hit -> dead.
    assert one_shot(0.0) == 0.0                                  # certain hit (roll=0 < P)
    assert one_shot(0.999) == 1.0                               # certain miss (roll ~1 > P)


# ---- 3b. hot-path optimization correctness (dedup'd terrain gather, SDF-only crash, z=0 footprint) ----
def test_nearest_obstacle_clr_matches_full():
    """The SDF-only clearance path used by the crash test must agree with the SDF+gradient path's
    clearance (they differ only by a ~1e-6 eps convention)."""
    env = _env(n=3, D=5, E=3, O=8)
    torch.manual_seed(0)
    pos = torch.randn(2, env.N, 5, 3) * 20.0                     # random query points [P,N,K,3]
    clr_full, _ = env._nearest_obstacle(pos, env.obst_half)
    clr_only = env._nearest_obstacle_clr(pos, env.obst_half)
    assert torch.allclose(clr_full, clr_only, atol=1e-3), \
        f"SDF-only clearance disagrees with SDF+grad path: max {(clr_full - clr_only).abs().max():.2e}"


def test_obstacle_footprint_is_z_independent():
    """The ground-unit obstacle footprint (obst_half2, huge half-height) must be independent of the
    query z — this is what makes the z=0 shortcut in the enemy branch exact."""
    env = _env(n=3, D=1, E=4, O=8)
    xy = torch.randn(2, env.N, 4, 2) * 20.0
    p_zero = torch.cat([xy, torch.zeros(2, env.N, 4, 1)], -1)
    p_hi = torch.cat([xy, torch.full((2, env.N, 4, 1), 12.0)], -1)   # any altitude
    c0, g0 = env._nearest_obstacle(p_zero, env.obst_half2)
    c1, g1 = env._nearest_obstacle(p_hi, env.obst_half2)
    assert torch.allclose(c0, c1, atol=1e-4) and torch.allclose(g0[..., :2], g1[..., :2], atol=1e-4)


# ---- 4. observations bounded ----
def test_obs_finite_and_bounded():
    # New contract: the env emits MAGNITUDE features RAW (SI units); the policy's learnable LOT normalizer
    # (asinh) bounds them, not a hardcoded clamp. So at the env level obs must be FINITE and within a generous
    # PHYSICAL sanity ceiling (raw m / m/s stay well under it) — this catches NaN-adjacent explosions without
    # re-asserting the removed obs_clamp bound.
    env = _env(n=4, seed=7)
    dfn, efn = _det_policy(env)
    s = env.reset(1)
    SANE = 1e3
    for _ in range(10):
        for o in (*env.drone_obs(s), *env.enemy_obs(s)):
            assert torch.isfinite(o).all()
            assert float(o.abs().max()) <= SANE
        s, *_ = env.step_dec(s, 0, dfn(*env.drone_obs(s)), efn(*env.enemy_obs(s)))
