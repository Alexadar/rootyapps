"""Torch BatchWorld — port of brax/env.py (Brax-paradigm vectorized game env), with TWO networked
agents: the player (move+aim) and a SHARED enemy net that drives every monster's velocity
(egocentric, type-conditioned) instead of the scripted chase. Scripted monster fallback kept.

State carries a leading [P, N] dim:  P = ES population (2*pop, mirrored),  N = envs.
The policy whose turn it is to train carries the population in its weights ([P,in,out]); the frozen
net uses center weights ([in,out]) that broadcast over P. Masked/branchless via torch.where.

Player reward mirrors env.py. Enemy reward is the adversary: damage dealt + approach − deaths.
"""
import numpy as np
import torch

DT = 1.0 / 30.0
PLAYER_SPEED = 300.0
PLAYER_HALF = 30.0
PLAYER_RADIUS = 30.0
MAP_HALF = 6000.0        # default arena half (per-map overridable via sched["arena_half"])
BUFFER = 5.0
BULLET_RADIUS = 6.0
TURN_RATE = 34.0
DAMAGE_INTERVAL = 1.0
EPS = 1e-6
MON_SPEED_NORM = 300.0     # obs normalizer for monster speed
MONSTER_COUNT_NORM = 64.0  # fixed count normalizer (NOT the per-env cap) -> train/eval consistent
BULLET_NORM = 1000.0       # obs normalizer for nearest-bullet distance


