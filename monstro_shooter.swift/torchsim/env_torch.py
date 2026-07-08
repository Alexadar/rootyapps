"""Torch BatchWorld — the vectorized game env. Two networked agents: the player (move+aim, the
training adversary / future companion seed) and the SHARED enemy net that drives every monster's
velocity (the deployed NPC). ALL global physics constants come from a single WorldConfig (the shared
"model+world setup") so torchsim and the Metal game cannot drift; per-type monster / weapon / exo
stats come from the YAML configs.

State carries a leading [P, N] dim:  P = ES population (2*pop, mirrored),  N = envs.
"""
import math
import numpy as np
import torch
from world_config import WorldConfig


def det_rand(t, k):
    """Deterministic pseudo-random in [-1,1] from integer (tick, pellet) — identical in Swift, so
    bullet spread stays parity-exact across the two engines (no real RNG)."""
    h = (t * 2654435761 + k * 2246822519 + 12345) & 0xffffffff   # k multiplier must be LARGE or pellets don't spread
    return h / 2147483647.5 - 1.0


class EnvTorch:
    player_obs = 8         # hp, count, threatXY, nearest, mean, wallX, wallY
    player_act = 5         # move2 + aim2 + fire1 (learned trigger; mirrors the game's click-to-fire, not auto-fire).
    #   NOTE: a per-type obs (8+4·6=32, "recognize monster type") was tried + reverted —
    #   it hurt ES (49% vs ~92% clear): 4.5x more params slows ES black-box search, and the obs is slower.
    #   Revisit only with a gradient method (PPO scales with params); keep the aggregate 8-dim obs for ES.
    enemy_obs = 31         # base19 + 8 weapon params + 2 player ammo/reload + 2 rock-flow (monsters route around rocks)
    #   + playerClosingVelXY, bulletVelXY (dynamics), + meanHeadXY, nearestNbrDirXY, nearestNbrDist (swarm)
    enemy_act = 2
    WFEAT = 8              # weapon features (both sides): dmg, rate, pellets, pen, range, spread, mag-capacity, reload-duration
    player_set_fs = 20     # self feats: hp, count, wallXY, velXY, aimXY + 8 weapon params + ammo/mag, reload + rock-flowXY
    player_set_fm = 13     # per-monster feats (see player_set_obs) + in-range ratio + clear_shot (line-of-fire)

    def __init__(self, sched, weapon, exo, device="cpu", bullets=32, cfg=None):
        self.device = device
        self.cfg = cfg or WorldConfig()
        c = self.cfg
        self.N = int(sched["spawn_tick"].shape[0])
        self.M = int(sched["M"])
        self.B = int(bullets)
        t = lambda a: torch.tensor(np.asarray(a, np.float32), device=device)
        self.spawn_tick = t(sched["spawn_tick"])      # [N,M]
        self.offset = t(sched["offset"])              # [N,M,2]
        self.mon_speed = t(sched["speed"])            # [N,M]
        self.mon_boxW = t(sched["boxW"])
        self.mon_mass = t(sched["mass"]) if "mass" in sched else torch.ones_like(self.mon_boxW)  # [N,M] body mass
        self.mon_dmg = t(sched["dmg"])
        self.mon_direct = t(sched["direct"])
        self.hp0 = t(sched["hp0"])                    # [N,M]
        ah = sched.get("arena_half")
        self.map_half = t(ah) if ah is not None else torch.full((self.N,), c.map_half, device=device)  # [N]
        rk = sched.get("rocks")                                              # static obstacles [N,K,3|4]
        self.rocks = t(rk) if rk is not None else torch.zeros((self.N, 1, 4), device=device)
        if self.rocks.shape[-1] == 3:                                        # legacy circles-only -> shape col 0
            self.rocks = torch.cat([self.rocks, torch.zeros_like(self.rocks[..., :1])], -1)
        self.rock_xy = self.rocks[..., :2].contiguous()                      # [N,K,2]
        self.rock_r = self.rocks[..., 2].contiguous()                       # [N,K] radius / square half-extent
        self.rock_sq = (self.rocks[..., 3] > 0.5).float().contiguous()      # [N,K] 1 = axis-aligned square
        self.rock_m = (self.rock_r > 0).float()                            # [N,K] valid-rock mask (padded r=0 -> 0)
        self._has_sq = bool(((self.rock_sq * self.rock_m).sum() > 0).item())  # py-const -> compile skips square math
        #   on all-circle batches (fast path); square batches pay the generic branch. Set before torch.compile.
        self._build_flow()                                                   # -> self.flow [N,G,G,2] clearance hint
        self.contact_interval = max(1, round(c.damage_interval / c.dt))
        self.defense = float(exo.get("defence", 0.0))
        self.exo_speed = float(exo.get("speed", 1.0))
        self._pc_cache = {}       # (weapon-sig, ticks) -> precompute tables; reused across weapon cycling
        self.set_weapon(weapon)   # bullet_*, fire_interval, bullets_per_shot, penetration, max_dev, mag/reload, wfeat
        # player reward shaping (TRAINING ONLY — rewards are NOT in the Swift parity contract). Defaults
        # reproduce the original r_player exactly (checksum-neutral); train_torch may reweight via --rw-*.
        self.rw_survive = 0.01   # per-tick alive baseline
        self.rw_kill = 1.0       # reward per kill
        self.rw_aim = 0.005      # reward for aiming AT the threat centroid (raise -> aim tracks the pack instead
        #   of staying fixed). NOTE: obs gives only ONE aggregate threat dir, so aim can track the centroid but
        #   NOT individual monsters — for true per-target aiming you need richer obs + PPO. 0.005 = original.
        self.rw_damage = 0.0     # dense per-tick reward per HP of damage DEALT (0 = off, checksum-neutral)
        self.rw_hit = 0.05       # penalty per HP of damage TAKEN. raise it to make the player damage-AVERSE
        #   (minimize damage -> dodge/move instead of tanking). 0.05 = original (checksum-neutral default).
        self.rw_space = 0.0      # per-tick reward for keeping monsters at distance — but allow up to space_keep
        #   close (you can't keep ALL away when surrounded). Signal = distance to the (space_keep+1)-th nearest
        #   monster, SATURATING at space_target (so it rewards spacing/dodging, NOT fleeing). 0 = off (parity).
        self.space_keep = 2      # how many monsters you're allowed to have close (reward keeps the (k+1)-th+ away)
        self.space_target = 200.0  # distance (world units) at which the spacing reward saturates
        # KEEP-OUT RING — penalize any monster inside a personal-space circle of ring_radius (post-move geometry).
        # Pure-neural anticipation: the reward only sees CURRENT incursion, but PPO's discounted return forces the
        # net (which sees each monster's pos+dir+velocity in its attention slot) to learn its own predictor and
        # vacate the spot BEFORE a monster arrives. Penalty = Σ over alive monsters of soft incursion depth
        # (0 outside, →1 at body). ring_radius≈90 sits just outside the ~60u damage line (2 monster bodies).
        # 0 = off (parity-safe; reward-only, never touches sim). Relieving breaches needs travel -> induces speed.
        self.rw_ring = 0.0
        self.ring_radius = 90.0
        # ECONOMICAL ACTIONS — one principle: actions cost energy, so do them only when worthwhile. Both off by
        # default (parity-neutral). Keep SMALL vs the kill/ring rewards or the player under-acts (timidity).
        self.rw_effort = 0.0     # per-tick cost ∝ |move| -> stillness emerges when safe, smoother dodging in combat
        self.rw_shot = 0.0       # per-tick cost when the gun fires -> trigger discipline (pair with a small rw_damage
        #   so a landing shot out-pays the cost; "fire only when it'll connect" is then learnable, no target check)
        # SWARM (enemy-side, shared/group reward via ES aggregate fitness). Both off by default.
        self.rw_align = 0.0      # reward coherent pack movement (each monster's heading vs the swarm mean heading)
        self.rw_separate = 0.0   # penalty when monsters breach each other's SMALL personal circle (anti-stacking)
        self.sep_radius = 50.0   # monster separation circle ≈ one body (vs the player's 90u keep-out ring)
        # enemy core reward weights (were hardcoded). Defaults reproduce the original r_enemy (checksum-neutral).
        # rw_e_approach is the DENSE per-tick closing gradient — the enemy's "easy" signal; lower it to stop the
        # enemy outpacing the (sparse-reward) player in co-evolution. rw_e_deaths near-0 = flock charges in.
        self.rw_e_dmg = 0.1      # reward per HP dealt to the player
        self.rw_e_approach = 0.0008  # dense per-tick reward ∝ closing distance (summed over alive monsters)
        self.rw_e_deaths = 0.02  # penalty per monster killed
        self.player_obs_fn = self.player_obs_vec   # MLP/ES default; train sets to player_set_obs for attention
        self.decompose = False     # eval-only: accumulate per-reward-term RAW sums into self._panel (analysis)
        self._panel = None

    # ---- OBSTACLE SHAPE BASE ----------------------------------------------------------------------------
    # The generic shape math (SDF + gradient + segment margin) is the BASE, written as pure tensor functions
    # over (dvec, size, is_square). An obstacle KIND (today: rocks; future: walls, crates, ...) is just a
    # tensor bundle (xy, size, shape-flag, mask) BOUND to this base — new kinds reuse the same math verbatim.
    def _shape_sdf(self, dvec, rr, sq):
        """SDF only (no gradient — cheaper than _shape_sdf_grad) at points dvec = p - center. dvec [...,K,2],
        rr/sq [...,K] -> [...,K]. Circle: |dvec|-rr. Square: standard AABB SDF. torch.where by shape."""
        eps = self.cfg.eps
        sdf_c = torch.sqrt((dvec * dvec).sum(-1) + eps) - rr
        if not self._has_sq:                                                # all-circle batch -> skip square math
            return sdf_c
        q = dvec.abs() - rr[..., None]
        sdf_s = torch.clamp(q, min=0.0).pow(2).sum(-1).add(eps).sqrt() + torch.clamp(q.amax(-1), max=0.0)
        return torch.where(sq > 0.5, sdf_s, sdf_c)

    def _shape_sdf_grad(self, dvec, rr, sq):
        """Signed distance + outward unit gradient at points dvec = p - shape_center.
        dvec [...,K,2], rr/sq [...,K] -> (sdf [...,K], grad [...,K,2]). Shape per entry: circle (radius rr) or
        axis-aligned square (half-extent rr), selected by sq via torch.where — ONE code path for physics
        de-overlap, the flow field, and the line-of-fire margin. Pure vector ops, no loops."""
        eps = self.cfg.eps
        L = torch.sqrt((dvec * dvec).sum(-1) + eps)                          # [...,K]
        sdf_c = L - rr                                                       # circle SDF
        grad_c = dvec / L[..., None]
        if not self._has_sq:                                                # all-circle batch -> skip square math
            return sdf_c, grad_c
        a = dvec.abs(); q = a - rr[..., None]                                # [...,K,2] per-axis face distance
        qp = torch.clamp(q, min=0.0)
        Lout = torch.sqrt((qp * qp).sum(-1) + eps)
        inside = q.amax(-1) < 0.0                                            # [...,K] fully inside the box
        sdf_s = torch.where(inside, q.amax(-1), Lout)                        # standard AABB SDF
        sgn = torch.where(dvec >= 0, torch.ones_like(dvec), -torch.ones_like(dvec))
        grad_out = (qp * sgn) / Lout[..., None]
        ax_x = (q[..., 0] >= q[..., 1]).float()[..., None]                   # inside: push out the CLOSEST face
        grad_in = torch.cat([sgn[..., :1] * ax_x, sgn[..., 1:] * (1.0 - ax_x)], -1)
        grad_s = torch.where(inside[..., None], grad_in, grad_out)
        return (torch.where(sq > 0.5, sdf_s, sdf_c),
                torch.where(sq[..., None] > 0.5, grad_s, grad_c))

    def _build_flow(self):
        """Precompute a per-env clearance flow field self.flow [N,G,G,2]: at each grid cell, a unit vector pointing
        AWAY from the nearest rock surface, scaled by proximity (0 in open space, 1 at the surface, fading over
        flow_influence). Rocks are static so this is computed ONCE. Fully vectorized — broadcast min over the rock
        axis, no python loop. Sampled O(1) per agent in the obs via _sample_flow."""
        c = self.cfg; dev = self.device; N, G = self.N, int(c.flow_grid)
        self._flow_g = G
        ah = self.map_half.view(N, 1, 1)                                     # [N,1,1] grid spans +/- arena_half/env
        axis = torch.linspace(-1.0, 1.0, G, device=dev)                      # [G] normalized cell centers
        gx = (axis.view(1, 1, G) * ah).expand(N, G, G)                       # x varies along the last (col) axis
        gy = (axis.view(1, G, 1) * ah).expand(N, G, G)                       # y varies along the middle (row) axis
        cells = torch.stack([gx, gy], -1)                                    # [N,G,G,2] (row=y, col=x)
        d = cells[:, :, :, None, :] - self.rock_xy[:, None, None, :, :]      # [N,G,G,K,2] cell - rock center
        clr, grad = self._shape_sdf_grad(d, self.rock_r[:, None, None, :], self.rock_sq[:, None, None, :])
        big = clr + (1.0 - self.rock_m[:, None, None, :]) * 1e9             # mask padded rocks (r=0) to +inf
        nidx = big.argmin(-1, keepdim=True)                                 # [N,G,G,1] nearest real rock
        near_clr = torch.gather(clr, 3, nidx).squeeze(-1)                   # [N,G,G] nearest clearance
        away = torch.gather(grad, 3, nidx[..., None].expand(N, G, G, 1, 2)).squeeze(3)  # SDF grad = away-dir
        weight = torch.clamp(1.0 - near_clr / c.flow_influence, min=0.0)    # [N,G,G] fades with clearance
        has_rock = (self.rock_m.sum(-1) > 0).float().view(N, 1, 1)          # rock-free envs -> zero flow
        self.flow = (away * (weight * has_rock)[..., None]).contiguous()    # [N,G,G,2]
        self._flow_flat = self.flow.view(N, G * G, 2)                       # [N,G*G,2] for O(1) gather

    def _sample_flow(self, pos):
        """Sample self.flow at world positions pos [P,N,X,2] -> flow vectors [P,N,X,2]. Per-env grid; loop-free
        batched gather (quantize world pos -> grid cell -> linear index -> gather)."""
        G = self._flow_g; P, N, X, _ = pos.shape
        ah = self.map_half.view(1, N, 1, 1)                                  # [1,N,1,1]
        norm = (pos / (ah + self.cfg.eps)).clamp(-1.0, 1.0)                  # -> [-1,1]
        idx = (((norm + 1.0) * 0.5) * (G - 1)).round().long().clamp(0, G - 1)   # [P,N,X,2] (col=x, row=y)
        lin = idx[..., 1] * G + idx[..., 0]                                  # [P,N,X] row*G + col
        flat = self._flow_flat[None].expand(P, N, G * G, 2)                  # [P,N,G*G,2]
        return torch.gather(flat, 2, lin[..., None].expand(P, N, X, 2))      # [P,N,X,2]

    def _shape_margin(self, p0, d, xy, rr, sq, mask):
        """GENERIC min signed clearance of the SEGMENT p0 -> p0+d past a bundle of shapes, inflated by
        bullet_radius. <0 = the segment enters a shape. p0,d [P,N,X,2]; xy [1,N,K,2]; rr/sq/mask [1,N,K] ->
        [P,N,X]. Lean single-point form: clearance = shape-SDF at the segment point closest to the shape CENTER,
        minus bullet_radius. Exact for circles; for squares this is exact on faces and slightly optimistic only
        for a shot grazing a corner far from the center-closest param (acceptable at 6u bullet / obs-hint scale).
        No slab, no gradient. Pure vector ops (broadcast over K; no python loop)."""
        c = self.cfg
        f = xy[:, :, None, :, :] - p0[..., None, :]                            # [P,N,X,K,2] p0 -> shape center
        t = ((f * d[..., None, :]).sum(-1) /
             ((d * d).sum(-1)[..., None] + c.eps)).clamp(0.0, 1.0)             # [P,N,X,K] closest approach on segment
        q = t[..., None] * d[..., None, :] - f                                 # shape center -> closest segment point
        marg = self._shape_sdf(q, rr[:, :, None, :], sq[:, :, None, :]) - c.bullet_radius
        return (marg + (1.0 - mask[:, :, None, :]) * 1e9).min(-1).values       # padded entries -> +inf

    def _rock_margin(self, p0, d):
        """Rocks bound to the generic shape margin. THE single line-of-fire rule: the in-flight bullet kill and
        the clear_shot obs both derive from this one function, so the obs can never lie about the sim."""
        return self._shape_margin(p0, d, self.rock_xy[None], self.rock_r[None],
                                  self.rock_sq[None], self.rock_m[None])

    PANEL_KEYS = ("p_kill", "p_aim", "p_damage", "p_hit", "p_space", "p_ring", "p_effort", "p_shot", "p_alive",
                  "e_dmg", "e_approach", "e_deaths", "e_align", "e_separate", "ticks")

    def reset_panel(self):
        """Zero the reward-decomposition accumulators. Call before a decompose=True eval rollout."""
        self._panel = {k: torch.zeros((), device=self.device) for k in self.PANEL_KEYS}

    def read_panel(self):
        """Return the accumulated per-term RAW sums as python floats (call after the eval rollout)."""
        return {k: float(v) for k, v in self._panel.items()} if self._panel else {}

    def set_weapon(self, weapon, range_scale=1.0):
        """Swap the active weapon: set its scalars, compute the normalized weapon feature vector (fed to BOTH
        player and enemy obs so both condition on the weapon), and invalidate the precompute tables (fire gate /
        spread / ring-slots depend on shotDelay/maxDeviation/bulletsPerShot). Per-iteration weapon randomization
        calls this each iter -> one policy generalizes across weapons at ~1x training cost.
        range_scale (training-only) shrinks bullet_range so spawn-distance can exceed range -> the player must
        learn to HOLD FIRE / close in (range discipline) in the cheap small maps. It's reflected in wfeat so the
        player perceives the scaled range, and stored as a 0-d tensor (_brange_t) read in the compiled _core so
        per-iter value changes do NOT trigger torch.compile recompiles."""
        c = self.cfg
        self.bullet_speed = float(weapon.get("bulletSpeed", 800))
        self.bullet_damage = float(weapon["damage"])
        self.bullet_range = float(weapon["shotRange"]) * range_scale
        self._brange_t = torch.tensor(self.bullet_range, dtype=torch.float32, device=self.device)  # _core reads this
        self.fire_interval = max(1, round(float(weapon["shotDelay"]) / c.dt))
        self.bullets_per_shot = int(weapon.get("bulletsPerShot", 1))
        self.penetration = max(1, int(weapon.get("penetrationPower", 1)))
        self.max_dev = float(weapon.get("maxDeviation", weapon.get("bulletDeviation", 0.0)))
        self.mag_size = int(weapon.get("magazineSize", 10 ** 9))
        self.reload_ticks = max(1, round(float(weapon.get("reloadTime", 0.0)) / c.dt))
        rate = 1.0 / (self.fire_interval * c.dt)                       # shots/sec
        self.wfeat = torch.tensor(                                     # [8] normalized; broadcast into both obs
            [self.bullet_damage / 50.0, rate / 20.0, self.bullets_per_shot / 6.0,
             self.penetration / 5.0, self.bullet_range / 1000.0, self.max_dev / 100.0,
             min(self.mag_size / 200.0, 1.5),                          # magazine CAPACITY (max ammo): pistol .06, minigun 1.0
             self.reload_ticks / 150.0],                               # reload DURATION: pistol .4, minigun 1.0 -> plan reloads
            dtype=torch.float32, device=self.device)
        if hasattr(self, "_pc_ticks"):
            del self._pc_ticks      # force _precompute rebuild (new fire_interval / max_dev / K)

    def reset(self, P):
        N, M, B, dev = self.N, self.M, self.B, self.device
        z = lambda *s: torch.zeros(*s, device=dev)
        return dict(
            player_pos=z(P, N, 2), player_hp=torch.full((P, N), self.cfg.player_max_hp, device=dev),
            mon_pos=z(P, N, M, 2), mon_vel=z(P, N, M, 2),
            mon_hp=self.hp0.unsqueeze(0).expand(P, N, M).clone(), mon_act=z(P, N, M),
            mon_contact=z(P, N, M),                                # was-in-contact flag (immediate pulse)
            bul_pos=z(P, N, B, 2), bul_vel=z(P, N, B, 2), bul_alive=z(P, N, B), bul_dist=z(P, N, B),
            bul_pen=z(P, N, B),                                    # penetration remaining
            ammo=torch.full((P, N), float(self.mag_size), device=dev), reload_t=z(P, N),
            kills=z(P, N),
            player_vel=z(P, N, 2), player_aim=z(P, N, 2),         # last-tick self motion/aim (for the attention obs)
        )

    # ---- observations ----
    def player_obs_vec(self, s):
        c = self.cfg
        rel = s["mon_pos"] - s["player_pos"][:, :, None, :]          # [P,N,M,2] toward monster
        dist = torch.sqrt((rel * rel).sum(-1)) + c.eps
        alive = ((s["mon_act"] > 0.5) & (s["mon_hp"] > 0)).float()
        cnt = alive.sum(-1)
        dirv = rel / dist[..., None]
        threat = (dirv * alive[..., None]).sum(2)                    # [P,N,2]
        threatN = threat / (torch.sqrt((threat * threat).sum(-1, keepdim=True)) + c.eps)
        masked = torch.where(alive > 0.5, dist, torch.full_like(dist, 1e9))
        nearest = masked.min(-1).values
        meanD = (dist * alive).sum(-1) / (cnt + c.eps)
        wall = s["player_pos"] / self.map_half.view(1, self.N, 1)    # [P,N,2] in [-1,1]: arena-size-invariant
        return torch.cat([(s["player_hp"] / c.player_max_hp)[..., None], (cnt / c.monster_count_norm)[..., None],
                          threatN, (nearest / c.dist_norm)[..., None], (meanD / c.dist_norm)[..., None], wall], -1)

    def player_set_obs(self, s):
        """Per-monster SET obs for the attention player — returns (self_feat [P,N,8], mon_feat [P,N,M,11],
        alive [P,N,M]). Rich features, nearly all FREE (the sim already computes the geometry); dead/absent
        monster slots are carried but the attention masks them via `alive`. No aggregation/summing."""
        c = self.cfg
        rel = s["mon_pos"] - s["player_pos"][:, :, None, :]          # [P,N,M,2] toward monster (bearing)
        dist = torch.sqrt((rel * rel).sum(-1)) + c.eps               # [P,N,M]
        dirv = rel / dist[..., None]                                 # [P,N,M,2] unit bearing
        alive = ((s["mon_act"] > 0.5) & (s["mon_hp"] > 0)).float()   # [P,N,M]
        cnt = alive.sum(-1)                                          # [P,N]
        snorm = c.monster_speed_norm
        spd = self.mon_speed[None]                                   # [1,N,M] -> broadcasts over P
        mvel_n = s["mon_vel"] / (spd[..., None] + c.eps)             # [P,N,M,2] monster velocity (|.|<=1)
        closing = (s["mon_vel"] * dirv).sum(-1) / snorm              # [P,N,M] radial speed (sign = toward/away)
        aim = s["player_aim"]                                        # [P,N,2]
        aim_dot = (dirv * aim[:, :, None, :]).sum(-1)                # [P,N,M] bearing·aim ("in my crosshair?")
        hp_n = s["mon_hp"] / (self.hp0[None] + c.eps)                # [P,N,M]
        spd_n = (spd / snorm).expand_as(dist)                        # [P,N,M] type behavior: max speed
        dmg_n = (self.mon_dmg[None] / 10.0).expand_as(dist)         # [P,N,M] type behavior: damage (~2-5)
        in_range = (dist / self.bullet_range).clamp(max=2.0)        # [P,N,M] <1 = killable now (range-discipline signal)
        # clear_shot: line-of-FIRE only (perception stays top-down/omniscient — no fog-of-war). Soft margin from
        # the SAME rule that kills bullets on rocks (_rock_margin), so 0 = "a shot along this bearing dies in a
        # rock" is truthful to the sim; >0 grades how cleanly the path clears (saturates at clear_shot_norm).
        p0 = s["player_pos"][:, :, None, :].expand_as(rel)          # [P,N,M,2]
        clear_shot = (self._rock_margin(p0, rel) / c.clear_shot_norm).clamp(0.0, 1.0)   # [P,N,M]
        mon_feat = torch.stack([dirv[..., 0], dirv[..., 1], dist / c.dist_norm,
                                mvel_n[..., 0], mvel_n[..., 1], closing,
                                hp_n, spd_n, dmg_n, aim_dot, alive, in_range, clear_shot], -1)  # [P,N,M,13]
        wall = s["player_pos"] / self.map_half.view(1, self.N, 1)    # [P,N,2]
        P, N = wall.shape[0], wall.shape[1]
        wf = self.wfeat.view(1, 1, -1).expand(P, N, -1)              # [P,N,6] current weapon params (player aware)
        ammo_n = (s["ammo"] / self.mag_size)[..., None]             # [P,N,1] magazine fraction
        reload_n = (s["reload_t"] / self.reload_ticks)[..., None]   # [P,N,1] reload progress (1=just started, 0=ready)
        flow_p = self._sample_flow(s["player_pos"][:, :, None, :]).squeeze(2)   # [P,N,2] rock-avoidance flow @ player
        self_feat = torch.cat([(s["player_hp"] / c.player_max_hp)[..., None], (cnt / c.monster_count_norm)[..., None],
                               wall, s["player_vel"], aim, wf, ammo_n, reload_n, flow_p], -1)  # [P,N,20]
        return self_feat, mon_feat, alive

    def enemy_obs_vec(self, s):
        c = self.cfg
        rel = s["player_pos"][:, :, None, :] - s["mon_pos"]          # [P,N,M,2] toward player
        dist = torch.sqrt((rel * rel).sum(-1)) + c.eps
        dirv = rel / dist[..., None]
        spd = self.mon_speed[None, :, :]                            # [1,N,M]
        vel_n = s["mon_vel"] / (spd[..., None] + c.eps)
        # nearest in-flight bullet per monster (so the enemy can learn to dodge) — [P,N,M,B]
        brel = s["bul_pos"][:, :, None, :, :] - s["mon_pos"][:, :, :, None, :]   # [P,N,M,B,2] toward bullet
        bd2 = (brel * brel).sum(-1)
        bd2 = torch.where(s["bul_alive"][:, :, None, :] > 0.5, bd2, torch.full_like(bd2, 1e18))
        bmin, bidx = bd2.min(-1)                                                  # [P,N,M]
        has = (bmin < 1e17).float()
        idx = bidx[..., None, None].expand(*bidx.shape, 1, 2)                     # [P,N,M,1,2]
        bnear = torch.gather(brel, 3, idx).squeeze(3)                             # [P,N,M,2] vec to bullet
        bdist = torch.sqrt(bmin.clamp(min=0.0)) + c.eps
        bdir = bnear / bdist[..., None] * has[..., None]                          # 0 when no live bullet
        bdist_n = torch.where(has > 0.5, (bdist / c.bullet_norm).clamp(max=2.0), torch.full_like(bdist, 2.0))
        # --- DYNAMICS (item 1): player velocity -> the monster can INTERCEPT (lead), not just chase; nearest
        # bullet's velocity -> it can dodge the bullet's PATH, not its current dot. Both already live in state.
        pvel_world = s["player_vel"] * (c.player_speed * self.exo_speed)          # [P,N,2] true world velocity
        pvel_rel = (pvel_world[:, :, None, :] - s["mon_vel"]) / c.monster_speed_norm   # [P,N,M,2] closing velocity
        bvel = torch.gather(s["bul_vel"][:, :, None, :, :].expand(*bd2.shape, 2), 3, idx).squeeze(3)   # [P,N,M,2]
        bvel_n = bvel / self.bullet_speed * has[..., None]                        # 0 when no live bullet
        # --- SWARM (item 2): mean-field heading (alignment, O(M)) + nearest-OTHER-monster (separation actability).
        alive = ((s["mon_act"] > 0.5) & (s["mon_hp"] > 0)).float()               # [P,N,M]
        cnt = alive.sum(2, keepdim=True) + c.eps                                  # [P,N,1]
        mean_vel = (s["mon_vel"] * alive[..., None]).sum(2) / cnt                 # [P,N,2] swarm mean velocity
        mean_head = mean_vel / (torch.sqrt((mean_vel * mean_vel).sum(-1, keepdim=True)) + c.eps)
        mean_head = mean_head[:, :, None, :].expand_as(dirv)                      # [P,N,M,2] alignment reference
        nd = s["mon_pos"][:, :, :, None, :] - s["mon_pos"][:, :, None, :, :]      # [P,N,M,M,2] (neighbor j -> self i)
        nd2 = (nd * nd).sum(-1)                                                   # [P,N,M,M]
        eye = torch.eye(self.M, device=nd2.device, dtype=torch.bool)[None, None]  # mask the self-pair
        nd2 = torch.where(eye | (alive[:, :, None, :] < 0.5), torch.full_like(nd2, 1e18), nd2)
        nnmin, nnidx = nd2.min(-1)                                                # [P,N,M] nearest OTHER monster
        nnhas = (nnmin < 1e17).float()
        nidx = nnidx[..., None, None].expand(*nnidx.shape, 1, 2)                  # [P,N,M,1,2]
        nn_vec = torch.gather(nd, 3, nidx).squeeze(3)                            # [P,N,M,2] points AWAY from neighbor
        nn_dist = torch.sqrt(nnmin.clamp(min=0.0)) + c.eps
        nn_dir = nn_vec / nn_dist[..., None] * nnhas[..., None]                   # 0 when alone
        nn_dist_n = torch.where(nnhas > 0.5, (nn_dist / c.dist_norm).clamp(max=2.0), torch.full_like(nn_dist, 2.0))
        Pn, Nn, Mn = dist.shape
        wf = self.wfeat.view(1, 1, 1, -1).expand(Pn, Nn, Mn, -1)                  # [P,N,M,6] weapon params (monster aware)
        ammo_m = (s["ammo"] / self.mag_size)[..., None, None].expand(Pn, Nn, Mn, 1)        # [P,N,M,1] player magazine frac
        reload_m = (s["reload_t"] / self.reload_ticks)[..., None, None].expand(Pn, Nn, Mn, 1)  # [P,N,M,1] -> monsters rush reloads
        flow_m = self._sample_flow(s["mon_pos"])                                 # [P,N,M,2] rock-avoidance flow @ each monster
        return torch.cat([dirv, (dist / c.dist_norm)[..., None], vel_n,
                          (spd / c.monster_speed_norm)[..., None].expand_as(dist[..., None]),
                          (s["mon_hp"] / (self.hp0[None] + c.eps))[..., None],
                          bdir, bdist_n[..., None],
                          pvel_rel, bvel_n,                                       # item 1: player + bullet dynamics
                          mean_head, nn_dir, nn_dist_n[..., None],                # item 2: align + separation
                          wf, ammo_m, reload_m, flow_m], -1)        # [P,N,M,31]  + rock-avoidance flow

    def _precompute(self, ticks):
        """Precompute per-tick spread (cos/sin), ring-slot one-hots, fire/contact gates, and elapsed —
        ONCE, as device tensors indexed by t. Removes the per-tick numpy + host->device copy from step()
        (the only CPU<->GPU boundary in the loop), which is what blocks fusion / CUDA-graph capture.
        Parity-exact: same det_rand hash / values as the inline version. Cached per (weapon-signature, ticks)
        so per-iteration weapon cycling reuses the 3 weapons' tables instead of rebuilding every iter."""
        key = (self.fire_interval, self.bullets_per_shot, round(self.max_dev, 6), ticks)
        hit = self._pc_cache.get(key)
        if hit is not None:
            (self._ct, self._st, self._onehot, self._gate_fire, self._gate_contact, self._elapsed) = hit
            self._pc_ticks = ticks
            return
        self._pc_ticks = ticks
        dev = self.device
        K, B, fi, ci = self.bullets_per_shot, self.B, self.fire_interval, self.contact_interval
        t_arr = np.arange(1, ticks + 1, dtype=np.int64)                          # [T]
        ks = np.arange(K, dtype=np.int64)                                        # [K]
        h = (t_arr[:, None] * 2654435761 + ks[None, :] * 2246822519 + 12345) & 0xffffffff  # large k mult -> real spread
        dr = h / 2147483647.5 - 1.0                                              # det_rand(t,k) [T,K]
        theta = np.arctan2(self.max_dev * dr, 500.0)
        self._ct = torch.tensor(np.cos(theta), dtype=torch.float32, device=dev)  # [T,K]
        self._st = torch.tensor(np.sin(theta), dtype=torch.float32, device=dev)  # [T,K]
        slots = ((t_arr // fi)[:, None] * K + ks[None, :]) % B                   # [T,K]
        oh = np.zeros((ticks, K, B), np.float32)
        oh[np.arange(ticks)[:, None], np.arange(K)[None, :], slots] = 1.0
        self._onehot = torch.tensor(oh, device=dev)                              # [T,K,B]
        self._gate_fire = torch.tensor((t_arr % fi == 0).astype(np.float32), device=dev)     # [T]
        self._gate_contact = torch.tensor((t_arr % ci == 0).astype(np.float32), device=dev)  # [T]
        self._elapsed = torch.tensor((t_arr * self.cfg.dt).astype(np.float32), device=dev)   # [T]
        self._pc_cache[key] = (self._ct, self._st, self._onehot, self._gate_fire, self._gate_contact, self._elapsed)

    # ---- one tick. player_fn: obs[P,N,8]->[P,N,4]; enemy_fn: obs[P,N,M,10]->[P,N,M,2] or None ----
    def step(self, s, t, player_fn, enemy_fn):
        # the player obs is pre-step, so the action is computed HERE (eager) and passed into _core; this
        # keeps the policy call OUT of the compiled core (no side-effecting closure inside compile) and
        # lets GRPO inject a grad-tracked action via step_pa. Numerically identical in eager.
        a_player = player_fn(self.player_obs_fn(s))   # player_obs_fn = player_obs_vec (MLP) or player_set_obs (attn)
        return self.step_pa(s, t, a_player, enemy_fn)

    def step_pa(self, s, t, a_player, enemy_fn):
        """Step with the player ACTION precomputed [P,N,4] (GRPO samples it with grad/log_prob outside)."""
        if not hasattr(self, "_pc_ticks") or t > self._pc_ticks:
            self._precompute(max(t * 2, 256))                       # cached; grows rarely
        i = t - 1
        # Per-tick tensors sliced HERE (eager) -> _core has no python-int guard, traces ONCE.
        return self._core(s, self._elapsed[i], self._gate_fire[i], self._gate_contact[i],
                          self._ct[i], self._st[i], self._onehot[i], a_player, enemy_fn)

    def _core(self, s, elapsed, gate_fire, gate_contact, pct, pst, onehot, a_player, enemy_fn):
        c = self.cfg
        P, N, M = s["mon_pos"].shape[0], self.N, self.M
        a_move, a_aim = a_player[..., 0:2], a_player[..., 2:4]
        a_fire = a_player[..., 4]                                   # [P,N] learned trigger; >0 = "mouse down"

        st = self.spawn_tick[None]                                  # [1,N,M]
        due = st <= elapsed
        just = due & (s["mon_act"] < 0.5)
        mon_pos = torch.where(just[..., None], s["player_pos"][:, :, None, :] + self.offset[None], s["mon_pos"])
        mon_act = torch.maximum(s["mon_act"], just.float())
        alive_b = due & (s["mon_hp"] > 0)

        rel = s["player_pos"][:, :, None, :] - mon_pos              # toward player
        dist = torch.sqrt((rel * rel).sum(-1)) + c.eps
        dirv = rel / dist[..., None]
        spd = self.mon_speed[None]
        stop = c.player_radius + self.mon_boxW[None] / 2
        move_mask = (alive_b & (dist > stop)).float()

        # neural enemy (the networked NPC) always drives monster velocity — scripted steering removed
        s2 = dict(s); s2["mon_pos"] = mon_pos                       # obs from post-spawn positions
        a_e = enemy_fn(self.enemy_obs_vec(s2))                      # [P,N,M,2]
        v = torch.tanh(a_e)
        vn = v / (torch.sqrt((v * v).sum(-1, keepdim=True)) + c.eps)
        mon_vel = vn * spd[..., None] * move_mask[..., None]
        mon_pos = mon_pos + mon_vel * c.dt                          # policy-driven (momentum/knock dropped)

        # ammo / reload state machine (per-env)
        reload_t = torch.clamp(s["reload_t"] - 1.0, min=0.0)
        just_reloaded = (s["reload_t"] > 0) & (reload_t == 0)
        ammo = torch.where(just_reloaded, torch.full_like(s["ammo"], float(self.mag_size)), s["ammo"])
        gate = gate_fire
        # learned trigger ANDs into the existing rate/ammo/reload machine: on a cadence tick the gun fires IFF the
        # player is holding the trigger (a_fire>0). Faithful mouse mirror — hold to fire at weapon rate, release = silent.
        fire = ((gate > 0.5) & (ammo > 0) & (reload_t == 0) & (a_fire > 0)).float()   # [P,N] envs firing this tick
        ammo = ammo - fire
        need_reload = (ammo <= 0) & (reload_t == 0)
        reload_t = torch.where(need_reload, torch.full_like(reload_t, float(self.reload_ticks)), reload_t)

        # fire bulletsPerShot pellets (deterministic spread) into the ring buffer
        aim = a_aim / (torch.sqrt((a_aim * a_aim).sum(-1, keepdim=True)) + c.eps)   # [P,N,2]
        bul_pos, bul_vel = s["bul_pos"], s["bul_vel"]
        bul_alive, bul_dist, bul_pen = s["bul_alive"], s["bul_dist"], s["bul_pen"]
        # pct/pst/onehot (spread cos/sin + ring-slot one-hot for this tick) are passed in as args.
        aimx, aimy = aim[..., 0:1], aim[..., 1:2]                                             # [P,N,1]
        pa = torch.stack([aimx * pct - aimy * pst, aimx * pst + aimy * pct], -1)              # [P,N,K,2]
        vel_k = pa * self.bullet_speed                                                        # [P,N,K,2]
        write_b = onehot.sum(0).clamp(max=1.0)                                                # [B] slots touched
        vel_b = torch.einsum("kb,pnkc->pnbc", onehot, vel_k)                                  # [P,N,B,2]
        writeB = write_b[None, None, :] * fire[:, :, None]                                    # [P,N,B]
        w1 = writeB[..., None]
        bul_pos = torch.where(w1 > 0.5, s["player_pos"][:, :, None, :], bul_pos)
        bul_vel = torch.where(w1 > 0.5, vel_b, bul_vel)
        bul_alive = torch.where(writeB > 0.5, torch.ones_like(bul_alive), bul_alive)
        bul_dist = torch.where(writeB > 0.5, torch.zeros_like(bul_dist), bul_dist)
        bul_pen = torch.where(writeB > 0.5, torch.full_like(bul_pen, float(self.penetration)), bul_pen)

        bul_p0 = bul_pos                                                       # pre-advance (incl. fresh muzzle spawns)
        bul_pos = bul_pos + bul_vel * c.dt
        bul_dist = bul_dist + torch.sqrt((bul_vel * bul_vel).sum(-1)) * c.dt
        bul_alive = ((bul_alive > 0.5) & (bul_dist < self._brange_t)).float()   # _brange_t: tensor -> no recompile on range change
        # bullet<->rock occlusion: SEGMENT test over this tick's travel (_rock_margin, the shared line-of-fire
        # rule) -> rocks block shots, and fast/grazing bullets can't tunnel a thin rock in one step.
        bul_alive = bul_alive * (self._rock_margin(bul_p0, bul_vel * c.dt) > 0.0).float()

        # collision with penetration (a bullet damages every monster it overlaps; dies after `pen` hits)
        diff = bul_pos[:, :, :, None, :] - mon_pos[:, :, None, :, :]
        d2 = (diff * diff).sum(-1)
        hitR = (c.bullet_radius + self.mon_boxW[None] / 2)
        hit = ((d2 < (hitR * hitR)[:, :, None, :]) &
               (bul_alive > 0.5)[..., None] & alive_b[:, :, None, :]).float()
        mon_hp = s["mon_hp"] - (hit * self.bullet_damage).sum(2)
        bul_pen = bul_pen - hit.sum(3)
        bul_alive = ((bul_alive > 0.5) & (bul_pen > 0.5)).float()

        alive_a = due & (mon_hp > 0)
        killed = (alive_b & (~alive_a)).float().sum(2)              # [P,N]
        kills = s["kills"] + killed
        # dense damage-DEALT shaping signal (training-only, capped at the monster's available HP so it
        # rewards landing shots, not overkill). Enters r_player only via rw_damage → 0.0 keeps parity.
        dmg_dealt = torch.minimum((hit * self.bullet_damage).sum(2), torch.clamp(s["mon_hp"], min=0.0)).sum(-1)

        # contact: immediate pulse on newly-touching + periodic for sustained; defense + min floor
        contact_now = (alive_a & (dist < (c.player_radius + self.mon_boxW[None] / 2 + c.buffer))).float()
        newly = contact_now * (1.0 - s["mon_contact"])
        sustained = contact_now * s["mon_contact"]
        gate_c = gate_contact
        dmg = ((newly + sustained * gate_c) * self.mon_dmg[None]).sum(2)
        applied = torch.where(dmg > 0, torch.clamp(dmg - self.defense, min=c.defense_min_floor), torch.zeros_like(dmg))
        player_hp = s["player_hp"] - applied
        mon_contact = contact_now

        # player move (tanh + exo speed; per-arena clamp)
        mv = torch.tanh(a_move)
        lo = (-self.map_half + c.player_half).view(1, N, 1)
        hi = (self.map_half - c.player_half).view(1, N, 1)
        player_vel = mv * (c.player_speed * self.exo_speed)         # policy-driven (momentum/knock dropped)
        player_pos = torch.minimum(torch.maximum(s["player_pos"] + player_vel * c.dt, lo), hi)

        # ---- RIGID BODIES: impenetrable circles, mass-weighted positional de-overlap (vectorized) ----
        af = alive_a.float()                                         # [P,N,M] real bodies
        mr = self.mon_boxW[None] * 0.5                              # [1,N,M] monster radius
        mm = self.mon_mass[None]                                    # [1,N,M] monster mass
        eye = torch.eye(M, device=mon_pos.device)[None, None]
        pair = af[:, :, :, None] * af[:, :, None, :] * (1.0 - eye)              # [P,N,M,M] valid pairs
        rsum = mr[..., :, None] + mr[..., None, :]                              # [1,N,M,M] radius sums
        mi, mj = mm[..., :, None], mm[..., None, :]
        fj = mj / (mi + mj + c.eps)                                             # i's positional share (lighter i moves more)
        msum = mm + c.player_mass + c.eps                                       # [1,N,M] monster+player
        fmon, fpl = c.player_mass / msum, mm / msum                            # player light -> moves more
        mh = self.map_half.view(1, N, 1, 1)
        # single-pass positional de-overlap (fully vectorized, no loop; dense piles may keep minor residual overlap)
        dvec = mon_pos[:, :, :, None, :] - mon_pos[:, :, None, :, :]            # [P,N,M,M,2] i<-j
        dlen = torch.sqrt((dvec * dvec).sum(-1) + c.eps)
        # sep_pen (enemy anti-stacking reward) reuses THIS pairwise dlen instead of re-materializing the [P,N,M,M,2]
        # tensor post-push (dedup: 1 of 3 M^2 passes removed). Measured pre-de-overlap — a hair larger raw values;
        # reward-only, NOT in the Swift parity contract, so the sim is unaffected.
        sep_pen = (torch.clamp(1.0 - dlen / self.sep_radius, min=0.0) * pair).sum((-1, -2))   # [P,N]
        overlap = torch.clamp(rsum - dlen, min=0.0) * pair
        push = (overlap * fj).clamp(max=c.max_overlap_push)
        mon_pos = mon_pos + (push[..., None] * (dvec / dlen[..., None])).sum(3)     # monster<->monster
        rp = mon_pos - player_pos[:, :, None, :]                                # [P,N,M,2] player->monster
        dpl = torch.sqrt((rp * rp).sum(-1) + c.eps)
        npl = rp / dpl[..., None]
        opl = torch.clamp((mr + c.player_radius) - dpl, min=0.0) * af           # monster<->player overlap
        mon_pos = mon_pos + (opl * fmon).clamp(max=c.max_overlap_push)[..., None] * npl
        player_pos = player_pos - ((opl * fpl).clamp(max=c.max_overlap_push)[..., None] * npl).sum(2)
        # body<->rock de-overlap: rocks are static/infinite-mass, so only the body moves out. Shape-generic via
        # the SDF base (_shape_sdf_grad): overlap = clamp(body_radius - sdf, 0), push along the SDF gradient —
        # identical to the old circle math for circles, exact for squares. Vectorized over K, no loops.
        rxy, rrad = self.rock_xy[None], self.rock_r[None]                          # [1,N,K,2] [1,N,K]
        rm, rsq = self.rock_m[None], self.rock_sq[None]                            # [1,N,K]
        mrk = mon_pos[:, :, :, None, :] - rxy[:, :, None, :, :]                    # [P,N,M,K,2] rock->monster
        msdf, mgrad = self._shape_sdf_grad(mrk, rrad[:, :, None, :], rsq[:, :, None, :])
        mov = (torch.clamp(mr[..., None] - msdf, min=0.0)
               * rm[:, :, None, :]).clamp(max=c.max_overlap_push)                  # [P,N,M,K]
        mon_pos = mon_pos + (mov[..., None] * mgrad).sum(3)
        prk = player_pos[:, :, None, :] - rxy                                      # [P,N,K,2] rock->player
        psdf, pgrad = self._shape_sdf_grad(prk, rrad, rsq)
        pov = (torch.clamp(c.player_radius - psdf, min=0.0) * rm).clamp(max=c.max_overlap_push)  # [P,N,K]
        player_pos = player_pos + (pov[..., None] * pgrad).sum(2)
        player_pos = torch.minimum(torch.maximum(player_pos, lo), hi)           # re-clamp player
        mon_pos = torch.minimum(torch.maximum(mon_pos, -mh), mh)                # keep shoved monsters in-arena
        # NOTE: momentum/knock impulse dropped — positional de-overlap alone gives impenetrability + frictionless
        # sliding (tangential motion preserved), without the knock channel saturating and overpowering policy motion.

        # player reward: survive + aim-shaping + kills − damage taken (alive-gated)
        threat_raw = ((mon_pos - player_pos[:, :, None, :]) * alive_a.float()[..., None]).sum(2)
        threatN = threat_raw / (torch.sqrt((threat_raw * threat_raw).sum(-1, keepdim=True)) + c.eps)
        aim_align = (aim * threatN).sum(-1)
        alive_env = (player_hp > 0).float()
        # spacing: reward keeping the (space_keep+1)-th nearest monster at distance (allow space_keep close,
        # keep the rest away). topk-smallest over alive distances; dead/absent slots = 1e9 -> saturates to 1.
        kth = min(self.space_keep + 1, M)
        masked_d = torch.where(alive_a, dist, torch.full_like(dist, 1e9))         # [P,N,M]
        d_k = torch.topk(masked_d, kth, dim=-1, largest=False).values[..., -1]    # [P,N] (space_keep+1)-th nearest
        space = torch.clamp(d_k / self.space_target, max=1.0)                     # 0 (3rd on top) .. 1 (>=target)
        # keep-out ring: soft incursion of each alive monster into ring_radius, measured from the POST-move player
        # position (mon_pos is already post-move). Pure current-distance penalty -> the predictor is learned, not coded.
        ring_rel = mon_pos - player_pos[:, :, None, :]                            # [P,N,M,2] post-move geometry
        ring_dist = torch.sqrt((ring_rel * ring_rel).sum(-1) + c.eps)             # [P,N,M]
        ring_inc = torch.clamp(1.0 - ring_dist / self.ring_radius, min=0.0)       # 0 outside ring .. 1 at body
        ring_pen = (ring_inc * alive_a.float()).sum(-1)                           # [P,N] Σ over alive monsters inside
        # UNIFY: a wall breaches the SAME personal-space circle. gap to the nearest wall per axis = map_half-|pos|;
        # incursion when that gap < ring_radius. Same radius + same rw_ring -> one signal for "keep monsters AND
        # boundaries out of my bubble" -> the player holds open center ground (escape routes) instead of getting
        # cornered. The net already sees its wall position (self_feat `wall`), so it can learn to slide off early.
        wall_gap = self.map_half.view(1, N, 1) - player_pos.abs()                 # [P,N,2] dist to nearest x/y wall
        ring_pen = ring_pen + torch.clamp(1.0 - wall_gap / self.ring_radius, min=0.0).sum(-1)   # + 2 walls (x,y)
        effort = torch.sqrt((mv * mv).sum(-1))                       # [P,N] |move| this tick (mv = tanh(a_move))
        r_player = (self.rw_survive + self.rw_aim * aim_align + self.rw_kill * killed + self.rw_space * space
                    + self.rw_damage * dmg_dealt - applied * self.rw_hit - self.rw_ring * ring_pen
                    - self.rw_effort * effort - self.rw_shot * fire) * alive_env

        # enemy reward: damage dealt + approach proximity − deaths
        approach = torch.clamp(1.0 - dist / 3000.0, min=0.0)
        approach = (approach * alive_a.float()).sum(2)
        # swarm shaping (shared/group reward, ES means over envs): alignment = coherent pack heading; separation
        # (sep_pen) is computed up in the de-overlap block from the SAME pairwise dlen (M^2 dedup — see there).
        acnt = af.sum(2, keepdim=True) + c.eps                                   # [P,N,1] (af from the bodies block)
        mvel_mean = (mon_vel * af[..., None]).sum(2) / acnt                      # [P,N,2] swarm mean velocity
        mhead = mvel_mean / (torch.sqrt((mvel_mean * mvel_mean).sum(-1, keepdim=True)) + c.eps)
        mvel_u = mon_vel / (torch.sqrt((mon_vel * mon_vel).sum(-1, keepdim=True)) + c.eps)
        align = ((mvel_u * mhead[:, :, None, :]).sum(-1) * af).sum(2) / acnt.squeeze(-1)   # [P,N] mean cos-alignment
        r_enemy = (self.rw_e_dmg * applied + self.rw_e_approach * approach - self.rw_e_deaths * killed
                   + self.rw_align * align - self.rw_separate * sep_pen)

        ns = dict(player_pos=player_pos, player_hp=player_hp, mon_pos=mon_pos, mon_vel=mon_vel,
                  mon_hp=mon_hp, mon_act=mon_act, mon_contact=mon_contact,
                  bul_pos=bul_pos, bul_vel=bul_vel, bul_alive=bul_alive, bul_dist=bul_dist, bul_pen=bul_pen,
                  ammo=ammo, reload_t=reload_t, kills=kills,
                  player_vel=mv, player_aim=aim)             # normalized tanh action for obs (line 225 rescales to world)
        # eval-only: emit per-tick reward-term sums as a SEPARATE return (never fed back into state, so no recompile);
        # the harness (_play_batch) accumulates them. None during training -> pruned, zero overhead, core stays pure calc.
        panel = None
        if self.decompose:
            ae = alive_env
            panel = {"p_kill": (killed * ae).sum(), "p_aim": (aim_align * ae).sum(), "p_damage": (dmg_dealt * ae).sum(),
                     "p_hit": (applied * ae).sum(), "p_space": (space * ae).sum(), "p_ring": (ring_pen * ae).sum(),
                     "p_effort": (effort * ae).sum(), "p_shot": (fire * ae).sum(), "p_alive": ae.sum(),
                     "e_dmg": applied.sum(), "e_approach": approach.sum(), "e_deaths": killed.sum(),
                     "e_align": align.sum(), "e_separate": sep_pen.sum(), "ticks": torch.ones((), device=ns["kills"].device)}
        return ns, r_player, r_enemy, panel

    @torch.no_grad()
    def rollout(self, P, ticks, player_fn, enemy_fn):
        """Returns per-(P,N) accumulated player & enemy reward, kills, hp. One pass, no grad (ES).
        The rollout carries state `s` across many compiled `_core` calls, so under CUDA-graph trees
        (torch.compile mode='reduce-overhead') we mark each tick as a new step — otherwise the next
        tick's graph replay clobbers the buffers the carried `s`/rewards still point to."""
        s = self.reset(P)
        rp = torch.zeros(P, self.N, device=self.device)
        re = torch.zeros(P, self.N, device=self.device)
        mark = getattr(torch.compiler, "cudagraph_mark_step_begin", lambda: None)
        for t in range(1, ticks + 1):
            mark()                                              # new CUDA-graph step (no-op when eager)
            s, r_p, r_e, _ = self.step(s, t, player_fn, enemy_fn)
            rp = rp + r_p; re = re + r_e                        # out-of-place: don't alias graph buffers
        return dict(reward_player=rp, reward_enemy=re,
                    kills=s["kills"].clone(), hp=s["player_hp"].clone())
