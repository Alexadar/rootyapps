"""JAX BatchWorld — the vectorized game env, Brax-paradigm (custom kinematics, not rigid-body).
A pure jit-able step + a lax.scan rollout (one device sync per episode). Mirror of BatchWorld.swift
(playerStep + rolloutPlayer). Masked/branchless via jnp.where; fixed MAX_M/B + alive masks."""
from typing import NamedTuple
import jax
import jax.numpy as jnp
import numpy as np

# constants (mirror SimConstants)
DT = 1.0 / 30.0
PLAYER_SPEED = 300.0
PLAYER_HALF = 30.0
PLAYER_RADIUS = 30.0
MAP_HALF = 6000.0
BUFFER = 5.0
BULLET_RADIUS = 6.0
TURN_RATE = 34.0
DAMAGE_INTERVAL = 1.0
EPS = 1e-6
B = 128            # bullet slots


class State(NamedTuple):
    player_pos: jnp.ndarray   # [N,2]
    player_hp: jnp.ndarray    # [N]
    mon_pos: jnp.ndarray      # [N,M,2]
    mon_vel: jnp.ndarray
    mon_hp: jnp.ndarray       # [N,M]
    mon_act: jnp.ndarray      # [N,M]
    bul_pos: jnp.ndarray      # [N,B,2]
    bul_vel: jnp.ndarray
    bul_alive: jnp.ndarray    # [N,B]
    bul_dist: jnp.ndarray
    kills: jnp.ndarray        # [N]


