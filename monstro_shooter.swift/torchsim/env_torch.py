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
    h = (t * 2654435761 + k * 340573 + 12345) & 0xffffffff
    return h / 2147483647.5 - 1.0


class EnvTorch:
    player_obs = 8         # hp, count, threatXY, nearest, mean, wallX, wallY
    player_act = 5         # move2 + aim2 + fire1 (learned trigger; mirrors the game's click-to-fire, not auto-fire).
    #   NOTE: a per-type obs (8+4·6=32, "recognize monster type") was tried + reverted —
    #   it hurt ES (49% vs ~92% clear): 4.5x more params slows ES black-box search, and the obs is slower.
    #   Revisit only with a gradient method (PPO scales with params); keep the aggregate 8-dim obs for ES.
    enemy_obs = 19         # dirXY, dist, velXY, speed, hp, bulletDirXY, bulletDist,
    #   + playerClosingVelXY, bulletVelXY (dynamics), + meanHeadXY, nearestNbrDirXY, nearestNbrDist (swarm)
    enemy_act = 2
    player_set_fs = 8      # attention player obs — self features (hp, count, wallXY, velXY, aimXY)
    player_set_fm = 11     # attention player obs — per-monster features (see player_set_obs)

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
        self.mon_dmg = t(sched["dmg"])
        self.mon_direct = t(sched["direct"])
        self.hp0 = t(sched["hp0"])                    # [N,M]
        ah = sched.get("arena_half")
        self.map_half = t(ah) if ah is not None else torch.full((self.N,), c.map_half, device=device)  # [N]
        self.bullet_speed = float(weapon.get("bulletSpeed", 800))
        self.bullet_damage = float(weapon["damage"])
        self.bullet_range = float(weapon["shotRange"])
        self.fire_interval = max(1, round(float(weapon["shotDelay"]) / c.dt))
        self.contact_interval = max(1, round(c.damage_interval / c.dt))
        self.defense = float(exo.get("defence", 0.0))
        # OLD-SpriteKit weapon/exo extras (canonical)
        self.bullets_per_shot = int(weapon.get("bulletsPerShot", 1))
        self.penetration = max(1, int(weapon.get("penetrationPower", 1)))
        self.max_dev = float(weapon.get("maxDeviation", weapon.get("bulletDeviation", 0.0)))
        self.mag_size = int(weapon.get("magazineSize", 10 ** 9))
        self.reload_ticks = max(1, round(float(weapon.get("reloadTime", 0.0)) / c.dt))
        self.exo_speed = float(exo.get("speed", 1.0))
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
        self.player_obs_fn = self.player_obs_vec   # MLP/ES default; train sets to player_set_obs for attention

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
        mon_feat = torch.stack([dirv[..., 0], dirv[..., 1], dist / c.dist_norm,
                                mvel_n[..., 0], mvel_n[..., 1], closing,
                                hp_n, spd_n, dmg_n, aim_dot, alive], -1)            # [P,N,M,11]
        wall = s["player_pos"] / self.map_half.view(1, self.N, 1)    # [P,N,2]
        self_feat = torch.cat([(s["player_hp"] / c.player_max_hp)[..., None], (cnt / c.monster_count_norm)[..., None],
                               wall, s["player_vel"], aim], -1)      # [P,N,8]
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
        return torch.cat([dirv, (dist / c.dist_norm)[..., None], vel_n,
                          (spd / c.monster_speed_norm)[..., None].expand_as(dist[..., None]),
                          (s["mon_hp"] / (self.hp0[None] + c.eps))[..., None],
                          bdir, bdist_n[..., None],
                          pvel_rel, bvel_n,                                       # item 1: player + bullet dynamics
                          mean_head, nn_dir, nn_dist_n[..., None]], -1)   # [P,N,M,19]  item 2: align + separation

    def _precompute(self, ticks):
        """Precompute per-tick spread (cos/sin), ring-slot one-hots, fire/contact gates, and elapsed —
        ONCE, as device tensors indexed by t. Removes the per-tick numpy + host->device copy from step()
        (the only CPU<->GPU boundary in the loop), which is what blocks fusion / CUDA-graph capture.
        Parity-exact: same det_rand hash / values as the inline version."""
        self._pc_ticks = ticks
        dev = self.device
        K, B, fi, ci = self.bullets_per_shot, self.B, self.fire_interval, self.contact_interval
        t_arr = np.arange(1, ticks + 1, dtype=np.int64)                          # [T]
        ks = np.arange(K, dtype=np.int64)                                        # [K]
        h = (t_arr[:, None] * 2654435761 + ks[None, :] * 340573 + 12345) & 0xffffffff
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

        if enemy_fn is not None:                                    # networked shared enemy (the NPC)
            s2 = dict(s); s2["mon_pos"] = mon_pos                   # obs from post-spawn positions
            a_e = enemy_fn(self.enemy_obs_vec(s2))                  # [P,N,M,2]
            v = torch.tanh(a_e)
            vn = v / (torch.sqrt((v * v).sum(-1, keepdim=True)) + c.eps)
            mon_vel = vn * spd[..., None] * move_mask[..., None]
        else:                                                       # scripted direct/arc (fallback only)
            direct_vel = dirv * spd[..., None]
            arc = s["mon_vel"] + dirv * (c.turn_rate * c.dt)
            arc_vel = arc / (torch.sqrt((arc * arc).sum(-1, keepdim=True)) + c.eps) * spd[..., None]
            chosen = torch.where((self.mon_direct[None] > 0.5)[..., None], direct_vel, arc_vel)
            mon_vel = chosen * move_mask[..., None]
        mon_pos = mon_pos + mon_vel * c.dt

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

        bul_pos = bul_pos + bul_vel * c.dt
        bul_dist = bul_dist + torch.sqrt((bul_vel * bul_vel).sum(-1)) * c.dt
        bul_alive = ((bul_alive > 0.5) & (bul_dist < self.bullet_range)).float()

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

        # player move (tanh, exo speed mult, per-arena clamp)
        mv = torch.tanh(a_move)
        lo = (-self.map_half + c.player_half).view(1, N, 1)
        hi = (self.map_half - c.player_half).view(1, N, 1)
        player_pos = torch.minimum(torch.maximum(
            s["player_pos"] + mv * (c.player_speed * self.exo_speed * c.dt), lo), hi)

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
        # swarm shaping (shared/group reward, ES means over envs): alignment = coherent pack heading; separation =
        # anti-stacking penalty when monsters breach each other's small (sep_radius) personal circle.
        af = alive_a.float()                                                     # [P,N,M]
        acnt = af.sum(2, keepdim=True) + c.eps                                   # [P,N,1]
        mvel_mean = (mon_vel * af[..., None]).sum(2) / acnt                      # [P,N,2] swarm mean velocity
        mhead = mvel_mean / (torch.sqrt((mvel_mean * mvel_mean).sum(-1, keepdim=True)) + c.eps)
        mvel_u = mon_vel / (torch.sqrt((mon_vel * mon_vel).sum(-1, keepdim=True)) + c.eps)
        align = ((mvel_u * mhead[:, :, None, :]).sum(-1) * af).sum(2) / acnt.squeeze(-1)   # [P,N] mean cos-alignment
        pdiff = mon_pos[:, :, :, None, :] - mon_pos[:, :, None, :, :]            # [P,N,M,M,2] all monster pairs
        pd = torch.sqrt((pdiff * pdiff).sum(-1) + c.eps)                         # [P,N,M,M]
        pair = af[:, :, :, None] * af[:, :, None, :] * (1.0 - torch.eye(M, device=pd.device)[None, None])
        sep_pen = (torch.clamp(1.0 - pd / self.sep_radius, min=0.0) * pair).sum((-1, -2))   # [P,N] Σ pairwise breach
        r_enemy = (0.1 * applied + 0.0008 * approach - 0.02 * killed
                   + self.rw_align * align - self.rw_separate * sep_pen)

        ns = dict(player_pos=player_pos, player_hp=player_hp, mon_pos=mon_pos, mon_vel=mon_vel,
                  mon_hp=mon_hp, mon_act=mon_act, mon_contact=mon_contact,
                  bul_pos=bul_pos, bul_vel=bul_vel, bul_alive=bul_alive, bul_dist=bul_dist, bul_pen=bul_pen,
                  ammo=ammo, reload_t=reload_t, kills=kills,
                  player_vel=mv, player_aim=aim)             # carried for the attention obs (not used by sim)
        return ns, r_player, r_enemy

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
            s, r_p, r_e = self.step(s, t, player_fn, enemy_fn)
            rp = rp + r_p; re = re + r_e                        # out-of-place: don't alias graph buffers
        return dict(reward_player=rp, reward_enemy=re,
                    kills=s["kills"].clone(), hp=s["player_hp"].clone())
