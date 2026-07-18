"""EnvDrone — the droneswarm WORLDSIM. Source of truth for all simulation; COMPOSES the oracles and
adds NO physics of its own. State is a plain dict of [P,N,...] tensors (P=rollout copies, N=envs,
D=drones, E=enemies); observations are pure functions routed through the SensorChannel (sensors.py);
only `_core` (one 50 Hz tick) is torch.compile'd (by the trainer, AFTER reward weights are set).

HARD RULE: no python loops in `_core` / the obs functions / any oracle. The only loops are the
per-tick loop in `step_dec` (marked TIME-LOOP-OK) and the decision loop in `game_loop` (DEC-LOOP-OK),
exactly the froggo carve-out. All conditionals are gated `torch.where`, no data-dependent branches,
so `_core` traces once.

Kamikaze combat: a drone that reaches an enemy kills it AND dies (contact-kill). Drones also die to
terrain/obstacle crashes and to enemy anti-air fire (CEP hitscan). One shared brain drives all drones
(CTBR), one shared coevolving brain drives all enemies (tank unicycle / soldier social-force + AA).
"""
import numpy as np
import torch

import sensors
from oracles import rotation as ROT
from oracles import aero as AERO
from oracles import quadrotor as QUAD
from oracles import wind as WIND
from oracles import terrain as TERR
from oracles import ground as GND
from oracles import collide3 as COL
from oracles import contact as CON
from oracles import aa_fire as AA
from oracles import assign as ASSIGN


def game_loop(env, drone_fn, enemy_fn, P, K_dec, on_step=None, record=None, record_stride=2,
              drone_recur=False, latent_h=0, early_break=True):
    """THE canonical outer decision loop (every driver uses this): reset, then K_dec times read the
    perceived obs, pick actions, advance one decision (act_every physics ticks). drone_fn/enemy_fn map
    obs bundles -> actions. on_step(k,s,...,done_e,h_in) fires after each decision with the PRE-decision
    state s (step_dec never mutates s). Returns the final state.

    drone_recur: the drone policy is RECURRENT — game_loop threads a per-drone latent h across decisions,
    resetting inactive / just-spawned drones to zero (h_in = h * active). drone_fn is then called as
    drone_fn(*d_obs, h_in) -> (action, h_new), and h_in is passed to on_step (for the PPO buffer). The
    final h is exposed as env._last_h for the tail-bootstrap value."""
    s = env.reset(P)
    h = torch.zeros(P, env.N, env.D, latent_h, device=env.device) if drone_recur else None
    for k in range(K_dec):                                        # DEC-LOOP-OK (decision loop, sequential)
        d_obs = env.drone_obs(s)
        e_obs = env.enemy_obs(s)
        if drone_recur:
            active = ((s["d_act"] > 0.5) & (s["d_alive"] > 0.5)).float()[..., None]   # reset inactive/spawned
            h_in = h * active
            a_d, h = drone_fn(*d_obs, h_in)
        else:
            h_in = None
            a_d = drone_fn(*d_obs)
        a_e = enemy_fn(*e_obs)
        ns, r_d, r_e, done_d, done_e = env.step_dec(s, k, a_d, a_e, record=record, record_stride=record_stride)
        if on_step is not None:
            on_step(k, s, d_obs, e_obs, a_d, a_e, ns, r_d, r_e, done_d, done_e, h_in)
        s = ns
        # Early-exit ONLY for eval/render (early_break=True). The `bool(...)` forces a GPU->CPU sync +
        # pipeline drain every decision; in a wide TRAINING batch no env clears simultaneously, so the
        # sync buys nothing and just serialises the GPU against Python (~10-30% rollout). GAE done-masks
        # + `valid`, so letting finished envs step on is cheap and correct.
        if early_break:
            enemies_left = (s["e_alive"] > 0.5).any()
            swarm_active = ((s["d_alive"] > 0.5) | (s["d_act"] < 0.5)).any()    # alive OR not-yet-launched
            if not bool(enemies_left & swarm_active):
                break                                            # all enemies dead, or swarm fully spent
    env._last_h = h                                              # final latent (for the recurrent tail bootstrap)
    return s