class Env:
    """Built for a fixed N and a precomputed schedule. obs_size=6, act_size=4 (moveXY, aimXY)."""
    obs_size = 6
    act_size = 4

    def __init__(self, level, sched, weapon, exo, max_seconds=None):
        self.N = sched["spawn_tick"].shape[0]
        self.M = sched["M"]
        self.duration = level["duration"]
        self.max_seconds = max_seconds or level["duration"]
        # per-env static arrays
        j = lambda a: jnp.asarray(a, jnp.float32)
        self.spawn_tick = j(sched["spawn_tick"])
        self.offset = j(sched["offset"])
        self.mon_speed = j(sched["speed"])
        self.mon_boxW = j(sched["boxW"])
        self.mon_dmg = j(sched["dmg"])
        self.mon_direct = j(sched["direct"])
        self.hp0 = j(sched["hp0"])
        # weapon / exo
        self.bullet_speed = float(weapon.get("bulletSpeed", 800))
        self.bullet_damage = float(weapon["damage"])
        self.bullet_range = float(weapon["shotRange"])
        self.fire_interval = max(1, round(float(weapon["shotDelay"]) / DT))
        self.contact_interval = max(1, round(DAMAGE_INTERVAL / DT))
        self.defense = float(exo.get("defence", 0.0))

    def reset(self):
        N, M = self.N, self.M
        z2 = jnp.zeros((N, 2)); z = jnp.zeros((N,))
        return State(
            player_pos=z2, player_hp=jnp.full((N,), 100.0),
            mon_pos=jnp.zeros((N, M, 2)), mon_vel=jnp.zeros((N, M, 2)),
            mon_hp=self.hp0, mon_act=jnp.zeros((N, M)),
            bul_pos=jnp.zeros((N, B, 2)), bul_vel=jnp.zeros((N, B, 2)),
            bul_alive=jnp.zeros((N, B)), bul_dist=jnp.zeros((N, B)),
            kills=z,
        )

    def obs(self, s):
        rel = s.mon_pos - s.player_pos[:, None, :]                 # [N,M,2] toward monster
        dist = jnp.sqrt(jnp.sum(rel * rel, -1)) + EPS              # [N,M]
        alive = ((s.mon_act > 0.5) & (s.mon_hp > 0)).astype(jnp.float32)
        cnt = jnp.sum(alive, -1)                                   # [N]
        dirv = rel / dist[..., None]
        threat = jnp.sum(dirv * alive[..., None], 1)               # [N,2]
        threatN = threat / (jnp.sqrt(jnp.sum(threat * threat, -1, keepdims=True)) + EPS)
        masked = jnp.where(alive > 0.5, dist, 1e9)
        nearest = jnp.min(masked, -1)
        meanD = jnp.sum(dist * alive, -1) / (cnt + EPS)
        return jnp.concatenate([
            (s.player_hp / 100.0)[:, None], (cnt / self.M)[:, None], threatN,
            (nearest / 1000.0)[:, None], (meanD / 1000.0)[:, None]], -1)   # [N,6]

    def step(self, s, t, a_move, a_aim):
        N, M = self.N, self.M
        elapsed = t.astype(jnp.float32) * DT
        due = self.spawn_tick <= elapsed
        just = due & (s.mon_act < 0.5)
        mon_pos = jnp.where(just[..., None], s.player_pos[:, None, :] + self.offset, s.mon_pos)
        mon_act = jnp.maximum(s.mon_act, just.astype(jnp.float32))
        alive_b = due & (s.mon_hp > 0)

        rel = s.player_pos[:, None, :] - mon_pos
        dist = jnp.sqrt(jnp.sum(rel * rel, -1)) + EPS
        dirv = rel / dist[..., None]
        stop = PLAYER_RADIUS + self.mon_boxW / 2
        move_mask = (alive_b & (dist > stop)).astype(jnp.float32)
        direct_vel = dirv * self.mon_speed[..., None]
        arc = s.mon_vel + dirv * (TURN_RATE * DT)
        arc_sp = jnp.sqrt(jnp.sum(arc * arc, -1)) + EPS
        arc_vel = arc / arc_sp[..., None] * self.mon_speed[..., None]
        chosen = jnp.where((self.mon_direct > 0.5)[..., None], direct_vel, arc_vel)
        mon_vel = chosen * move_mask[..., None]
        mon_pos = mon_pos + mon_vel * DT

        # fire along aim, gated
        aim = a_aim / (jnp.sqrt(jnp.sum(a_aim * a_aim, -1, keepdims=True)) + EPS)
        fire_gate = (t % self.fire_interval == 0).astype(jnp.float32)
        slot = (t // self.fire_interval) % B
        onehot = (jnp.arange(B) == slot).astype(jnp.float32) * fire_gate    # [B]
        wb1 = onehot[None, :, None]; wb = onehot[None, :]
        bul_pos = jnp.where(wb1 > 0.5, s.player_pos[:, None, :], s.bul_pos)
        bul_vel = jnp.where(wb1 > 0.5, (aim * self.bullet_speed)[:, None, :], s.bul_vel)
        bul_alive = jnp.where(wb > 0.5, 1.0, s.bul_alive)
        bul_dist = jnp.where(wb > 0.5, 0.0, s.bul_dist)

        bul_pos = bul_pos + bul_vel * DT
        bul_dist = bul_dist + jnp.sqrt(jnp.sum(bul_vel * bul_vel, -1)) * DT
        bul_alive = ((bul_alive > 0.5) & (bul_dist < self.bullet_range)).astype(jnp.float32)

        # collision (reduction)
        diff = bul_pos[:, :, None, :] - mon_pos[:, None, :, :]       # [N,B,M,2]
        d2 = jnp.sum(diff * diff, -1)                               # [N,B,M]
        hitR = (BULLET_RADIUS + self.mon_boxW / 2)
        hit = ((d2 < (hitR * hitR)[:, None, :]) &
               (bul_alive > 0.5)[:, :, None] & alive_b[:, None, :]).astype(jnp.float32)
        mon_hp = s.mon_hp - jnp.sum(hit * self.bullet_damage, 1)
        bul_alive = ((bul_alive > 0.5) & (jnp.sum(hit, 2) < 0.5)).astype(jnp.float32)

        alive_a = due & (mon_hp > 0)
        killed = jnp.sum((alive_b & ~alive_a).astype(jnp.float32), 1)   # [N]
        kills = s.kills + killed

        contact_gate = (t % self.contact_interval == 0).astype(jnp.float32)
        contact = (alive_a & (dist < (PLAYER_RADIUS + self.mon_boxW / 2 + BUFFER))).astype(jnp.float32)
        dmg = jnp.sum(contact * self.mon_dmg, 1) * contact_gate
        applied = jnp.maximum(dmg - self.defense, 0.0)
        player_hp = s.player_hp - applied

        mv = jnp.tanh(a_move)
        player_pos = jnp.clip(s.player_pos + mv * (PLAYER_SPEED * DT), -MAP_HALF + PLAYER_HALF, MAP_HALF - PLAYER_HALF)

        # reward: survive + aim-shaping + kills - damage, alive-gated
        threat_raw = jnp.sum((mon_pos - player_pos[:, None, :]) * alive_a.astype(jnp.float32)[..., None], 1)
        threatN = threat_raw / (jnp.sqrt(jnp.sum(threat_raw * threat_raw, -1, keepdims=True)) + EPS)
        aim_align = jnp.sum(aim * threatN, -1)
        alive_env = (player_hp > 0).astype(jnp.float32)
        reward = (0.01 + 0.005 * aim_align + killed - applied * 0.05) * alive_env

        ns = State(player_pos, player_hp, mon_pos, mon_vel, mon_hp, mon_act,
                   bul_pos, bul_vel, bul_alive, bul_dist, kills)
        return ns, reward

    def rollout(self, apply_fn, params, ticks):
        """Full episode driven by apply_fn(params, obs)->[N,4]. lax.scan; one sync at the end."""
        s0 = self.reset()

        def body(carry, t):
            s, racc = carry
            out = apply_fn(params, self.obs(s))
            s, r = self.step(s, t, out[:, 0:2], out[:, 2:4])
            return (s, racc + r), None

        (s, racc), _ = jax.lax.scan(body, (s0, jnp.zeros(self.N)), jnp.arange(1, ticks + 1, dtype=jnp.int32))
        return dict(reward=racc, kills=s.kills, hp=s.player_hp)