class EnvTorch:
    player_obs = 8         # hp, count, threatXY, nearest, mean, wallX, wallY
    player_act = 4
    enemy_obs = 10        # dirXY, dist, velXY, speed, hp, bulletDirXY, bulletDist
    enemy_act = 2

    def __init__(self, sched, weapon, exo, device="cpu", bullets=32):
        self.device = device
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
        self.map_half = t(ah) if ah is not None else torch.full((self.N,), MAP_HALF, device=device)  # [N]
        self.bullet_speed = float(weapon.get("bulletSpeed", 800))
        self.bullet_damage = float(weapon["damage"])
        self.bullet_range = float(weapon["shotRange"])
        self.fire_interval = max(1, round(float(weapon["shotDelay"]) / DT))
        self.contact_interval = max(1, round(DAMAGE_INTERVAL / DT))
        self.defense = float(exo.get("defence", 0.0))

    def reset(self, P):
        N, M, B, dev = self.N, self.M, self.B, self.device
        z = lambda *s: torch.zeros(*s, device=dev)
        return dict(
            player_pos=z(P, N, 2), player_hp=torch.full((P, N), 100.0, device=dev),
            mon_pos=z(P, N, M, 2), mon_vel=z(P, N, M, 2),
            mon_hp=self.hp0.unsqueeze(0).expand(P, N, M).clone(), mon_act=z(P, N, M),
            bul_pos=z(P, N, B, 2), bul_vel=z(P, N, B, 2), bul_alive=z(P, N, B), bul_dist=z(P, N, B),
            kills=z(P, N),
        )

    # ---- observations ----
    def player_obs_vec(self, s):
        rel = s["mon_pos"] - s["player_pos"][:, :, None, :]          # [P,N,M,2] toward monster
        dist = torch.sqrt((rel * rel).sum(-1)) + EPS
        alive = ((s["mon_act"] > 0.5) & (s["mon_hp"] > 0)).float()
        cnt = alive.sum(-1)
        dirv = rel / dist[..., None]
        threat = (dirv * alive[..., None]).sum(2)                    # [P,N,2]
        threatN = threat / (torch.sqrt((threat * threat).sum(-1, keepdim=True)) + EPS)
        masked = torch.where(alive > 0.5, dist, torch.full_like(dist, 1e9))
        nearest = masked.min(-1).values
        meanD = (dist * alive).sum(-1) / (cnt + EPS)
        wall = s["player_pos"] / self.map_half.view(1, self.N, 1)    # [P,N,2] in [-1,1]: arena-size-invariant
        return torch.cat([(s["player_hp"] / 100.0)[..., None], (cnt / MONSTER_COUNT_NORM)[..., None],
                          threatN, (nearest / 1000.0)[..., None], (meanD / 1000.0)[..., None], wall], -1)

    def enemy_obs_vec(self, s):
        rel = s["player_pos"][:, :, None, :] - s["mon_pos"]          # [P,N,M,2] toward player
        dist = torch.sqrt((rel * rel).sum(-1)) + EPS
        dirv = rel / dist[..., None]
        spd = self.mon_speed[None, :, :]                            # [1,N,M]
        vel_n = s["mon_vel"] / (spd[..., None] + EPS)
        # nearest in-flight bullet per monster (so the enemy can learn to dodge) — [P,N,M,B]
        brel = s["bul_pos"][:, :, None, :, :] - s["mon_pos"][:, :, :, None, :]   # [P,N,M,B,2] toward bullet
        bd2 = (brel * brel).sum(-1)
        bd2 = torch.where(s["bul_alive"][:, :, None, :] > 0.5, bd2, torch.full_like(bd2, 1e18))
        bmin, bidx = bd2.min(-1)                                                  # [P,N,M]
        has = (bmin < 1e17).float()
        idx = bidx[..., None, None].expand(*bidx.shape, 1, 2)                     # [P,N,M,1,2]
        bnear = torch.gather(brel, 3, idx).squeeze(3)                             # [P,N,M,2] vec to bullet
        bdist = torch.sqrt(bmin.clamp(min=0.0)) + EPS
        bdir = bnear / bdist[..., None] * has[..., None]                          # 0 when no live bullet
        bdist_n = torch.where(has > 0.5, (bdist / BULLET_NORM).clamp(max=2.0), torch.full_like(bdist, 2.0))
        return torch.cat([dirv, (dist / 1000.0)[..., None], vel_n,
                          (spd / MON_SPEED_NORM)[..., None].expand_as(dist[..., None]),
                          (s["mon_hp"] / (self.hp0[None] + EPS))[..., None],
                          bdir, bdist_n[..., None]], -1)   # [P,N,M,10]

    # ---- one tick. player_fn: obs[P,N,6]->[P,N,4]; enemy_fn: obs[P,N,M,7]->[P,N,M,2] or None ----
    def step(self, s, t, player_fn, enemy_fn):
        P, N, M = s["mon_pos"].shape[0], self.N, self.M
        a_player = player_fn(self.player_obs_vec(s))                 # pre-step player obs
        a_move, a_aim = a_player[..., 0:2], a_player[..., 2:4]

        elapsed = float(t) * DT
        st = self.spawn_tick[None]                                  # [1,N,M]
        due = st <= elapsed
        just = due & (s["mon_act"] < 0.5)
        mon_pos = torch.where(just[..., None], s["player_pos"][:, :, None, :] + self.offset[None], s["mon_pos"])
        mon_act = torch.maximum(s["mon_act"], just.float())
        alive_b = due & (s["mon_hp"] > 0)

        rel = s["player_pos"][:, :, None, :] - mon_pos              # toward player
        dist = torch.sqrt((rel * rel).sum(-1)) + EPS
        dirv = rel / dist[..., None]
        spd = self.mon_speed[None]
        stop = PLAYER_RADIUS + self.mon_boxW[None] / 2
        move_mask = (alive_b & (dist > stop)).float()

        if enemy_fn is not None:                                    # networked shared enemy
            s2 = dict(s); s2["mon_pos"] = mon_pos                   # obs from post-spawn positions
            a_e = enemy_fn(self.enemy_obs_vec(s2))                  # [P,N,M,2]
            v = torch.tanh(a_e)
            vn = v / (torch.sqrt((v * v).sum(-1, keepdim=True)) + EPS)
            mon_vel = vn * spd[..., None] * move_mask[..., None]
        else:                                                       # scripted direct/arc
            direct_vel = dirv * spd[..., None]
            arc = s["mon_vel"] + dirv * (TURN_RATE * DT)
            arc_vel = arc / (torch.sqrt((arc * arc).sum(-1, keepdim=True)) + EPS) * spd[..., None]
            chosen = torch.where((self.mon_direct[None] > 0.5)[..., None], direct_vel, arc_vel)
            mon_vel = chosen * move_mask[..., None]
        mon_pos = mon_pos + mon_vel * DT

        # fire along aim, gated
        aim = a_aim / (torch.sqrt((a_aim * a_aim).sum(-1, keepdim=True)) + EPS)
        fire_gate = 1.0 if (t % self.fire_interval == 0) else 0.0
        slot = (t // self.fire_interval) % self.B
        onehot = (torch.arange(self.B, device=self.device) == slot).float() * fire_gate
        wb1 = onehot[None, None, :, None]; wb = onehot[None, None, :]
        bul_pos = torch.where(wb1 > 0.5, s["player_pos"][:, :, None, :], s["bul_pos"])
        bul_vel = torch.where(wb1 > 0.5, (aim * self.bullet_speed)[:, :, None, :], s["bul_vel"])
        bul_alive = torch.where(wb > 0.5, torch.ones_like(s["bul_alive"]), s["bul_alive"])
        bul_dist = torch.where(wb > 0.5, torch.zeros_like(s["bul_dist"]), s["bul_dist"])

        bul_pos = bul_pos + bul_vel * DT
        bul_dist = bul_dist + torch.sqrt((bul_vel * bul_vel).sum(-1)) * DT
        bul_alive = ((bul_alive > 0.5) & (bul_dist < self.bullet_range)).float()

        # collision [P,N,B,M]
        diff = bul_pos[:, :, :, None, :] - mon_pos[:, :, None, :, :]
        d2 = (diff * diff).sum(-1)
        hitR = (BULLET_RADIUS + self.mon_boxW[None] / 2)
        hit = ((d2 < (hitR * hitR)[:, :, None, :]) &
               (bul_alive > 0.5)[..., None] & alive_b[:, :, None, :]).float()
        mon_hp = s["mon_hp"] - (hit * self.bullet_damage).sum(2)
        bul_alive = ((bul_alive > 0.5) & (hit.sum(3) < 0.5)).float()

        alive_a = due & (mon_hp > 0)
        killed = (alive_b & (~alive_a)).float().sum(2)              # [P,N]
        kills = s["kills"] + killed

        contact_gate = 1.0 if (t % self.contact_interval == 0) else 0.0
        contact = (alive_a & (dist < (PLAYER_RADIUS + self.mon_boxW[None] / 2 + BUFFER))).float()
        dmg = (contact * self.mon_dmg[None]).sum(2) * contact_gate
        applied = torch.clamp(dmg - self.defense, min=0.0)
        player_hp = s["player_hp"] - applied

        mv = torch.tanh(a_move)
        lo = (-self.map_half + PLAYER_HALF).view(1, N, 1)            # per-env arena bounds
        hi = (self.map_half - PLAYER_HALF).view(1, N, 1)
        player_pos = torch.minimum(torch.maximum(s["player_pos"] + mv * (PLAYER_SPEED * DT), lo), hi)

        # player reward (env.py:150-155)
        threat_raw = ((mon_pos - player_pos[:, :, None, :]) * alive_a.float()[..., None]).sum(2)
        threatN = threat_raw / (torch.sqrt((threat_raw * threat_raw).sum(-1, keepdim=True)) + EPS)
        aim_align = (aim * threatN).sum(-1)
        alive_env = (player_hp > 0).float()
        r_player = (0.01 + 0.005 * aim_align + killed - applied * 0.05) * alive_env

        # enemy reward: damage dealt + approach proximity − deaths
        approach = torch.clamp(1.0 - dist / 3000.0, min=0.0)
        approach = (approach * alive_a.float()).sum(2)
        r_enemy = 0.1 * applied + 0.0008 * approach - 0.02 * killed

        ns = dict(player_pos=player_pos, player_hp=player_hp, mon_pos=mon_pos, mon_vel=mon_vel,
                  mon_hp=mon_hp, mon_act=mon_act, bul_pos=bul_pos, bul_vel=bul_vel,
                  bul_alive=bul_alive, bul_dist=bul_dist, kills=kills)
        return ns, r_player, r_enemy

    @torch.no_grad()
    def rollout(self, P, ticks, player_fn, enemy_fn):
        """Returns per-(P,N) accumulated player & enemy reward, kills, hp. One pass, no grad (ES)."""
        s = self.reset(P)
        rp = torch.zeros(P, self.N, device=self.device)
        re = torch.zeros(P, self.N, device=self.device)
        for t in range(1, ticks + 1):
            s, r_p, r_e = self.step(s, t, player_fn, enemy_fn)
            rp += r_p; re += r_e
        return dict(reward_player=rp, reward_enemy=re, kills=s["kills"], hp=s["player_hp"])
