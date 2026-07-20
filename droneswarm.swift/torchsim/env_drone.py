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
import torch.nn.functional as F

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
            a_d, h, assign = drone_fn(*d_obs, h_in)                       # GROUP policy also returns the target assignment
        else:
            h_in = None
            a_d = drone_fn(*d_obs)
            e_al = s["e_alive"]                                          # feedforward fallback (unused for the drone):
            assign = e_al[:, :, None, :].expand(-1, -1, a_d.shape[2], -1)   # uniform over alive enemies
            assign = assign / assign.sum(-1, keepdim=True).clamp_min(1e-8)
        a_e = enemy_fn(*e_obs)
        ns, r_d, r_e, done_d, done_e = env.step_dec(s, k, a_d, a_e, assign, record=record, record_stride=record_stride)
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
    DRONE_RAYS = 192      # egocentric DEPTH-GRID sensor: 16 az x 12 el low-res depth image (raw bbox geometry,
    #                       not types). ~matches the 16x12 depth image of "Back to Newton's Laws" diff-physics.
    DRONE_SELF_F = 26     # 13 base [bz3 vel3 rate3 agl1 batt1 slope2] + 13 nav [flow2 geo1 overht1 patch9]. Target sel is now
    #                       the policy's own LEARNED token-attention (no hand-coded Sinkhorn tgt_dir/focus).
    DRONE_TOK_F = 10      # rel_dir(3) dist(1) rvel(3) closing(1) is_enemy(1) enemy_tank(1)  (coordination now in the GROUP layer)
    DRONE_K = 12          # attended tokens per drone (nearest drones + enemies)
    DRONE_ACT = 4         # CTBR: (thrust, wx, wy, wz) pre-squash
    ENEMY_SELF_F = 12     # +1: obstacle CLEARANCE scalar added so tanks sense how close, not just direction
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
        ob = t(sched["obst"])                                     # [N,O,10] x,y,zc,hx,hy,hz,is_cyl, vx,vy,vz
        self.obst_xyz = ob[..., 0:3].contiguous()                 # INITIAL centre; obstacles are DYNAMIC -> the LIVE
        #                                                           centre lives in the state dict, moved each tick in _core
        self.obst_half = ob[..., 3:6].contiguous()                # half-extent (STATIC — obstacles don't resize)
        self.obst_cyl = ob[..., 6].contiguous()
        self.obst_vel0 = ob[..., 7:10].contiguous()               # per-scene DRIFT velocity (0 for 'static' classes)
        self.obst_mask = (self.obst_half.abs().sum(-1) > 1e-6).float()   # [N,O] valid obstacle
        # a drifting obstacle bounces its CENTRE inside the arena (before the footprint touches the wall):
        self.obst_bound = (c.arena_half - self.obst_half[..., :2].amax(-1)).clamp(min=0.0)   # [N,O]
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
        # egocentric DEPTH-GRID directions (constant): AZ azimuth x EL elevation = DRONE_RAYS rays, a low-res
        # spherical depth "image" the drone reads via raycast_aabb each decision (raw bbox geometry, not types;
        # [[prefer-learnable-features]]). World-frame panorama centred on the drone; elevation spans down..
        # slightly-up so it senses obstacles around AND below (for the dive). 16x12 ~ "Back to Newton's Laws".
        AZ, EL = 16, 12                                          # AZ*EL must == DRONE_RAYS (192)
        _az = torch.arange(AZ, device=device, dtype=torch.float32) * (2 * np.pi / AZ)            # [AZ]
        _el = torch.linspace(float(np.radians(-55.0)), float(np.radians(15.0)), EL, device=device)  # [EL] down->up
        _elg, _azg = torch.meshgrid(_el, _az, indexing="ij")     # [EL,AZ]
        _ce = torch.cos(_elg)
        self.ray_dirs = torch.stack([_ce * torch.cos(_azg), _ce * torch.sin(_azg),
                                     torch.sin(_elg)], -1).reshape(-1, 3)                          # [AZ*EL,3] unit
        self.ray_range = 20.0                                     # depth sense range [m] — absolute, ~0.9 s of
        #                                                           reaction at top speed (NOT tied to the small
        #                                                           engage_range normalizer, which would give ~4 m)
        # --- DYNAMIC NAVIGATION FIELD grid (GPU flow/eikonal pathfinding; REPLACES the ray fan) ---
        # One geodesic distance-to-enemy field per env over a G x G arena grid, REBUILT each decision from the LIVE
        # obstacle+enemy state and sampled by every drone (cost ~ map size, not agent count). Static grid geometry:
        # 3D field: a G x G x Gz geodesic VOLUME so the flow carries the DESCENT (drone routes up-over / down-onto
        # the ground enemy in one 3D vector). QUANTIZED for memory: horizontal G coarse, vertical Gz tiny (z only
        # spans ground..ceiling). Real obstacle heights -> a drone can fly OVER a short building, not just around it.
        self.nav_G = int(getattr(c, "nav_grid3d", 12)); G = self.nav_G          # horizontal cells — START VERY SCARCE (low VRAM)
        self.nav_Gz = int(getattr(c, "nav_gz", 6)); Gz = self.nav_Gz            # vertical cells (QUANTIZED: ground..ceiling)
        self.nav_sweeps = int(getattr(c, "nav_sweeps", 40))                     # FIXED unrolled min-relaxation passes
        self.nav_zlo = -1.0; self.nav_zhi = float(c.ceiling) + 1.0              # z span (just below ground .. above ceiling)
        _lin = torch.linspace(-self.extent, self.extent, G, device=device)     # [G] xy cell centres
        _zlin = torch.linspace(self.nav_zlo, self.nav_zhi, Gz, device=device)  # [Gz] z cell centres
        _zc, _gy, _gx = torch.meshgrid(_zlin, _lin, _lin, indexing="ij")        # [Gz,G,G] (z, y, x)
        self.nav_xyz = torch.stack([_gx, _gy, _zc], -1)                         # [Gz,G,G,3] 3D cell centres
        self.nav_cell = float(2.0 * self.extent / max(1, G - 1))               # xy pitch (straight xy move cost)
        self.nav_diag = self.nav_cell * 1.41421356                             # xy diagonal cost
        self.nav_zcell = float((self.nav_zhi - self.nav_zlo) / max(1, Gz - 1)) # z pitch (vertical move cost)
        # --- SUPERVISOR clip params: the field is the authority on ALLOWED states; the drone only ever knows what
        #     the supervisor permits. Base clip = the robot BODY radius (a physical size, not a tuned scalar); the
        #     dyna-r ground floor ADDS the stopping distance from the CURRENT descent speed each rebuild (in
        #     _build_navfield). No `nav_clear` -- inflation is the body only. ---
        self.nav_r_body = float(c.drone_radius)                                # robot body radius = supervisor BASE clip
        _gxy = self.nav_xyz[0, :, :, :2].reshape(G * G, 2)[None, None].expand(1, self.N, G * G, 2)   # [1,N,G*G,2]
        self.nav_ground = TERR.height(self.hf, _gxy, self.extent)[0].reshape(self.N, G, G).contiguous()   # [N,G,G] terrain under each cell (static)
        self.nav_los_K = 4                                                     # LOS segment sample count (fixed unroll size)
        self.nav_los_t = torch.linspace(0.0, 1.0, self.nav_los_K + 2, device=device)[1:-1]   # [K] interior segment fractions
        # ---- BASE-CONTROLLER GAIN DEFAULTS (raw = softplus^-1(physical); F.softplus applied in _core). Used by tests /
        #      open-loop when no policy gains are attached. TRAINING overrides self.ctrl_gains with the LEARNABLE dparams
        #      leaves (policy_recur.ctrl_gains) so they train via SAPO's analytic gradient + save/load with the model. ----
        _ci = {"v_cruise": 0.5 * c.drone_speed_max, "tau": 0.1, "t_look": 0.2, "k_v": 2.0, "k_R": 10.0,
               "v_override": 0.25 * c.drone_speed_max, "urgency_gain": 0.3}
        self.ctrl_gains = {k: torch.tensor(float(v), device=device).expm1().log() for k, v in _ci.items()}   # softplus^-1
        self._spawn_pos = (self.base_pos[:, None, :] + self.spawn_off).contiguous()   # [N,D,3] static launch point
        self._eye_d = torch.eye(self.D, device=device)[None, None]        # [1,1,D,D] self-pair masks (static)
        self._eye_e = torch.eye(self.E, device=device)[None, None]        # [1,1,E,E]
        self._drone_self_mask = torch.cat(                                # [D, D+E] excludes drone i as its own token
            [torch.eye(self.D, device=device), torch.zeros(self.D, self.E, device=device)], 1)
        # DRONE REWARD = the true objective (kills_now - died_wo_kill, both COUNT-weight 1) + ONE potential-based
        # shaping term Phi (built in _core from physical actuator limits — no tuned scale). The old hand-tuned
        # rw_kill/clear/close/commit/brake/apf weights + commit_radius/clearance_range/apf_range ranges are GONE:
        # homing/dive/avoidance EMERGE from Phi + the learned critic, not from sculpted per-tick penalties.
        self.los_scale = 5.0                               # clear-shot token: metres of path clearance -> tanh saturates
        # ---- LOT (learnable obs transform) metadata: env emits MAGNITUDE features RAW (no /scale, no clamp); the
        #      policy applies asinh(g*(x-b)) with LEARNABLE per-feature g,b (init g=1/scale below = a sane starting
        #      range, NOT a baked constant — the net learns g,b). mask=1 marks the magnitude features that get the
        #      transform; directions/flags/nav-field pass through untouched (asinh would distort a unit vector).
        _vmax = c.drone_speed_max; _wmax = c.drone_omega_max; _er = c.engage_range
        # self_feat layout: bz(3) dv(3) dw(3) agl(1) energy(1) tgrad(2) nav_feat(13) = 26
        self.self_mag_mask  = torch.tensor([0,0,0, 1,1,1, 1,1,1, 1, 0, 1,1] + [0]*13, dtype=torch.float32, device=device)
        self.self_lot_scale = torch.tensor([1,1,1, _vmax,_vmax,_vmax, _wmax,_wmax,_wmax, _er, 1, 1,1] + [1]*13, dtype=torch.float32, device=device)
        # token layout: rel_dir(3) dist(1) rvel(3) closing(1) is_enemy(1) enemy_tank(1) = 10
        self.tok_mag_mask   = torch.tensor([0,0,0, 1, 1,1,1, 1, 0,0], dtype=torch.float32, device=device)
        self.tok_lot_scale  = torch.tensor([1,1,1, _er, _vmax,_vmax,_vmax, _vmax, 1,1], dtype=torch.float32, device=device)
        # ---- physical scales for the reward potential Phi (from actuator limits — NO tuning knobs): ----
        _g = c.gravity
        self.a_up  = (c.drone_t2w - 1.0) * _g                       # max net climb decel [m/s^2] — arrest a descent
        self.a_lat = _g * (c.drone_t2w ** 2 - 1.0) ** 0.5          # max lateral decel [m/s^2] — arrest horizontal closing
        self.T_ep  = self.T * c.dt                                 # episode duration [s] — Phi normalization (magnitude only)
        self.stop_dist = c.drone_speed_max ** 2 / (2.0 * self.a_lat)   # horizontal stopping distance [m] — terrain-grace gate
        # SEEK range: in v1 detection is PERFECT (all enemies visible), so seek must cover the whole arena
        # INCLUDING the far corners (arena diagonal = 2*sqrt(2)*arena_half ~= 2.83*arena_half) — else a drone
        # in a corner gets NO homing gradient and drifts/flies away. 3x covers the diagonal with margin.
        # Range-gated detection returns later via the SensorChannel.
        # COMBAT ZONE: the central square the fight lives in. Spawns, the homing gradient, and the enemy
        # edge-penalty all key off this (not arena_half), so a 3x arena can hold a 1x-scale engagement in its
        # middle. Homing/edge MUST use combat_half — if they used arena_half=3x, detection_range balloons and
        # the seek gradient goes flat over the combat zone (the swarm barely learns). 0 => == arena_half.
        self.combat_half = c.combat_half if c.combat_half > 0 else c.arena_half
        self.detection_range = 3.0 * self.combat_half      # nav-field geodesic-distance normalization (perception only)
        # nav-field FLOW-ALIGNMENT reward: differentiable "move along the computed route" term (the field lookup
        # itself is detached/non-diff, so this keeps SAPO's analytic actor gradient alive for obstacle routing).
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
        st = dict(
            d_pos=self.base_pos[None, :, None, :].expand(P, N, D, 3).clone(),
            d_vel=z(P, N, D, 3), d_quat=quat, d_omega=z(P, N, D, 3),
            d_act=z(P, N, D), d_alive=z(P, N, D),
            d_energy=torch.full((P, N, D), c.batt_capacity_j, device=dev),
            phi_prev=z(P, N),                                    # last-decision per-env potential Phi (potential-based shaping)
            d_vref=z(P, N, D, 3),                                # base-controller reference-velocity LOW-PASS state (smoothing); reset on spawn
            d_crash=z(P, N, D),                                  # sticky: 1 once a drone died by terrain/obstacle crash (render)
            e_pos=self.e_pos0[None].expand(P, N, E, 2).clone(),
            e_head=self.e_head0[None].expand(P, N, E).clone(),
            e_vel=z(P, N, E, 2), e_alive=torch.ones(P, N, E, device=dev),
            e_cd=z(P, N, E), kills=z(P, N), losses=z(P, N),
            obst_xyz=self.obst_xyz.clone(),                      # DYNAMIC obstacles: LIVE centre, [N,O,3] (P-invariant:
            obst_vel=self.obst_vel0.clone(),                    #   deterministic per-scene motion is identical across P)
        )
        nd, nfl, no, na, ntb = self._build_navfield(st["obst_xyz"], st["e_pos"], st["e_alive"], z(P, N))   # seed SUPERVISOR
        st["nav_dist"] = nd; st["nav_flow"] = nfl; st["nav_occ"] = no; st["nav_allowed"] = na; st["nav_tube"] = ntb
        return st

    # ---- geometry helpers ----
    def _terrain_z(self, xy):
        """Terrain height at xy [P,N,K,2] -> [P,N,K]."""
        return TERR.height(self.hf, xy, self.extent)

    def _enemy_pos3(self, e_pos):
        """Enemy 3D position = (x, y, terrain_z). e_pos [P,N,E,2] -> [P,N,E,3]."""
        z = self._terrain_z(e_pos)
        return torch.cat([e_pos, z[..., None]], -1)

    def _nearest_obstacle(self, pos3, half, centers=None):
        """Nearest-obstacle signed clearance + outward gradient for query points pos3 [P,N,K,3] against the
        obstacle bundle. `centers` (default self.obst_xyz) is the LIVE centre [N,O,3] for DYNAMIC obstacles.
        Returns (clr [P,N,K], grad [P,N,K,3]). Loop-free."""
        P, N, K, _ = pos3.shape
        oc = self.obst_xyz if centers is None else centers                    # live centre (dynamic) or static default
        dvec = pos3[:, :, :, None, :] - oc[None, :, None, :, :]               # [P,N,K,O,3]
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

    def _nearest_obstacle_clr(self, pos3, half, centers=None):
        """Nearest-obstacle clearance ONLY (no gradient path change) — cheaper than _nearest_obstacle for the
        crash test. `centers` (default self.obst_xyz) = LIVE centre [N,O,3] for DYNAMIC obstacles. Loop-free."""
        P, N, K, _ = pos3.shape
        oc = self.obst_xyz if centers is None else centers
        dvec = pos3[:, :, :, None, :] - oc[None, :, None, :, :]               # [P,N,K,O,3]
        half_e = half[None, :, None, :, :].expand(P, N, K, self.O, 3)
        cyl_e = self.obst_cyl[None, :, None, :].expand(P, N, K, self.O)
        sdf = COL.shape_sdf3(dvec, half_e, cyl_e)                             # [P,N,K,O]
        return (sdf + (1.0 - self.obst_mask[None, :, None, :]) * 1e9).amin(-1)

    def _obstacle_rays(self, dp, centers=None):
        """Egocentric depth-ray fan for drones dp [P,N,D,3] -> normalized depths [P,N,D,K] in [0,1]. Casts
        DRONE_RAYS world-frame rays against every obstacle's BOUNDING BOX (raycast_aabb: box exact, cylinder
        as its bbox) and normalizes by ray_range. `centers` (default self.obst_xyz) = LIVE centre for DYNAMIC
        obstacles. The drone's raw-geometry obstacle sensor. Loop-free."""
        P, N, D, _ = dp.shape; O = self.O
        oc = self.obst_xyz if centers is None else centers
        d = self.ray_dirs.to(dp.dtype)[None, None, None].expand(P, N, D, self.DRONE_RAYS, 3)   # [P,N,D,K,3]
        c = oc[None, :, None].expand(P, N, D, O, 3)                                             # [P,N,D,O,3]
        h = self.obst_half[None, :, None].expand(P, N, D, O, 3)
        m = self.obst_mask[None, :, None].expand(P, N, D, O)                                    # [P,N,D,O]
        depth = COL.raycast_aabb(dp, d, c, h, m, self.ray_range, ray_chunk=48)                  # [P,N,D,K] (VRAM-bounded)
        # DETACH: this is a depth SENSOR (an input), not a differentiable dynamics quantity. Detaching keeps
        # the SHAC H-window graph from holding the big [P,N,D,K,O] raycast intermediates (OOM guard), and is
        # correct — obstacle AVOIDANCE is learned via the crash-penalty -> critic -> dynamics gradient path,
        # while the policy still learns to REACT to the rays through its own weights (their grad is unaffected).
        return (depth / self.ray_range).clamp(0.0, 1.0).detach()

    # ---- DYNAMIC NAVIGATION FIELD (GPU flow/eikonal pathfinding — the ray fan's replacement) ----
    def _build_navfield(self, obst_xyz, e_pos, e_alive, v_desc):
        """SUPERVISOR: the swarm's shared 3D pathfinding map AND the authority on ALLOWED states -- the drone only
        ever knows what this permits. Rebuilt each decision, sampled by all drones (cost ~ map size, not agents).
        Clip rule = a cell is FORBIDDEN if it is inside a SOLID: an obstacle (`occ<r`) OR below the terrain surface
        (`z<ground+r`) -- so flows never route into the earth -- EXCEPT the ground denial is LIFTED where the cell
        has line-of-sight to a live enemy (a valid strike position -> the dive corridor is defined by VISIBILITY,
        not a radius). `r` is a DYNA-PARAM = body radius + stopping distance at the env's current descent speed
        `v_desc` [P,N]: the floor breathes with speed, so a drone must SLOW to be allowed near the ground.
        `obst_xyz` [N,O,3]; `e_pos` [P,N,E,2]; `e_alive` [P,N,E]. Returns `dist [P,N,Gz,G,G]`, `flow [P,N,Gz,G,G,3]`
        (-grad dist, unit), `occ2 [N,G,G]` (obs patch), `allowed [P,N,Gz,G,G]` float (1=allowed, for the render).
        DETACHED sensor; the `nav_sweeps` min-relaxation + `nav_los_K` LOS samples are FIXED unrolls (no data loop)."""
        G = self.nav_G; Gz = self.nav_Gz; N = self.N; dev = obst_xyz.device; c = self.cfg
        cell = self.nav_xyz                                                   # [Gz,G,G,3] 3D world position of each cell
        P = e_pos.shape[0]
        rb = self.nav_r_body                                                  # robot body radius (base clip)
        # --- obstacle solids (inflated by the body radius) ---
        dxyz = cell[None, :, :, :, None, :] - obst_xyz[:, None, None, None, :, :]   # [N,Gz,G,G,O,3] cell -> obstacle centre
        sdf3 = COL.shape_sdf3(dxyz, self.obst_half[:, None, None, None], self.obst_cyl[:, None, None, None])  # [N,Gz,G,G,O]
        sdf3 = sdf3 + (1.0 - self.obst_mask[:, None, None, None]) * 1e9        # padded obstacles -> +inf
        occ3 = sdf3.amin(-1)                                                   # [N,Gz,G,G] nearest-obstacle signed dist
        occ2 = occ3.amin(1)                                                    # [N,G,G] footprint clearance (min over z) for obs patch
        obst_solid = occ3 < rb                                                # [N,Gz,G,G] inside/at an obstacle (always forbidden)
        # --- DYNA-r ground floor: forbid cells below the terrain surface + the stopping distance at CURRENT speed ---
        cell_z = cell[..., 2]                                                 # [Gz,G,G] absolute altitude of each cell
        r_dyn = rb + v_desc * v_desc / (2.0 * self.a_up)                      # [P,N] body + vertical stopping distance (dyna-r)
        ground_solid = cell_z[None, None] < (self.nav_ground[None, :, None] + r_dyn[:, :, None, None, None])   # [P,N,Gz,G,G]
        # --- enemy sources (ground cells) + their terrain altitude (also the LOS target height) ---
        ez = self._terrain_z(e_pos)                                          # [P,N,E] terrain z under each enemy
        ix = ((e_pos[..., 0] + self.extent) / (2.0 * self.extent) * (G - 1)).round().long().clamp(0, G - 1)   # [P,N,E]
        iy = ((e_pos[..., 1] + self.extent) / (2.0 * self.extent) * (G - 1)).round().long().clamp(0, G - 1)
        iz = ((ez - self.nav_zlo) / (self.nav_zhi - self.nav_zlo) * (Gz - 1)).round().long().clamp(0, Gz - 1)  # [P,N,E]
        flat = (iz * G * G + iy * G + ix)                                     # [P,N,E] flat cell index (z,y,x)
        src = torch.zeros(P, N, Gz * G * G, device=dev).scatter_add(-1, flat, e_alive).view(P, N, Gz, G, G) > 0.5
        # --- LINE-OF-SIGHT: a cell sees the NEAREST live enemy if the segment stays above terrain (K fixed samples) ---
        gxy = cell[0, :, :, :2]                                              # [G,G,2] grid xy (z-independent)
        d2 = ((gxy[None, None, :, :, None, :] - e_pos[:, :, None, None, :, :]) ** 2).sum(-1)   # [P,N,G,G,E]
        d2 = d2 + (1.0 - e_alive[:, :, None, None, :]) * 1e12                 # dead enemies -> never the nearest
        nidx = d2.argmin(-1)                                                 # [P,N,G,G] nearest LIVE enemy per column
        e_full = torch.cat([e_pos, ez[..., None]], -1)                       # [P,N,E,3] enemy world pos (z = terrain)
        ne = torch.gather(e_full, 2, nidx.reshape(P, N, G * G, 1).expand(P, N, G * G, 3)).reshape(P, N, G, G, 3)
        t = self.nav_los_t.view(1, 1, 1, 1, 1, self.nav_los_K, 1)            # [1,1,1,1,1,K,1] interior fractions
        p0 = cell[None, None, :, :, :, None, :]                              # [1,1,Gz,G,G,1,3] cell end
        p1 = ne[:, :, None, :, :, None, :]                                   # [P,N,1,G,G,1,3] enemy end (broadcast over z)
        pts = p0 * (1.0 - t) + p1 * t                                        # [P,N,Gz,G,G,K,3] sampled segment points
        terr = TERR.height(self.hf, pts[..., :2].reshape(P, N, -1, 2), self.extent).reshape(P, N, Gz, G, G, self.nav_los_K)
        los = (pts[..., 2] >= terr - rb).all(-1)                             # [P,N,Gz,G,G] all samples clear the ground
        # --- ALLOWED = not-a-solid; obstacles ALWAYS solid, ground denial LIFTED along LOS to an enemy ---
        blocked = obst_solid[None] | (ground_solid & (~los))                # [P,N,Gz,G,G] forbidden states
        allowed = ~blocked
        # --- TUBE CLEARANCE (cross-track signal): signed distance to the nearest tube WALL, corridor-aware. The ground
        #     is a wall ONLY where LOS does not lift it -> inside the strike corridor the tube extends to the target, so
        #     this does NOT fight the terminal dive. Sampled per-drone to keep the swarm CENTERED in the tube (the
        #     cross-track term of along-track x cross-track path following -- MDPI Sensors 24(2):561, doi 10.3390/s24020561). ---
        ground_sd = cell_z[None, None] - (self.nav_ground[None, :, None] + r_dyn[:, :, None, None, None])   # height above the floor
        ground_sd = torch.where(los, torch.full_like(ground_sd, 1e6), ground_sd)   # LOS corridor -> ground is not a wall here
        tube_clear = torch.minimum(ground_sd, occ3[None] - rb).clamp(min=0.0)      # [P,N,Gz,G,G] distance to the nearest wall
        # --- multi-source 3D geodesic distance over the ALLOWED space; the enemy source OVERRIDES the block ---
        fixed = blocked | src                                                # sources + solids never relax
        BIG = 1e6
        dist = torch.where(src, torch.zeros(P, N, Gz, G, G, device=dev),     # source -> 0 (overrides a below-ground enemy)
                           torch.full((P, N, Gz, G, G), BIG, device=dev))    # every other cell (solid or free) starts BIG
        step, zst = self.nav_cell, self.nav_zcell
        wxy = 1.0 / (step * step); wz = 1.0 / (zst * zst)                    # per-axis weights 1/h^2 (f=1 -> distance in metres)
        for _ in range(self.nav_sweeps):                                     # NAV-FIELD-UNROLL-OK: fixed 3D Eikonal relaxation
            dp = F.pad(dist, (1, 1, 1, 1, 1, 1), value=BIG)                  # pad x,y,z -> [P,N,Gz+2,G+2,G+2]
            zc, yc, xc = slice(1, Gz + 1), slice(1, G + 1), slice(1, G + 1)
            # --- GODUNOV upwind EIKONAL update: solve sum_i w_i*((d-U_i)_+)^2 = 1 from the smaller neighbour on each
            #     axis -> the TRUE Euclidean geodesic (kills the octile-metric ZIGZAG of a plain min-relaxation).
            #     Fast Iterative/Sweeping scheme (Jeong & Whitaker, arXiv:2106.15869; Zhao fast-sweeping). Branchless
            #     causal 3->2->1 cascade; the sort-of-3 is a min/max/where network (no python `if`, compile-safe). ---
            Ux = torch.minimum(dp[..., zc, yc, :G], dp[..., zc, yc, 2:])     # [P,N,Gz,G,G] upwind x neighbour
            Uy = torch.minimum(dp[..., zc, :G, xc], dp[..., zc, 2:, xc])     # upwind y neighbour
            Uz = torch.minimum(dp[..., :Gz, yc, xc], dp[..., 2:, yc, xc])    # upwind z neighbour
            u0, w0 = Ux, torch.full_like(Ux, wxy); u1, w1 = Uy, torch.full_like(Uy, wxy)   # sort the 3 (U,w) axes ascending by U
            m = u0 <= u1; u0, w0, u1, w1 = torch.where(m, u0, u1), torch.where(m, w0, w1), torch.where(m, u1, u0), torch.where(m, w1, w0)
            u2, w2 = Uz, torch.full_like(Uz, wz)
            m = u1 <= u2; u1, w1, u2, w2 = torch.where(m, u1, u2), torch.where(m, w1, w2), torch.where(m, u2, u1), torch.where(m, w2, w1)
            m = u0 <= u1; u0, w0, u1, w1 = torch.where(m, u0, u1), torch.where(m, w0, w1), torch.where(m, u1, u0), torch.where(m, w1, w0)
            d1 = u0 + 1.0 / torch.sqrt(w0)                                   # 1-axis solution (nearest upwind face)
            A2 = w0 + w1; B2 = -2.0 * (w0 * u0 + w1 * u1); C2 = w0 * u0 * u0 + w1 * u1 * u1 - 1.0
            d2 = (-B2 + torch.sqrt(torch.clamp(B2 * B2 - 4.0 * A2 * C2, min=0.0))) / (2.0 * A2)   # 2-axis (mandated safe-sqrt)
            A3 = A2 + w2; B3 = B2 - 2.0 * w2 * u2; C3 = C2 + w2 * u2 * u2     # fold in the 3rd axis
            d3 = (-B3 + torch.sqrt(torch.clamp(B3 * B3 - 4.0 * A3 * C3, min=0.0))) / (2.0 * A3)   # 3-axis (safe-sqrt)
            nb = torch.where(d1 <= u1, d1, torch.where(d2 <= u2, d2, d3))    # causal cascade: fewest upwind axes that stays consistent
            dist = torch.where(fixed, dist, torch.minimum(dist, nb))         # Jacobi Eikonal relax; sources/solids frozen
        # --- 3D flow = -grad dist (unit) toward the nearest reachable enemy (carries the vertical descent) ---
        # REPLICATE-pad for the gradient (one-sided difference at the ARENA edge) -- a BIG pad here would poison the
        # boundary gradient (esp. the ground plane where the enemy sits) and flip the flow to point straight up.
        # Interior walls keep their BIG in `dist` itself, so the flow still repels off real obstacles.
        dpad = F.pad(dist, (1, 1, 1, 1, 1, 1), mode="replicate")
        gx = (dpad[..., 1:Gz + 1, 1:G + 1, 2:] - dpad[..., 1:Gz + 1, 1:G + 1, :G]) / (2.0 * step)   # d/dx per METRE
        gy = (dpad[..., 1:Gz + 1, 2:, 1:G + 1] - dpad[..., 1:Gz + 1, :G, 1:G + 1]) / (2.0 * step)   # d/dy per METRE
        gz = (dpad[..., 2:, 1:G + 1, 1:G + 1] - dpad[..., :Gz, 1:G + 1, 1:G + 1]) / (2.0 * zst)     # d/dz per METRE (anisotropy fix)
        flow = torch.stack([-gx, -gy, -gz], -1)                              # [P,N,Gz,G,G,3]
        flow = flow / (flow.norm(dim=-1, keepdim=True) + 1e-6)              # unit 3D route direction
        flow = torch.where(blocked[..., None], torch.zeros_like(flow), flow) # no guidance inside a forbidden state
        dist = dist.clamp(max=2.0 * self.detection_range)                    # finite cap
        return dist.detach(), flow.detach(), occ2.detach(), allowed.float().detach(), tube_clear.detach()

    def _sample_nav3(self, dp, dist3, flow3):
        """Trilinear-sample the 3D nav-field at drone positions. `dp` [P,N,D,3]; `dist3` [P,N,Gz,G,G];
        `flow3` [P,N,Gz,G,G,3]. Returns `geo [P,N,D]` (geodesic dist) + `flow [P,N,D,3]` (unit 3D route dir)."""
        P, N, D, _ = dp.shape; G = self.nav_G; Gz = self.nav_Gz
        xn = (dp[..., 0] / self.extent).clamp(-1.0, 1.0)                      # [P,N,D] x -> [-1,1]
        yn = (dp[..., 1] / self.extent).clamp(-1.0, 1.0)                      # y -> [-1,1]
        zn = ((dp[..., 2] - self.nav_zlo) / (self.nav_zhi - self.nav_zlo) * 2.0 - 1.0).clamp(-1.0, 1.0)   # z -> [-1,1]
        grid = torch.stack([xn, yn, zn], -1).reshape(P * N, D, 1, 1, 3)       # [PN,D,1,1,3] (x,y,z)
        fld = torch.cat([dist3[..., None], flow3], -1).permute(0, 1, 5, 2, 3, 4).reshape(P * N, 4, Gz, G, G)   # [PN,4,Gz,G,G]
        s = F.grid_sample(fld, grid, mode="bilinear", align_corners=True).reshape(P, N, 4, D).permute(0, 1, 3, 2)   # [P,N,D,4]
        geo = s[..., 0]                                                       # [P,N,D] geodesic distance
        flow = s[..., 1:4]                                                    # [P,N,D,3] 3D route direction
        flow = flow / (flow.norm(dim=-1, keepdim=True) + 1e-6)              # re-unit after interpolation
        return geo, flow

    def _sample_navfield(self, dp, dist, flow, occ_sdf, ht):
        """3D route features per drone (DETACHED). Returns `nav_feat [P,N,D,13]` = flow3(3) + geodesic_closeness(1)
        + 3x3 footprint-clearance patch(9). The 3D flow includes the descent so the height feature is redundant."""
        P, N, D, _ = dp.shape; G = self.nav_G; dev = dp.device; c = self.cfg
        sc = self.scale.view(1, N, 1)                                        # [1,N,1] per-env length scale
        geo, fdir = self._sample_nav3(dp, dist, flow)                       # [P,N,D], [P,N,D,3] the 3D route
        geo_close = (1.0 - geo / self.detection_range).clamp(0.0, c.obs_clamp)[..., None]         # [P,N,D,1]
        # 3x3 local footprint-occupancy patch (min-over-z clearance) — a mini local obstacle sensor
        occ_b = occ_sdf[None].expand(P, N, G, G)
        off = self.nav_cell * torch.tensor([[-1, -1], [0, -1], [1, -1], [-1, 0], [0, 0], [1, 0],
                                            [-1, 1], [0, 1], [1, 1]], device=dev, dtype=torch.float32)   # [9,2]
        pxy = ((dp[..., None, :2] + off) / self.extent).clamp(-1.0, 1.0).reshape(P * N, D * 9, 1, 2)
        patch = F.grid_sample(occ_b.reshape(P * N, 1, G, G), pxy, mode="bilinear", align_corners=True)
        patch = (patch.reshape(P, N, D, 9) / sc[..., None]).clamp(-c.obs_clamp, c.obs_clamp)      # [P,N,D,9]
        return torch.cat([fdir, geo_close, patch], -1).detach()             # [P,N,D,13] = 3 + 1 + 9

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
        """-> (self_feat [P,N,D,DRONE_SELF_F=26], tok [P,N,D,K,DRONE_TOK_F=12], mask [P,N,D,K]). Obstacle sensing
        is the DYNAMIC NAV-FIELD (a per-env geodesic pathfinding map toward enemies, routing around live obstacles,
        sampled per drone as flow-dir + geodesic-closeness + height + a 3x3 clearance patch) — replaces the raycast
        fan. Each candidate token carries a LEARNABLE-targeting pair: teammate_demand + clear_shot — the policy's
        own attention picks + distributes targets."""
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
        # DYNAMIC NAV-FIELD sensor (REPLACES the ray fan): READ the SHARED geodesic map from the state (built once
        # every nav_refresh_every decisions by step_dec) and sample per-drone route features. The decision layer
        # treats the field as fixed at this instant — no rebuild here (the slow-planner/fast-controller split).
        nav_feat = self._sample_navfield(dp, state["nav_dist"], state["nav_flow"], state["nav_occ"], state["nav_allowed"])
        self_feat = torch.cat([
            bz,                                                              # body-z tilt (unit dir — passthrough)
            dv,                                                              # velocity RAW m/s   (LOT-normalized in policy)
            dw,                                                              # angular rate RAW rad/s (LOT)
            agl[..., None],                                                  # altitude RAW m     (LOT)
            (de / c.batt_capacity_j)[..., None],                            # energy FRACTION [0,1] (passthrough)
            tgrad,                                                           # terrain slope RAW  (LOT)
            nav_feat,                                                        # nav-field route features (passthrough)
        ], -1)                                                               # 3+3+3+1+1+2 + 13 = 26 = DRONE_SELF_F
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
        rvel = cand_vel[:, :, None, :, :] - dv[:, :, :, None, :]            # [P,N,D,S,3] RAW relative vel m/s (LOT)
        closing = -(rvel * rel_dir).sum(-1)                                 # >0 = approaching me
        ise = is_enemy[:, :, None, :].expand(P, N, D, S)
        etank = enemy_tank[:, :, None, :].expand(P, N, D, S)              # (isd dropped: it's just 1-ise)
        # (cand_demand teammate-coverage + cand_los clear-shot hints REMOVED: the GROUP layer's set-attention +
        #  learned assignment now do coordinated target selection directly, so these hand-coded token hints are
        #  redundant — and cand_los's [P,N,D,E,O,3] segment-clearance was the memory hog that OOM'd the wide batch.)
        feat = torch.cat([rel_dir, dist[..., None],                        # rel_dir unit (passthrough); dist RAW m (LOT)
                          rvel, closing[..., None],                         # rvel RAW m/s, closing RAW m/s (LOT)
                          ise[..., None], etank[..., None]], -1)            # 3+1+3+1+1+1 = 10 = DRONE_TOK_F
        valid = cand_alive[:, :, None, :].expand(P, N, D, S)               # exclude self via the static mask
        valid = valid * (1.0 - self._drone_self_mask[None, None])
        tok, mask = self._select_topk(feat, dist, valid, self.DRONE_K)
        # target selection is LEARNED by the GROUP layer: per-enemy SET features (shared across drones) + the alive
        # masks + each drone's arena-frame xy feed the policy's set-self-attention + bilinear assignment, which
        # returns a one-hot target per drone (routes the reward homing) -- no hand-coded Sinkhorn.
        enemy_feat = torch.cat([ep / c.arena_half,                            # [P,N,E,2] enemy arena-frame position
                                ev / c.tank_speed_max,                        # [P,N,E,2] enemy velocity
                                (torch.sqrt((ev * ev).sum(-1) + c.eps) / c.tank_speed_max)[..., None],   # [P,N,E,1] speed
                                self.e_type[None].expand(P, N, E)[..., None]], -1)   # [P,N,E,1] tank flag -> Fe=6
        dp_xy = dp[..., :2] / c.arena_half                                    # [P,N,D,2] drone arena-frame xy (affinity geometry)
        return self_feat, tok, mask, enemy_feat, e_alive, da, dp_xy

    def enemy_obs(self, state):
        """-> (self_feat [P,N,E,12], tok [P,N,E,K,9], mask [P,N,E,K])."""
        c = self.cfg; pic = sensors.perceive(state)
        ep, ev, eh, e_cd, e_alive = pic["e_pos"], pic["e_vel"], pic["e_head"], pic["e_cd"], pic["e_alive"]
        dp, dv, da = pic["d_pos"], pic["d_vel"], pic["d_alive"]
        P, N, E, _ = ep.shape; D = self.D; sc = self.scale.view(1, N, 1)
        ez, slope = TERR.height_and_grad(self.hf, ep, self.extent)           # fused: one corner-gather pass
        ep3 = torch.cat([ep, ez[..., None]], -1)                             # [P,N,E,3]
        speed = torch.sqrt((ev * ev).sum(-1) + c.eps)                        # [P,N,E]
        oclr, ograd = self._nearest_obstacle(ep3, self.obst_half2, centers=state["obst_xyz"])   # 2D footprint (LIVE pos)
        arena_pos = ep / c.arena_half
        self_feat = torch.cat([
            self.e_type[None, :, :, None].expand(P, N, E, 1),
            torch.stack([torch.cos(eh), torch.sin(eh)], -1),
            (speed / c.tank_speed_max).clamp(0, c.obs_clamp)[..., None],
            slope.clamp(-c.obs_clamp, c.obs_clamp),
            (e_cd / self.cd_ticks)[..., None],
            ograd[..., :2],
            (oclr / c.engage_range).clamp(-c.obs_clamp, c.obs_clamp)[..., None],   # obstacle CLEARANCE (how close)
            arena_pos.clamp(-c.obs_clamp, c.obs_clamp),
        ], -1)                                                               # 1+2+1+2+1+2+1+2 = 12 = ENEMY_SELF_F
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
    def _core(self, s, gust_t, aa_roll_t, due, a_drone, a_enemy, assign):
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
        d_vref = torch.where(just[..., None], torch.zeros_like(s["d_vref"]), s["d_vref"])   # reference-velocity filter resets on spawn
        d_omega = torch.where(just[..., None], torch.zeros_like(s["d_omega"]), s["d_omega"])
        d_energy = torch.where(just, torch.full_like(s["d_energy"], c.batt_capacity_j), s["d_energy"])
        d_act = torch.maximum(s["d_act"], just.float())
        d_alive = torch.maximum(s["d_alive"], just.float())
        active_d = (d_act > 0.5) & (d_alive > 0.5)                           # [P,N,D]
        af = active_d.float()                                                # cached (reused ~4x below)
        # ===== 1b. DYNAMIC obstacles: kinematic drift + edge-bounce, z inert. Pure broadcast (no loop/if). =====
        # Positions live in the state ([N,O,3], P-invariant); size/shape stay static attrs. Integrated FIRST so
        # every reader below (enemy avoid/push-out, drone crash, next obs) sees one consistent current-tick centre.
        bnd = self.obst_bound[..., None]                                     # [N,O,1] centre bounce bound
        oxy = s["obst_xyz"][..., :2] + s["obst_vel"][..., :2] * c.dt         # [N,O,2] proposed next xy
        over = oxy.abs() > bnd                                               # [N,O,2] crossed the wall this tick
        obst_vel = torch.cat([torch.where(over, -s["obst_vel"][..., :2], s["obst_vel"][..., :2]),
                              torch.zeros_like(s["obst_vel"][..., 2:3])], -1) * self.obst_mask[..., None]  # bounce, vz=0
        obst_xyz = torch.cat([oxy.clamp(-bnd, bnd), s["obst_xyz"][..., 2:3]], -1) * self.obst_mask[..., None]  # z carried

        # ===== 2. wind at drones =====
        agl = d_pos[..., 2] - self._terrain_z(d_pos[..., :2])                # [P,N,D]
        wind = WIND.wind_at(gust_t, self.mean_wind, agl, c.wind_z0, c.wind_z_ref)   # [P,N,D,3]

        # ===== 3. drone dynamics -- DIFFERENTIABLE VELOCITY-TRACKING BASE CONTROLLER (algorithmic flight) + AI VELOCITY
        #        OVERRIDE (the residual). The nav flow field is the route; the AI (a_drone) only STEERS (Delta v) and sets
        #        urgency -- it never touches thrust/rates. Vector-field guidance -> velocity control (AIAA 2021,
        #        doi 10.2514/6.2021-0782); residual RL (Johannink et al. arXiv:1812.03201; diff-sim residual Luo et al.
        #        arXiv:2410.03076). Runs per physics tick (50 Hz) on FRESH kinematics + flow, so the 10 Hz zero-order-held
        #        action still flies smooth; a state-carried low-pass on the reference is the anti-shake guardrail. =====
        gn = self.ctrl_gains                                                # base-controller gains (learnable leaves in training)
        v_cruise = F.softplus(gn["v_cruise"]); tau = F.softplus(gn["tau"]); t_look = F.softplus(gn["t_look"])
        k_v = F.softplus(gn["k_v"]); k_R = F.softplus(gn["k_R"]); v_ovr = F.softplus(gn["v_override"]); urg_g = F.softplus(gn["urgency_gain"])
        _, flow3 = self._sample_nav3(d_pos + d_vel * t_look, s["nav_dist"], s["nav_flow"])   # route dir at a LOOKAHEAD (0 outside tube -> hover)
        urg = 1.0 + urg_g * torch.tanh(a_drone[..., 3])                     # [P,N,D] AI urgency knob (route speed scale)
        v_ref = flow3 * (v_cruise * urg)[..., None] + v_ovr * torch.tanh(a_drone[..., 0:3])   # route velocity + AI VELOCITY OVERRIDE (steer)
        d_vref = d_vref + (v_ref - d_vref) * (c.dt / tau)                   # LOW-PASS reference filter (state-carried anti-shake guardrail)
        a_des = k_v * (d_vref - d_vel)                                      # [P,N,D,3] commanded acceleration
        f_des = c.drone_mass * a_des                                        # desired thrust vector (world)
        f_des = torch.cat([f_des[..., :2], f_des[..., 2:3] + c.drone_mass * c.gravity], -1)   # + gravity compensation on z
        bodyz = ROT.body_z_axis(d_quat)                                     # [P,N,D,3] current thrust axis (world)
        thrust = (f_des * bodyz).sum(-1).clamp(0.0, c.drone_t_max)          # collective thrust = f_des projected on body-z
        thrust = thrust * (d_energy > 0).float()                            # dead battery -> no thrust (falls)
        bodyz_des = f_des / (f_des.norm(dim=-1, keepdim=True) + 1e-6)       # desired thrust direction (unit)
        err_w = ROT.shortest_arc(bodyz, bodyz_des)                          # WORLD-frame attitude-error rotation vector
        err_b = ROT.quat_rotate(ROT.quat_conjugate(d_quat), err_w)         # -> BODY frame (quad_step integrates BODY rates)
        omega_cmd = (k_R * err_b).clamp(-c.drone_omega_max, c.drone_omega_max)   # body-rate command
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
        oclr, ograd = self._nearest_obstacle(ep3_foot, self.obst_half2, centers=obst_xyz)   # footprint (LIVE pos)
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
        # HARD obstacle push-out (BOTH types): project the enemy out of any obstacle FOOTPRINT so it can't
        # phase through a building. Tanks have no soft avoidance, so without this they drive straight through;
        # the shove makes buildings solid to ground units -> the policy must route AROUND (using its obstacle
        # obs). penetration = max(0, r - clearance) pushed along the outward SDF gradient. Loop-free.
        e_foot = torch.cat([e_pos, torch.zeros_like(e_pos[..., :1])], -1)     # z-independent footprint query
        pclr, pgrad = self._nearest_obstacle(e_foot, self.obst_half2, centers=obst_xyz)   # [P,N,E] (LIVE pos)
        e_rad = torch.where(is_tank.expand(P, N, E),                          # tank body vs soldier body radius
                            torch.full_like(pclr, c.tank_radius),
                            torch.full_like(pclr, c.soldier_radius))
        push = torch.clamp(e_rad - pclr, min=0.0)                            # penetration depth (0 outside)
        e_pos = e_pos + push[..., None] * pgrad[..., :2]                     # shove outward in xy
        e_pos = torch.where(e_alive[..., None] > 0.5, e_pos, ep)            # dead enemies stay put
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
        o_clr = self._nearest_obstacle_clr(d_pos, self.obst_half, centers=obst_xyz)   # LIVE obstacle pos (dynamic)
        # A drone clipping TERRAIN while horizontally OVER an alive enemy is a committed DIVE, not a botched
        # flight -> terrain grace (non-fatal) so the swarm can PRACTICE diving without dying every attempt.
        # But there is NO IMMUNITY ON SEEK for OBSTACLES: buildings/trees stay SOLID even mid-dive, so a
        # committed drone still crashes if it clips one -> it must LEARN to weave (the APF-repel reward gives
        # the gradient). Kamikaze contact with an enemy overrides everything (a detonation, not a crash).
        committed = d_near_xy < self.stop_dist                           # within physical horizontal stopping distance of an enemy
        terr_hit = agl2 < c.drone_radius                                  # clipped the ground
        obst_hit = o_clr < c.drone_radius                                 # clipped a building/tree (solid mid-seek)
        crash = ((terr_hit & (~committed)) | obst_hit) & active_d & (~drone_kama)
        # The terrain grace must not let a graced drone SINK THROUGH the ground and get stuck underground
        # (diagnosed: median AGL -15 m). Clamp a committed drone that dipped below the surface back UP to the
        # ground (skim it) and kill its downward velocity — a physical dive-to-surface, not a bug hole.
        below = terr_hit & active_d & committed & (~drone_kama)
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
        # HOMING = PROPORTIONAL NAVIGATION via ZERO-EFFORT-MISS (ZEM), the quantity real guidance laws null.
        # (An earlier version used raw 3D distance; distance-to-a-ground-target shaping greedily rewards diving
        # straight down and the swarm plowed into the terrain SHORT of the enemy -- the exact local-optimum the
        # guidance/RL literature warns distance shaping falls into. ZEM is velocity-aware: a drone diving short is
        # NOT on an intercept course -> big miss -> penalized; only a real collision course drives ZEM->0.)
        n_alive = af.sum(-1) + c.eps                                       # [P,N]     alive-drone count (safe denominator)
        # ---- REACH: dense, differentiable HORIZONTAL closing to each drone's ASSIGNED enemy (the group brain's one-hot
        #      `assign` [P,N,D,E]). This is the ONLY homing term now -- the ROUTE is algorithmic (the base controller flies
        #      the nav flow); the reward just says "get to YOUR target, don't die". Potential-based (telescopes over the
        #      episode -> un-farmable by loitering/circling) and HORIZONTAL so it never rewards diving into terrain short
        #      of the target. Differentiable in d_pos (the target enemy position is a DETACHED reference). ----
        tgt     = (assign[..., None] * ep3[:, :, None, :, :]).sum(3).detach()               # [P,N,D,3] assigned-enemy position (target)
        d_now   = (d_pos[..., :2] - tgt[..., :2]).norm(dim=-1)                              # [P,N,D] post-move horizontal range to target
        d_prev  = (s["d_pos"][..., :2] - tgt[..., :2]).norm(dim=-1)                         # [P,N,D] pre-move range (same target)
        r_reach = (torch.where(just, torch.zeros_like(af), d_prev - d_now) * af).sum(-1) / (n_alive * c.drone_speed_max * c.dt)   # [P,N] closing rate
        # ---- Phi_safe = -(1/T_ep) * mean_drones (ground-deficit + obstacle-deficit) seconds. Each term = relu(t_stop -
        #      ttc): the seconds by which a stop CANNOT be completed before impact. ZERO whenever the impact is
        #      physically arrestable -> 0 in normal flight; supplies the differentiable ground/obstacle-avoidance
        #      gradient (replaces the old brake+apf penalties). Every scale is an actuator limit (a_up, a_lat) -- no tuning. ----
        down    = torch.relu(-d_vel[..., 2])                              # [P,N,D]  downward speed (0 if climbing/level)
        gdef    = torch.relu(down / self.a_up - torch.relu(agl2) / (down + c.eps))     # [P,N,D] GROUND stopping deficit [s]
        _, o_grad2 = self._nearest_obstacle(d_pos, self.obst_half2, centers=obst_xyz)  # [P,N,D,.] outward gradient (points away from obstacle)
        v_into  = torch.relu(-(d_vel[..., :2] * o_grad2[..., :2]).sum(-1))# [P,N,D]  horizontal speed INTO the nearest obstacle
        odef    = torch.relu(v_into / self.a_lat - o_clr / (v_into + c.eps))           # [P,N,D] OBSTACLE stopping deficit [s]
        phi_s   = -((gdef + odef) * af).sum(-1) / (n_alive * self.T_ep)   # [P,N]    -mean over alive drones, normalized
        phi_new = phi_s                                                   # [P,N]    Phi(s') = the safety potential only (homing is now the flow rate)
        r_shape = phi_new - s["phi_prev"]                                 # [P,N]    safety potential delta (telescopes -> un-farmable)
        # ---- REWARD F = +kill (objective) - wasted drone (tradeoff) + r_reach (dense closing to the ASSIGNED enemy)
        #      + r_shape (differentiable safety). The route/flight is handled by the base controller, so the reward is
        #      just the OBJECTIVE + a reach gradient + don't-crash -- the AI (residual) learns tactics on top. ----
        r_drone = kills_now - died_wo_kill + r_reach + r_shape             # [P,N]    F : objective + reach + safety
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
                  d_act=d_act, d_alive=d_alive, d_energy=d_energy, phi_prev=phi_new,
                  d_vref=d_vref,                                      # base-controller reference-velocity filter state (carried)
                  d_crash=torch.maximum(s["d_crash"], crash.float()),  # sticky terrain/obstacle-crash flag (render)
                  e_pos=e_pos, e_head=e_head, e_vel=e_vel, e_alive=e_alive, e_cd=e_cd,
                  kills=kills, losses=losses,
                  obst_xyz=obst_xyz, obst_vel=obst_vel,               # DYNAMIC obstacles: carry the moved centre + vel
                  nav_dist=s["nav_dist"], nav_flow=s["nav_flow"],     # SHARED geodesic nav-field (carried across ticks;
                  nav_occ=s["nav_occ"], nav_allowed=s["nav_allowed"], nav_tube=s["nav_tube"])   # SUPERVISOR field carried
        done_d = drone_died.float()
        done_e = (enemy_hit & was_e_alive).float()
        panel = None
        if self.decompose:                                        # contribution of each drone-reward term (all weight 1)
            panel = {"r_kill": kills_now.sum(), "r_waste": (-died_wo_kill).sum(),
                     "r_shape": r_shape.sum(), "r_reach": r_reach.sum(), "phi_safe": phi_s.sum(),
                     "kills": kills_now.sum(), "ticks": torch.ones((), device=dev)}
        return ns, r_drone, r_enemy, done_d, done_e, panel

    # ---- one decision = act_every physics ticks (held actions) ----
    def step_dec(self, s, k, a_drone, a_enemy, assign=None, record=None, record_stride=2):
        """Advance one policy decision: act_every compiled ticks with zero-order-hold actions. `assign` [P,N,D,E]
        is the GROUP policy's per-drone target (one-hot); None -> uniform-over-alive-enemies fallback (tests).
        Returns (ns, r_drone[P,N], r_enemy[P,N], done_d[P,N,D], done_e[P,N,E]) summed over the ticks."""
        c = self.cfg
        P = s["d_pos"].shape[0]
        if assign is None:                                              # uniform over ALIVE enemies (test / feedforward fallback)
            ea = s["e_alive"]                                          # [P,N,E]
            assign = ea[:, :, None, :].expand(-1, -1, self.D, -1)
            assign = assign / assign.sum(-1, keepdim=True).clamp_min(1e-8)
        rp = torch.zeros(P, self.N, device=self.device)
        re = torch.zeros(P, self.N, device=self.device)
        dd = torch.zeros(P, self.N, self.D, device=self.device)
        de = torch.zeros(P, self.N, self.E, device=self.device)
        t0 = k * c.act_every
        # DYNAMIC SUPERVISOR: rebuild the nav-field each decision from the pre-decision obstacle+enemy+SPEED state, so
        # the dyna-r ground floor breathes with the swarm's current descent speed and the flow tracks moving enemies.
        # `v_desc` = per-env max descent speed among ALIVE drones -> the supervisor's stopping-distance clearance.
        if self.cfg.nav_refresh_every and k % self.cfg.nav_refresh_every == 0:   # data-independent gate (config + decision idx)
            v_desc = (torch.relu(-s["d_vel"][..., 2]) * s["d_alive"]).amax(-1)   # [P,N] current descent-speed state (dyna-r input)
            nd, nfl, no, na, ntb = self._build_navfield(s["obst_xyz"], s["e_pos"], s["e_alive"], v_desc)
            s = {**s, "nav_dist": nd, "nav_flow": nfl, "nav_occ": no, "nav_allowed": na, "nav_tube": ntb}
        # else: reuse the SHARED field already carried in s (the fast controller reads it as fixed at this instant)
        for j in range(c.act_every):                                        # TIME-LOOP-OK
            t = min(t0 + j, self.T - 1)
            gust_t = self.gust[:, t, :]                                      # [N,3]
            aa_roll_t = self.aa_roll[:, t, :]                               # [N,E]
            due = (self.spawn_tick <= float(t))[None].expand(P, self.N, self.D)   # [P,N,D]
            s, r_d, r_e, done_d, done_e, _ = self._core(s, gust_t, aa_roll_t, due.float(), a_drone, a_enemy, assign)
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
                    obst_xyz=g(s["obst_xyz"]),                                # DYNAMIC obstacle centres (per frame)
                    nav_allowed=g(s["nav_allowed"]), nav_flow=g(s["nav_flow"]), nav_dist=g(s["nav_dist"]),   # SUPERVISOR field (render dots)
                    nav_xyz=g(self.nav_xyz), nav_cell=float(self.nav_cell),   # static grid geometry (cell centres + pitch) for the overlay
                    kills=g(s["kills"]), losses=g(s["losses"]))