class EnvDrone:
    # ---- obs / action dims (the policy is parameterized by these) ----
    DRONE_SELF_F = 20     # + assigned-target dir(3) + focus(1) from the Sinkhorn dispersion oracle
    DRONE_TOK_F = 10      # rel_dir(3) dist(1) rvel(3) closing(1) is_enemy(1) enemy_tank(1)
    DRONE_K = 12          # attended tokens per drone (nearest drones + enemies)
    DRONE_ACT = 4         # CTBR: (thrust, wx, wy, wz) pre-squash
    ENEMY_SELF_F = 11
    ENEMY_TOK_F = 9
    ENEMY_K = 6           # attended drones per enemy
    ENEMY_ACT = 3         # (u0, u1, fire) pre-squash

    def __init__(self, sched, device="cpu", cfg=None):
        from world_config_drone import WorldConfig
        self.device = device
        self.cfg = cfg or WorldConfig()
        c = self.cfg
        self.N = int(sched["hf"].shape[0])
        self.D = int(sched["D"]); self.E = int(sched["E"]); self.O = int(sched["O"]); self.T = int(sched["T"])
        t = lambda a: torch.tensor(np.asarray(a, np.float32), device=device)
        self.hf = t(sched["hf"])                                  # [N,G,G]
        ob = t(sched["obst"])                                     # [N,O,7] x,y,zc,hx,hy,hz,is_cyl
        self.obst_xyz = ob[..., 0:3].contiguous()
        self.obst_half = ob[..., 3:6].contiguous()
        self.obst_cyl = ob[..., 6].contiguous()
        self.obst_mask = (self.obst_half.abs().sum(-1) > 1e-6).float()   # [N,O] valid obstacle
        self.e_type = t(sched["e_type"])                         # [N,E] 1=tank 0=soldier
        self.e_pos0 = t(sched["e_pos0"]); self.e_head0 = t(sched["e_head0"])
        self.base_pos = t(sched["base_pos"]); self.spawn_off = t(sched["spawn_off"])
        self.spawn_tick = t(sched["spawn_tick"])                  # [N,D]
        self.mean_wind = t(sched["mean_wind"]); self.gust = t(sched["gust"]); self.aa_roll = t(sched["aa_roll"])
        self.scale = t(sched["scale"])                            # [N] engage_range
        self.extent = c.arena_half
        self.cd_ticks = max(1, round(c.aa_cooldown / c.dt))
        # obstacle footprint (2D cross-section) for GROUND units: reuse the 3D SDF with a huge half_z
        # so the vertical term never binds -> the horizontal cross-section (obstacle-shape-primitives rule).
        self.obst_half2 = self.obst_half.clone(); self.obst_half2[..., 2] = 1e4
        self._spawn_pos = (self.base_pos[:, None, :] + self.spawn_off).contiguous()   # [N,D,3] static launch point
        self._eye_d = torch.eye(self.D, device=device)[None, None]        # [1,1,D,D] self-pair masks (static)
        self._eye_e = torch.eye(self.E, device=device)[None, None]        # [1,1,E,E]
        self._drone_self_mask = torch.cat(                                # [D, D+E] excludes drone i as its own token
            [torch.eye(self.D, device=device), torch.zeros(self.D, self.E, device=device)], 1)
        # reward weights (training only, parity-safe; set BEFORE compile). Defaults = the plan §3 draft.
        # rewards: kills DOMINATE; the closing term is POTENTIAL-BASED (bounded, un-farmable) so it can
        # never dwarf the sparse kill signal (the monstro/froggo 'shaping stays a minority' rule).
        self.rw_kill = 3.0; self.rw_clear = 8.0; self.rw_waste = 0.3; self.rw_close = 1.0; self.rw_smooth = 0.0005
        # COMMITMENT: a steep near-contact term folded into the same potential (un-farmable), sharpens the
        # terminal dive gradient.
        self.rw_commit = 2.5; self.commit_radius = 6.0 * c.drone_kill_radius
        # FLIGHT-COMPETENCE substrate: DISABLED (rw=0) — as always-on per-tick penalties they accumulate
        # over ~300 ticks and BURY the sparse kill signal (measured: alt-hold was 95.8% of the reward and
        # fought the strike-descent). The horizontal SEEK already prevents the ground-dive, so alt-hold is
        # redundant; obstacle-avoidance is covered by the sparse crash penalty. Re-add later ONLY as bounded
        # potentials (telescoping), never as raw per-tick penalties. cruise_alt/evade_range kept for that.
        self.rw_alt = 0.0; self.cruise_alt = 0.4 * c.ceiling
        # SMOOTH ground-clearance / terminal-braking penalty: penalise fast DESCENT near the deck UNLESS
        # diving onto a target. Unlike the hard crash event (0-grad), this is a clamp of agl+vz -> it gives
        # the analytic (SHAC) gradient a real "pull up / brake before impact" signal to avoid the earth.
        self.rw_brake = 1.0; self.clearance_range = 4.0
        self.rw_evade = 0.0; self.evade_range = 8.0
        # SEEK range: in v1 detection is PERFECT (all enemies visible), so seek must cover the whole arena
        # INCLUDING the far corners (arena diagonal = 2*sqrt(2)*arena_half ~= 2.83*arena_half) — else a drone
        # in a corner gets NO homing gradient and drifts/flies away. 3x covers the diagonal with margin.
        # Range-gated detection returns later via the SensorChannel.
        # COMBAT ZONE: the central square the fight lives in. Spawns, the homing gradient, and the enemy
        # edge-penalty all key off this (not arena_half), so a 3x arena can hold a 1x-scale engagement in its
        # middle. Homing/edge MUST use combat_half — if they used arena_half=3x, detection_range balloons and
        # the seek gradient goes flat over the combat zone (the swarm barely learns). 0 => == arena_half.
        self.combat_half = c.combat_half if c.combat_half > 0 else c.arena_half
        self.detection_range = 3.0 * self.combat_half
        self.rw_e_alive = 0.01; self.rw_e_death = 1.0; self.rw_e_aa = 0.5; self.rw_e_clump = 0.02
        # edge/corner-camp penalty: the naive evader flees the diving swarm straight to the arena wall
        # and pins against the clamp (measured: 78% of kills happen at the boundary), which shoves the
        # whole fight to the map edge and makes a degenerate evader. Penalise alive enemies for sitting
        # past edge_soft of the way out, so they learn to JUKE in the open field instead of wall-hugging.
        self.rw_e_edge = 0.05; self.edge_soft = 0.6 * self.combat_half   # pressure enemies to stay in the middle square
        self.aa_scale = 1.0            # AA-lethality curriculum knob (0-d tensor read in _core -> no recompile)
        self._aa_scale_t = torch.tensor(1.0, device=device)
        # kamikaze lethal-radius CURRICULUM knob (0-d tensor -> changed at runtime WITHOUT recompiling
        # _core, monstro _brange_t idiom). Start large to bootstrap contacts, anneal to the real radius.
        self._kill_r_t = torch.tensor(float(c.drone_kill_radius), device=device)
        # GENTLE EJECT of enemy anti-air fire (like the sensor-channel seam): when False the enemies only
        # MANEUVER — the whole AA block still runs but its effect is gated to zero, so re-injecting later
        # is a single flag (set BEFORE torch.compile: it bakes in as a compile-time constant, no recompile).
        self.aa_enabled = True
        self.decompose = False; self._panel = None

    def set_aa_scale(self, x):
        """Curriculum knob: scale AA lethality without recompiling _core (monstro _brange_t idiom)."""
        self.aa_scale = float(x); self._aa_scale_t = torch.tensor(float(x), device=self.device)

    def set_kill_radius(self, r):
        """Curriculum knob: kamikaze lethal radius (metres) without recompiling _core."""
        self._kill_r_t = torch.tensor(float(r), device=self.device)

    # ---- state ----
    def reset(self, P):
        c = self.cfg; N, D, E, dev = self.N, self.D, self.E, self.device
        z = lambda *s: torch.zeros(*s, device=dev)
        quat = torch.zeros(P, N, D, 4, device=dev); quat[..., 0] = 1.0    # identity attitude
        return dict(
            d_pos=self.base_pos[None, :, None, :].expand(P, N, D, 3).clone(),
            d_vel=z(P, N, D, 3), d_quat=quat, d_omega=z(P, N, D, 3),
            d_act=z(P, N, D), d_alive=z(P, N, D),
            d_energy=torch.full((P, N, D), c.batt_capacity_j, device=dev),
            d_prox=z(P, N, D),                                   # last-tick per-drone proximity (potential-based shaping)
            d_crash=z(P, N, D),                                  # sticky: 1 once a drone died by terrain/obstacle crash (render)
            e_pos=self.e_pos0[None].expand(P, N, E, 2).clone(),
            e_head=self.e_head0[None].expand(P, N, E).clone(),
            e_vel=z(P, N, E, 2), e_alive=torch.ones(P, N, E, device=dev),
            e_cd=z(P, N, E), kills=z(P, N), losses=z(P, N),
        )

    # ---- geometry helpers ----
    def _terrain_z(self, xy):
        """Terrain height at xy [P,N,K,2] -> [P,N,K]."""
        return TERR.height(self.hf, xy, self.extent)

    def _enemy_pos3(self, e_pos):
        """Enemy 3D position = (x, y, terrain_z). e_pos [P,N,E,2] -> [P,N,E,3]."""
        z = self._terrain_z(e_pos)
        return torch.cat([e_pos, z[..., None]], -1)

    def _nearest_obstacle(self, pos3, half):
        """Nearest-obstacle signed clearance + outward gradient for query points pos3 [P,N,K,3] against
        obstacle bundle with the given `half` [N,O,3]. Returns (clr [P,N,K], grad [P,N,K,3]). Loop-free."""
        P, N, K, _ = pos3.shape
        dvec = pos3[:, :, :, None, :] - self.obst_xyz[None, :, None, :, :]     # [P,N,K,O,3]
        half_e = half[None, :, None, :, :].expand(P, N, K, self.O, 3)
        cyl_e = self.obst_cyl[None, :, None, :].expand(P, N, K, self.O)
        # TWO-PHASE: SDF over all O to pick the nearest, then the analytic grad on ONLY that one shape.
        # Per-shape grad is independent -> bit-identical to grad-over-all-O + gather, but O grad-evals -> 1
        # (the discarded 23/24 of the grad branch is never computed).
        sdf = COL.shape_sdf3(dvec, half_e, cyl_e)                             # [P,N,K,O] SDF only
        big = sdf + (1.0 - self.obst_mask[None, :, None, :]) * 1e9            # mask padded
        idx = big.argmin(-1, keepdim=True)                                   # [P,N,K,1]
        clr = torch.gather(big, -1, idx).squeeze(-1)
        idx3 = idx[..., None].expand(P, N, K, 1, 3)
        dv1 = torch.gather(dvec, 3, idx3)                                     # [P,N,K,1,3] nearest shape only
        hf1 = torch.gather(half_e, 3, idx3)
        cy1 = torch.gather(cyl_e, 3, idx)                                     # [P,N,K,1]
        _, g1 = COL.shape_sdf3_grad(dv1, hf1, cy1)                            # grad on the ONE nearest shape
        return clr, g1.squeeze(-2)

    def _nearest_obstacle_clr(self, pos3, half):
        """Nearest-obstacle clearance ONLY (no gradient) — cheaper than _nearest_obstacle for the crash
        test, which never uses the gradient. Uses shape_sdf3 (SDF, not SDF+grad). Loop-free."""
        P, N, K, _ = pos3.shape
        dvec = pos3[:, :, :, None, :] - self.obst_xyz[None, :, None, :, :]     # [P,N,K,O,3]
        half_e = half[None, :, None, :, :].expand(P, N, K, self.O, 3)
        cyl_e = self.obst_cyl[None, :, None, :].expand(P, N, K, self.O)
        sdf = COL.shape_sdf3(dvec, half_e, cyl_e)                             # [P,N,K,O]
        return (sdf + (1.0 - self.obst_mask[None, :, None, :]) * 1e9).amin(-1)

    # ---- observations (pure functions of the PERCEIVED picture; bounded + scale-normalized + clamped) ----
    def _select_topk(self, feat_qs, dist_qs, valid_qs, K):
        """Top-K nearest sources per query from precomputed relative features. feat_qs [P,N,Q,S,F],
        dist_qs/valid_qs [P,N,Q,S] -> (tok [P,N,Q,K,F], mask [P,N,Q,K]). Loop-free (topk + gather)."""
        S = dist_qs.shape[-1]; K = min(K, S)
        d = torch.where(valid_qs > 0.5, dist_qs, torch.full_like(dist_qs, 1e18))
        kd, ki = torch.topk(d, K, largest=False, dim=-1)
        mask = (kd < 1e17).to(feat_qs.dtype)
        idx = ki[..., None].expand(*ki.shape, feat_qs.shape[-1])
        return torch.gather(feat_qs, -2, idx), mask

    def drone_obs(self, state):
        """-> (self_feat [P,N,D,20], tok [P,N,D,K,10], mask [P,N,D,K]). Reads the SensorChannel picture;
        self_feat ends with the Sinkhorn assigned-target direction(3)+focus(1) for swarm dispersion."""
        c = self.cfg; pic = sensors.perceive(state)
        dp, dv, dq, dw = pic["d_pos"], pic["d_vel"], pic["d_quat"], pic["d_omega"]
        de, da = pic["d_energy"], pic["d_alive"]
        ep, ev, e_alive = pic["e_pos"], pic["e_vel"], pic["e_alive"]
        P, N, D, _ = dp.shape; E = self.E; sc = self.scale.view(1, N, 1)
        vmax = c.drone_speed_max
        # --- self features ---
        bz = ROT.body_z_axis(dq)                                              # [P,N,D,3] tilt
        th, tgrad = TERR.height_and_grad(self.hf, dp[..., :2], self.extent)   # fused: one corner-gather pass
        agl = dp[..., 2] - th                                                 # [P,N,D]
        oclr, ograd = self._nearest_obstacle(dp, self.obst_half)             # [P,N,D],[P,N,D,3]
        self_feat = torch.cat([
            bz,
            (dv / vmax).clamp(-c.obs_clamp, c.obs_clamp),
            (dw / c.drone_omega_max).clamp(-c.obs_clamp, c.obs_clamp),
            (agl / c.engage_range).clamp(0.0, c.obs_clamp)[..., None],
            (de / c.batt_capacity_j)[..., None],
            (tgrad).clamp(-c.obs_clamp, c.obs_clamp),
            (oclr / c.engage_range).clamp(-c.obs_clamp, c.obs_clamp)[..., None],
            ograd[..., :2],
        ], -1)                                                               # 3+3+3+1+1+2+1+2 = 16
        # --- tokens: other drones + enemies (merged, type-tagged) ---
        ep3 = self._enemy_pos3(ep)                                           # [P,N,E,3]
        ev3 = torch.cat([ev, torch.zeros_like(ev[..., :1])], -1)             # enemy vel (ground plane)
        # candidate positions/vels/alive/type over S = D + E
        cand_pos = torch.cat([dp, ep3], dim=2)                              # [P,N,D+E,3]
        cand_vel = torch.cat([dv, ev3], dim=2)
        cand_alive = torch.cat([da, e_alive], dim=2)                        # [P,N,D+E]
        is_enemy = torch.cat([torch.zeros(P, N, D, device=dp.device),
                              torch.ones(P, N, E, device=dp.device)], dim=2)
        enemy_tank = torch.cat([torch.zeros(P, N, D, device=dp.device),
                                self.e_type[None].expand(P, N, E)], dim=2)
        S = D + E
        rel = cand_pos[:, :, None, :, :] - dp[:, :, :, None, :]             # [P,N,D,S,3] query=drone i
        dist = torch.sqrt((rel * rel).sum(-1) + c.eps)                      # [P,N,D,S]
        rel_dir = rel / dist[..., None]
        rvel = (cand_vel[:, :, None, :, :] - dv[:, :, :, None, :]) / vmax   # [P,N,D,S,3]
        closing = -(rvel * rel_dir).sum(-1)                                 # >0 = approaching me
        ise = is_enemy[:, :, None, :].expand(P, N, D, S)
        etank = enemy_tank[:, :, None, :].expand(P, N, D, S)              # (isd dropped: it's just 1-ise)
        feat = torch.cat([rel_dir, (dist / sc[..., None]).clamp(max=c.obs_clamp)[..., None],
                          rvel.clamp(-c.obs_clamp, c.obs_clamp), closing[..., None],
                          ise[..., None], etank[..., None]], -1)          # 3+1+3+1+1+1 = 10 = DRONE_TOK_F
        valid = cand_alive[:, :, None, :].expand(P, N, D, S)               # exclude self via the static mask
        valid = valid * (1.0 - self._drone_self_mask[None, None])
        tok, mask = self._select_topk(feat, dist, valid, self.DRONE_K)
        # SWARM DISPERSION: balanced Sinkhorn assignment over enemies (reuses the drone->enemy sub-block
        # of the already-computed dist/rel_dir — no extra distance math). Gives each drone its assigned
        # target DIRECTION + focus, appended to self_feat. Recomputed here every decision = on-the-fly
        # re-assignment. (dist/rel_dir columns D: are the enemy candidates.)
        d2e = (dist[..., D:] / sc[..., None]).clamp(max=c.obs_clamp)      # [P,N,D,E] normalized dist
        T = ASSIGN.balanced_assignment(d2e, da, e_alive)                 # [P,N,D,E] soft assignment
        tgt_dir, focus = ASSIGN.target_direction(T, rel_dir[..., D:, :]) # [P,N,D,3], [P,N,D]
        self_feat = torch.cat([self_feat, tgt_dir, focus[..., None]], -1)   # 16 -> 20 = DRONE_SELF_F
        return self_feat, tok, mask

    def enemy_obs(self, state):
        """-> (self_feat [P,N,E,11], tok [P,N,E,K,9], mask [P,N,E,K])."""
        c = self.cfg; pic = sensors.perceive(state)
        ep, ev, eh, e_cd, e_alive = pic["e_pos"], pic["e_vel"], pic["e_head"], pic["e_cd"], pic["e_alive"]
        dp, dv, da = pic["d_pos"], pic["d_vel"], pic["d_alive"]
        P, N, E, _ = ep.shape; D = self.D; sc = self.scale.view(1, N, 1)
        ez, slope = TERR.height_and_grad(self.hf, ep, self.extent)           # fused: one corner-gather pass
        ep3 = torch.cat([ep, ez[..., None]], -1)                             # [P,N,E,3]
        speed = torch.sqrt((ev * ev).sum(-1) + c.eps)                        # [P,N,E]
        oclr, ograd = self._nearest_obstacle(ep3, self.obst_half2)          # 2D footprint clearance
        arena_pos = ep / c.arena_half
        self_feat = torch.cat([
            self.e_type[None, :, :, None].expand(P, N, E, 1),
            torch.stack([torch.cos(eh), torch.sin(eh)], -1),
            (speed / c.tank_speed_max).clamp(0, c.obs_clamp)[..., None],
            slope.clamp(-c.obs_clamp, c.obs_clamp),
            (e_cd / self.cd_ticks)[..., None],
            ograd[..., :2],
            arena_pos.clamp(-c.obs_clamp, c.obs_clamp),
        ], -1)                                                               # 1+2+1+2+1+2+2 = 11 = ENEMY_SELF_F
        # tokens: nearest alive drones
        rel = dp[:, :, None, :, :] - ep3[:, :, :, None, :]                   # [P,N,E,D,3] query=enemy
        dist = torch.sqrt((rel * rel).sum(-1) + c.eps)
        rel_dir = rel / dist[..., None]
        rvel = (dv[:, :, None, :, :] / c.drone_speed_max).expand(P, N, E, D, 3)   # drone world vel per enemy query
        closing = -(rvel * rel_dir).sum(-1)
        agl = (dp[..., 2] - self._terrain_z(dp[..., :2]))[:, :, None, :].expand(P, N, E, D)
        feat = torch.cat([rel_dir, (dist / sc[..., None]).clamp(max=c.obs_clamp)[..., None],
                          rvel.clamp(-c.obs_clamp, c.obs_clamp), closing[..., None],
                          (agl / c.engage_range).clamp(0, c.obs_clamp)[..., None]], -1)   # 3+1+3+1+1 = 9
        valid = da[:, :, None, :].expand(P, N, E, D)
        tok, mask = self._select_topk(feat, dist, valid, self.ENEMY_K)
        return self_feat, tok, mask

    # ---- one physics tick (COMPILED hot path; gated writes, no python branches, no loops) ----
    def _core(self, s, gust_t, aa_roll_t, due, a_drone, a_enemy):
        c = self.cfg; cfg = c
        P, N, D, E = s["d_pos"].shape[0], self.N, self.D, self.E
        dev = s["d_pos"].device
        # ===== 1. spawn drones =====
        just = (due > 0.5) & (s["d_act"] < 0.5)                              # [P,N,D] launching this tick
        spawn_pos = self._spawn_pos[None].expand(P, N, D, 3)                  # static launch point
        d_pos = torch.where(just[..., None], spawn_pos, s["d_pos"])
        ident = torch.zeros(P, N, D, 4, device=dev); ident[..., 0] = 1.0
        d_quat = torch.where(just[..., None], ident, s["d_quat"])
        d_vel = torch.where(just[..., None], torch.zeros_like(s["d_vel"]), s["d_vel"])
        d_omega = torch.where(just[..., None], torch.zeros_like(s["d_omega"]), s["d_omega"])
        d_energy = torch.where(just, torch.full_like(s["d_energy"], c.batt_capacity_j), s["d_energy"])
        d_act = torch.maximum(s["d_act"], just.float())
        d_alive = torch.maximum(s["d_alive"], just.float())
        active_d = (d_act > 0.5) & (d_alive > 0.5)                           # [P,N,D]
        af = active_d.float()                                                # cached (reused ~4x below)

        # ===== 2. wind at drones =====
        agl = d_pos[..., 2] - self._terrain_z(d_pos[..., :2])                # [P,N,D]
        wind = WIND.wind_at(gust_t, self.mean_wind, agl, c.wind_z0, c.wind_z_ref)   # [P,N,D,3]

        # ===== 3. drone dynamics (CTBR Level-A) =====
        thrust = c.drone_t_max * torch.sigmoid(a_drone[..., 0])             # [P,N,D] collective thrust
        thrust = thrust * (d_energy > 0).float()                            # dead battery -> no thrust (falls)
        omega_cmd = c.drone_omega_max * torch.tanh(a_drone[..., 1:4])
        ge = AERO.ground_effect_factor(agl, c.rotor_radius, c.ge_coef)      # [P,N,D]
        np_, nv, nq, nw = QUAD.quad_step(d_pos, d_vel, d_quat, d_omega, thrust, omega_cmd, wind, ge,
                                         c.drone_mass, c.tau_omega, c.drag_quad, c.drag_lin, c.gravity, c.dt)
        d_pos = torch.where(active_d[..., None], np_, d_pos)
        d_vel = torch.where(active_d[..., None], nv, d_vel)
        d_quat = torch.where(active_d[..., None], nq, d_quat)
        d_omega = torch.where(active_d[..., None], nw, d_omega)
        # keep drones inside the arena box + under the ceiling (soft clamp, not a crash; the terrain
        # floor is handled by the crash test below). Idempotent for in-bounds / inactive drones.
        d_xy = d_pos[..., :2].clamp(-c.arena_half, c.arena_half)
        tz_new = self._terrain_z(d_xy)                                       # terrain at post-move xy (reused for crash)
        d_z = torch.minimum(d_pos[..., 2], tz_new + c.ceiling)
        d_pos = torch.cat([d_xy, d_z[..., None]], -1)
        # battery drain (P ~ hover_power * (thrust/mg)^1.5 grey-box, SOURCES G3)
        thr_ratio = (thrust / (c.drone_mass * c.gravity + c.eps)).clamp(min=0.0)
        power = c.hover_power_w * thr_ratio ** 1.5
        d_energy = torch.clamp(d_energy - power * c.dt * af, min=0.0)

        # ===== 4. enemy dynamics (type-gated: tank unicycle / soldier social-force) =====
        ep, eh, ev, e_alive, e_cd = s["e_pos"], s["e_head"], s["e_vel"], s["e_alive"], s["e_cd"]
        is_tank = (self.e_type[None] > 0.5)                                  # [1,N,E] -> broadcast
        slope = TERR.height_grad(self.hf, ep, self.extent)                   # [P,N,E,2]
        # tank branch
        v_tank = c.tank_speed_max * 0.5 * (torch.tanh(a_enemy[..., 0]) + 1.0)
        om_tank = c.tank_omega_max * torch.tanh(a_enemy[..., 1])
        head_dir = torch.stack([torch.cos(eh), torch.sin(eh)], -1)
        slope_along_tank = (slope * head_dir).sum(-1)
        tob_t = GND.tobler_factor(slope_along_tank)
        pos_tank, head_tank = GND.unicycle_step(ep, eh, v_tank, om_tank, tob_t, c.dt)
        vel_tank = (pos_tank - ep) / c.dt
        # soldier branch
        desired = c.soldier_speed_max * torch.tanh(a_enemy[..., 0:2])       # [P,N,E,2]
        # obstacle footprint is z-independent (obst_half2 has a huge half-height), so skip the terrain
        # gather and use z=0 — the horizontal cross-section is all the ground unit needs.
        ep3_foot = torch.cat([ep, torch.zeros_like(ep[..., :1])], -1)
        oclr, ograd = self._nearest_obstacle(ep3_foot, self.obst_half2)     # footprint clearance
        accel = GND.social_force(ep, ev, desired, e_alive, c.sfm_A / c.sfm_mass, c.sfm_B,
                                 c.soldier_tau, c.soldier_radius,
                                 obst_sdf=oclr, obst_grad=ograd[..., :2],
                                 A_w=c.sfm_A / c.sfm_mass, B_w=c.sfm_B)
        vel_sol = ev + accel * c.dt
        sp = torch.sqrt((vel_sol * vel_sol).sum(-1, keepdim=True) + c.eps)
        move_dir = vel_sol / sp                                              # direction (clamp below is a +ve rescale)
        vel_sol = vel_sol * torch.clamp(c.soldier_speed_max / sp, max=1.0)
        slope_along_sol = (slope * move_dir).sum(-1)
        tob_s = GND.tobler_factor(slope_along_sol)
        pos_sol = ep + vel_sol * tob_s[..., None] * c.dt
        head_sol = torch.atan2(vel_sol[..., 1], vel_sol[..., 0])
        # select by type
        it = is_tank.expand(P, N, E)
        e_pos = torch.where(it[..., None], pos_tank, pos_sol)
        e_head = torch.where(it, head_tank, head_sol)
        e_vel = torch.where(it[..., None], vel_tank, vel_sol)
        # freeze dead enemies, clamp to arena
        e_pos = torch.where(e_alive[..., None] > 0.5, e_pos, ep)
        e_head = torch.where(e_alive > 0.5, e_head, eh)
        e_vel = torch.where(e_alive[..., None] > 0.5, e_vel, torch.zeros_like(e_vel))
        e_pos = e_pos.clamp(-c.arena_half, c.arena_half)
        ep3 = self._enemy_pos3(e_pos)

        # distances drone<->enemy (SHARED: AA fire below + kamikaze contact + closing shaping)
        rel_ed = d_pos[:, :, None, :, :] - ep3[:, :, :, None, :]            # [P,N,E,D,3]
        dist_ed = torch.sqrt((rel_ed * rel_ed).sum(-1) + c.eps)            # [P,N,E,D]
        # HORIZONTAL geometry drone<->enemy — the reward approaches enemies HORIZONTALLY (at altitude),
        # NOT along the 3D vector (which points down into the ground where the enemies sit, so drones dove
        # into the earth from spawn). agl_ed = drone altitude above the enemy. nearest enemy by HORIZONTAL
        # distance (+ its above-altitude), reused by the crash grace and the closing/strike reward.
        dxy_ed = torch.sqrt((rel_ed[..., :2] ** 2).sum(-1) + c.eps)        # [P,N,E,D] horizontal separation
        agl_ed = rel_ed[..., 2]                                            # [P,N,E,D] drone-above-enemy altitude
        dxy_de = torch.where(e_alive[..., None] > 0.5, dxy_ed, torch.full_like(dxy_ed, 1e18))
        d_near_xy = dxy_de.amin(2)                                        # [P,N,D] nearest-enemy horiz dist (crash grace)

        # ===== 5. anti-air fire (CEP hitscan; enemy targets its nearest alive drone). COMPILE-TIME
        # GATE: self.aa_enabled is a python const set BEFORE torch.compile (monstro _has_sq idiom), so
        # when ejected the entire block below (targeting, p_hit, maneuver term, one-hot scatter) is
        # compiled OUT — no wasted AA math runs. Not a per-element data branch; branchless at runtime. =====
        if self.aa_enabled:
            d_valid = active_d[:, :, None, :].expand(P, N, E, D)
            dmask = torch.where(d_valid, dist_ed, torch.full_like(dist_ed, 1e18))
            tgt_dist, tgt_idx = dmask.min(-1)                              # [P,N,E] nearest drone
            has_tgt = tgt_dist < 1e17
            in_range = tgt_dist < c.aa_range
            # crossing-speed evasion proxy -> maneuver variance (SOURCES aa-fire; jinking/crossing lowers P)
            los = torch.gather(rel_ed, 3, tgt_idx[..., None, None].expand(P, N, E, 1, 3)).squeeze(3)
            los = los / (torch.sqrt((los * los).sum(-1, keepdim=True)) + c.eps)
            vtgt = torch.gather(d_vel[:, :, None, :, :].expand(P, N, E, D, 3), 3,
                                tgt_idx[..., None, None].expand(P, N, E, 1, 3)).squeeze(3)   # [P,N,E,3]
            perp = vtgt - (vtgt * los).sum(-1, keepdim=True) * los
            perp_speed = torch.sqrt((perp * perp).sum(-1) + c.eps)
            t_f = tgt_dist / c.aa_muzzle_soldier
            extra_var = (perp_speed * t_f) ** 2 * c.aa_maneuver_penalty
            p = AA.p_hit(tgt_dist, c.aa_target_radius, c.aa_sigma_ang, extra_var) * self._aa_scale_t
            fire_gate = (a_enemy[..., 2] > 0).float() * (e_cd <= 0).float() * e_alive \
                        * in_range.float() * has_tgt.float()
            hit_e = AA.resolve_fire(fire_gate, p, aa_roll_t[None].expand(P, N, E))   # [P,N,E]
            onehot = torch.zeros(P, N, E, D, device=dev).scatter(3, tgt_idx[..., None], 1.0)
            aa_killed = ((onehot * hit_e[..., None]).sum(2) > 0.5) & active_d          # [P,N,D]
            e_cd = torch.where(fire_gate > 0.5, torch.full_like(e_cd, float(self.cd_ticks)),
                               torch.clamp(e_cd - 1.0, min=0.0))
        else:                                                             # ejected: enemies only maneuver
            hit_e = torch.zeros(P, N, E, device=dev)
            aa_killed = torch.zeros(P, N, D, dtype=torch.bool, device=dev)

        # ===== 6. collisions =====
        # drone <-> enemy kamikaze (3D contact -> BOTH die, +kill). Radius = the curriculum knob (0-d tensor).
        contact = (dist_ed < self._kill_r_t) & active_d[:, :, None, :] & e_alive[..., None].bool()
        # contact is [P,N,E,D]
        drone_kama = contact.any(2)                                        # [P,N,D] drone hit an enemy
        enemy_hit = contact.any(3)                                         # [P,N,E] enemy hit by a drone
        # drone <-> terrain / obstacle crash. agl2 reuses tz_new (d_pos.xy == d_xy after the clamp);
        # o_clr uses the SDF-only path (the crash test never needs the obstacle gradient).
        agl2 = d_pos[..., 2] - tz_new
        o_clr = self._nearest_obstacle_clr(d_pos, self.obst_half)
        # a drone clipping terrain while horizontally OVER an alive enemy is a committed DIVE, not a
        # botched flight -> grace (non-fatal), so the swarm can PRACTICE diving without dying every attempt.
        committed = d_near_xy < self.commit_radius
        crash = (((agl2 < c.drone_radius) | (o_clr < c.drone_radius)) & active_d) & (~drone_kama) & (~committed)
        # BUT the grace must not let a graced drone SINK THROUGH the terrain and get stuck underground
        # (diagnosed: median AGL -15 m — drones dropped out of the fight into the ground). Clamp a
        # committed drone that dipped below the surface back UP to the ground (skim it) and kill its
        # downward velocity — a physical dive-to-surface, not a bug hole.
        below = (agl2 < c.drone_radius) & active_d & committed & (~drone_kama)
        surf_z = tz_new + c.drone_radius
        d_pos = torch.cat([d_pos[..., :2],
                           torch.where(below, torch.maximum(d_pos[..., 2], surf_z), d_pos[..., 2])[..., None]], -1)
        d_vel = torch.cat([d_vel[..., :2],
                           torch.where(below & (d_vel[..., 2] < 0), torch.zeros_like(d_vel[..., 2]),
                                       d_vel[..., 2])[..., None]], -1)
        # drone <-> drone Hunt-Crossley soft penalty (nudge velocities apart; no death)
        dd = d_pos[:, :, :, None, :] - d_pos[:, :, None, :, :]              # [P,N,D,D,3]
        dl = torch.sqrt((dd * dd).sum(-1) + c.eps)
        nrm = dd / dl[..., None]                                            # unit drone->drone (reused: rate + push)
        pen = (2.0 * c.drone_radius) - dl                                  # penetration depth
        pair = af[:, :, :, None] * af[:, :, None, :] * (1.0 - self._eye_d)
        pen_rate = -((d_vel[:, :, :, None, :] - d_vel[:, :, None, :, :]) * nrm).sum(-1)
        f = CON.hunt_crossley_force(pen, pen_rate, c.hc_stiffness, c.hc_damping, c.hc_exponent) * pair
        push = (f[..., None] * nrm).sum(3) / c.drone_mass * c.dt            # impulse -> dv
        d_vel = torch.where(active_d[..., None], d_vel + push, d_vel)

        # ===== 7. resolve life/death, rewards =====
        drone_died = (drone_kama | crash | aa_killed) & active_d
        d_alive = torch.where(drone_died, torch.zeros_like(d_alive), d_alive)
        was_e_alive = e_alive > 0.5
        killed_e = enemy_hit & was_e_alive                                 # [P,N,E] newly killed (reused)
        e_alive = torch.where(killed_e, torch.zeros_like(e_alive), e_alive)
        kills_now = killed_e.float().sum(-1)                               # [P,N] enemies killed this tick
        died_wo_kill = (crash | aa_killed).float().sum(-1)                 # wasted drones this tick
        losses_now = drone_died.float().sum(-1)
        kills = s["kills"] + kills_now
        losses = s["losses"] + losses_now
        # cleared bonus: all enemies just became dead
        e_left = e_alive.sum(-1)
        cleared_now = ((e_left < 0.5) & (s["e_alive"].sum(-1) >= 0.5)).float()
        # ============================ DRONE REWARD ==================================================
        # KILL dominates; the HOMING shaping below is POTENTIAL-BASED (Ng, Harada & Russell 1999) — we
        # reward the CHANGE in a potential, not its level, so it telescopes to a bounded episode total and
        # can never dominate the sparse kill signal (the lesson from the alt-penalty domination bug that
        # was 95.8% of the reward). Loitering nets 0 (delta 0), circling nets 0 (round-trip telescopes).
        #
        # HOMING = PROPORTIONAL NAVIGATION: steer at where the target WILL BE, not where it is. This is the
        # law dragonflies, robber flies, bats AND missiles all use (a = N*V_c*lambda_dot). We express it as
        # a potential = closeness to the LEAD (intercept) point, so PN homing stays un-farmable & bounded.
        #
        d_xy = d_pos[..., :2]                                              # [P,N,D,2] this drone's horizontal position
        sc = self.scale.view(1, N, 1)                                      # [1,N,1] per-env length scale (engage_range)
        # ---- SWARM-DISPERSED HOMING (anti-dogpile): reward each drone for closing on its BALANCED-ASSIGNED
        #      enemy, NOT the single nearest one the whole swarm piles onto. Reuse the SAME Sinkhorn OT oracle
        #      the obs uses (Cuturi 2013): a doubly-normalised soft matching whose balanced marginals SPREAD the
        #      swarm across enemies. Before, the seek pulled every drone to the shared nearest target (dogpile),
        #      and the assignment was only an obs HINT with no reward backing, so the policy ignored it. Now the
        #      shaping gradient itself disperses the swarm. Still a pure function of state -> potential-based. ----
        dde = dxy_de.transpose(2, 3)                                       # [P,N,D,E] horiz range drone->enemy (dead=1e18)
        d2e_r = (dde / sc[..., None]).clamp(max=c.obs_clamp)               # [P,N,D,E] normalised dist (O(1) for Sinkhorn)
        T_r = ASSIGN.balanced_assignment(d2e_r, af, e_alive)              # [P,N,D,E] balanced transport plan
        w_r = T_r / (T_r.sum(-1, keepdim=True) + c.eps)                   # [P,N,D,E] per-drone distribution over enemies
        # ---- PN lead PER ENEMY: predict where each enemy will be after this drone's time-to-go to IT ----
        t_go_e = (dde / c.drone_speed_max)[..., None]                     # [P,N,D,E,1] seconds to close each gap
        lead_e = e_pos[:, :, None, :, :] + e_vel[:, :, None, :, :] * t_go_e  # [P,N,D,E,2] predicted (lead) enemy positions
        R_e = lead_e - d_xy[:, :, :, None, :]                             # [P,N,D,E,2] drone -> each lead point
        r_lead_e = torch.sqrt((R_e * R_e).sum(-1) + c.eps)               # [P,N,D,E] range to each lead point
        # ---- SEEK potential: 1 on a lead point, fading to 0 at detection_range; ASSIGNMENT-WEIGHTED across
        #      enemies so a drone is rewarded for intercepting ITS assigned target(s). HORIZONTAL only (never
        #      pulls into the ground). ----
        seek_e = torch.clamp(1.0 - r_lead_e / self.detection_range, min=0.0)  # [P,N,D,E] per-enemy homing potential
        seek = (w_r * seek_e).sum(-1)                                     # [P,N,D] balanced-assignment-weighted seek
        # ---- STRIKE: reward DESCENDING onto the target, ASSIGNMENT-WEIGHTED (same w_r) so a drone is only
        #      rewarded for diving on ITS assigned enemy — NOT for piling onto whatever's nearest. This term is
        #      rw_commit=2.5x the seek, so when it was nearest-based it drowned the dispersion signal and kept
        #      the swarm dogpiled (measured: ~5 drones on one enemy). Weighting it by the balanced plan makes
        #      the WHOLE potential respect the assignment -> the shaping disperses the swarm end-to-end. ----
        over_e = torch.clamp(1.0 - dde / self.commit_radius, min=0.0)       # [P,N,D,E] 1 = horizontally over each enemy
        agl_de = agl_ed.transpose(2, 3)                                    # [P,N,D,E] drone altitude above each enemy
        descent_e = torch.clamp(1.0 - agl_de.clamp(min=0.0) / c.ceiling, min=0.0)  # [P,N,D,E] 1 = down at its altitude
        strike = (w_r * over_e * descent_e).sum(-1)                        # [P,N,D] assignment-weighted strike
        # ---- combined potential Phi = homing + weighted strike; reward its net INCREASE (progress) ----
        prox_new = seek + self.rw_commit * strike                          # [P,N,D] Phi_t (this tick's potential)
        delta = torch.where(just, torch.zeros_like(prox_new), prox_new - s["d_prox"])  # Phi_t - Phi_{t-1} (0 on spawn)
        hunt_r = (delta * af).sum(-1)                                       # [P,N] reward net progress, alive drones only
        d_prox = torch.where(active_d, prox_new, torch.zeros_like(prox_new))  # [P,N,D] carry Phi to next tick (0 if dead)
        # ---- flight substrate (alt-hold / evade / smoothness): DISABLED (rw=0) — kept for future re-enable as
        #      bounded potentials. MEAN over alive drones (a per-drone RATE), never a raw per-tick sum. ----
        n_alive = af.sum(-1) + c.eps                                        # [P,N] alive-drone count (safe denominator)
        over = (w_r * over_e).sum(-1)                                       # [P,N,D] assignment-weighted "over a target"
        # SMOOTH ground-clearance brake (SHAC-differentiable earth-avoidance): penalise fast descent near the
        # deck EXCEPT when diving onto a target. clamps of agl+vz -> analytic gradient (the hard crash is 0-grad).
        ground_prox = torch.clamp(1.0 - agl2 / self.clearance_range, min=0.0)         # [P,N,D] 1 at deck -> 0 above
        descent_rate = torch.clamp(-d_vel[..., 2] / c.drone_speed_max, min=0.0)       # [P,N,D] normalized downward speed
        brake = (ground_prox * descent_rate * (1.0 - over) * af).sum(-1) / n_alive    # [P,N] mean over alive drones
        # alt/evade substrate is DISABLED (rw_alt=rw_evade=0); Inductor can't fold 0*x -> gate behind the
        # python-const idiom so they only run when consumed (a live weight, or the eval decompose panel).
        if self.rw_alt or self.rw_evade or self.decompose:
            alt_pen = (torch.clamp(1.0 - agl2 / self.cruise_alt, min=0.0) * (1.0 - over) * af).sum(-1) / n_alive
            evade_pen = (torch.clamp(1.0 - o_clr / self.evade_range, min=0.0) * af).sum(-1) / n_alive
        else:
            alt_pen = evade_pen = torch.zeros_like(n_alive)
        smooth = (torch.abs(omega_cmd).sum(-1) * af).sum(-1) / (n_alive * c.drone_omega_max)                   # rate thrashing
        # ---- total: +kill(dominant) +clear(bonus) -wasted(crash) +homing(bounded potential) -substrate(off) ----
        r_drone = (self.rw_kill * kills_now                                 # [P,N] +N per enemy killed this tick (dominant)
                   + self.rw_clear * cleared_now                           #       +big one-off when the last enemy dies
                   - self.rw_waste * died_wo_kill                          #       -per drone that died WITHOUT a kill
                   + self.rw_close * hunt_r                                #       +PN homing progress (potential delta)
                   - self.rw_alt * alt_pen - self.rw_evade * evade_pen     #       flight substrate (rw=0 -> no effect)
                   - self.rw_brake * brake                                 #       -fast descent near the deck (avoid earth)
                   - self.rw_smooth * smooth)                              #       tiny smoothness cost
        # enemy team reward
        alive_frac = e_alive.mean(-1)
        aa_hits_now = hit_e.sum(-1)
        # clump penalty (pairwise closeness among alive enemies)
        de = e_pos[:, :, :, None, :] - e_pos[:, :, None, :, :]
        del_ = torch.sqrt((de * de).sum(-1) + c.eps)
        epair = e_alive[:, :, :, None] * e_alive[:, :, None, :] * (1.0 - self._eye_e)
        clump = (torch.clamp(1.0 - del_ / (2.0 * c.tank_radius + c.soldier_radius), min=0.0) * epair).sum((-1, -2))
        # edge-camp penalty: chebyshev dist from arena centre, ramped 0->1 from edge_soft out to the wall,
        # averaged over alive enemies (bounded [0,1] -> comparable scale to alive_frac; safe denom).
        cheby = e_pos.abs().amax(-1)                                        # [P,N,E] L-inf dist from centre
        edge = (torch.clamp((cheby - self.edge_soft) / (self.combat_half - self.edge_soft + c.eps), 0.0, 1.0)
                * e_alive).sum(-1) / (e_alive.sum(-1) + c.eps)             # [P,N] mean edge-proximity, alive only
        r_enemy = (self.rw_e_alive * alive_frac - self.rw_e_death * kills_now
                   + self.rw_e_aa * aa_hits_now - self.rw_e_clump * clump
                   - self.rw_e_edge * edge)                                #       -stay-off-the-wall

        ns = dict(d_pos=d_pos, d_vel=d_vel, d_quat=d_quat, d_omega=d_omega,
                  d_act=d_act, d_alive=d_alive, d_energy=d_energy, d_prox=d_prox,
                  d_crash=torch.maximum(s["d_crash"], crash.float()),  # sticky terrain/obstacle-crash flag (render)
                  e_pos=e_pos, e_head=e_head, e_vel=e_vel, e_alive=e_alive, e_cd=e_cd,
                  kills=kills, losses=losses)
        done_d = drone_died.float()
        done_e = (enemy_hit & was_e_alive).float()
        panel = None
        if self.decompose:                                        # WEIGHTED contribution of each drone-reward term
            panel = {"r_kill": (self.rw_kill * kills_now).sum(), "r_clear": (self.rw_clear * cleared_now).sum(),
                     "r_waste": (-self.rw_waste * died_wo_kill).sum(), "r_hunt": (self.rw_close * hunt_r).sum(),
                     "r_alt": (-self.rw_alt * alt_pen).sum(), "r_evade": (-self.rw_evade * evade_pen).sum(),
                     "r_brake": (-self.rw_brake * brake).sum(),
                     "r_smooth": (-self.rw_smooth * smooth).sum(), "kills": kills_now.sum(),
                     "ticks": torch.ones((), device=dev)}
        return ns, r_drone, r_enemy, done_d, done_e, panel

    # ---- one decision = act_every physics ticks (held actions) ----
    def step_dec(self, s, k, a_drone, a_enemy, record=None, record_stride=2):
        """Advance one policy decision: act_every compiled ticks with zero-order-hold actions. Slices
        the per-tick schedule tensors EAGERLY here (monstro step_pa pattern) so _core traces once.
        Returns (ns, r_drone[P,N], r_enemy[P,N], done_d[P,N,D], done_e[P,N,E]) summed over the ticks."""
        c = self.cfg
        P = s["d_pos"].shape[0]
        rp = torch.zeros(P, self.N, device=self.device)
        re = torch.zeros(P, self.N, device=self.device)
        dd = torch.zeros(P, self.N, self.D, device=self.device)
        de = torch.zeros(P, self.N, self.E, device=self.device)
        t0 = k * c.act_every
        for j in range(c.act_every):                                        # TIME-LOOP-OK
            t = min(t0 + j, self.T - 1)
            gust_t = self.gust[:, t, :]                                      # [N,3]
            aa_roll_t = self.aa_roll[:, t, :]                               # [N,E]
            due = (self.spawn_tick <= float(t))[None].expand(P, self.N, self.D)   # [P,N,D]
            s, r_d, r_e, done_d, done_e, _ = self._core(s, gust_t, aa_roll_t, due.float(), a_drone, a_enemy)
            rp = rp + r_d; re = re + r_e; dd = dd + done_d; de = de + done_e
            if record is not None and j % record_stride == 0:
                record.append(self._snapshot(s))
        return s, rp, re, dd.clamp(max=1.0), de.clamp(max=1.0)

    def _snapshot(self, s):
        """CPU snapshot for the renderer (external kinematics only)."""
        g = lambda x: x.detach().cpu().numpy()
        return dict(d_pos=g(s["d_pos"]), d_quat=g(s["d_quat"]), d_alive=g(s["d_alive"]), d_act=g(s["d_act"]),
                    d_crash=g(s["d_crash"]),
                    e_pos=g(s["e_pos"]), e_alive=g(s["e_alive"]), e_type=g(self.e_type),
                    kills=g(s["kills"]), losses=g(s["losses"]))
