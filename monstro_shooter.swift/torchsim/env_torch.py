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
    player_act = 4         # NOTE: a per-type obs (8+4·6=32, "recognize monster type") was tried + reverted —
    #   it hurt ES (49% vs ~92% clear): 4.5x more params slows ES black-box search, and the obs is slower.
    #   Revisit only with a gradient method (PPO scales with params); keep the aggregate 8-dim obs for ES.
    enemy_obs = 10         # dirXY, dist, velXY, speed, hp, bulletDirXY, bulletDist
    enemy_act = 2

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
        self.rw_damage = 0.0     # dense per-tick reward per HP of damage DEALT (0 = off, checksum-neutral)

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
        return torch.cat([dirv, (dist / c.dist_norm)[..., None], vel_n,
                          (spd / c.monster_speed_norm)[..., None].expand_as(dist[..., None]),
                          (s["mon_hp"] / (self.hp0[None] + c.eps))[..., None],
                          bdir, bdist_n[..., None]], -1)   # [P,N,M,10]

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
        a_player = player_fn(self.player_obs_vec(s))
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
        fire = ((gate > 0.5) & (ammo > 0) & (reload_t == 0)).float()        # [P,N] envs firing this tick
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
        r_player = (self.rw_survive + 0.005 * aim_align + self.rw_kill * killed
                    + self.rw_damage * dmg_dealt - applied * 0.05) * alive_env

        # enemy reward: damage dealt + approach proximity − deaths
        approach = torch.clamp(1.0 - dist / 3000.0, min=0.0)
        approach = (approach * alive_a.float()).sum(2)
        r_enemy = 0.1 * applied + 0.0008 * approach - 0.02 * killed

        ns = dict(player_pos=player_pos, player_hp=player_hp, mon_pos=mon_pos, mon_vel=mon_vel,
                  mon_hp=mon_hp, mon_act=mon_act, mon_contact=mon_contact,
                  bul_pos=bul_pos, bul_vel=bul_vel, bul_alive=bul_alive, bul_dist=bul_dist, bul_pen=bul_pen,
                  ammo=ammo, reload_t=reload_t, kills=kills)
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
