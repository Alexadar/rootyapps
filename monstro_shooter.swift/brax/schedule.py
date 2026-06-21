"""CPU-precomputed deterministic spawn schedule — mirror of SpawnSchedule.swift.
Per env (own seed) per monster slot: spawn tick (SECONDS), spawn offset, and per-type stats.
Rule-parity (not bit-exact): numpy default_rng != Swift SeededGenerator, but same logic/distributions."""
import numpy as np

SPAWN_HALF_W = 830.0
SPAWN_HALF_H = 650.0
SPAWN_INTERVAL = 1.0


def build(level, monsters, base_seed, n_envs, cap=512):
    total = min(level["expected_total"], cap)
    M = max(total, 1)
    spawn_tick = np.full((n_envs, M), 1e30, np.float32)   # seconds; never-spawn = huge
    off = np.zeros((n_envs, M, 2), np.float32)
    hp0 = np.ones((n_envs, M), np.float32)
    speed = np.zeros((n_envs, M), np.float32)
    boxW = np.ones((n_envs, M), np.float32)
    dmg = np.zeros((n_envs, M), np.float32)
    direct = np.ones((n_envs, M), np.float32)

    for e in range(n_envs):
        rng = np.random.default_rng(base_seed + e)
        slot = 0
        for (start, count, types) in level["waves"]:
            for k in range(count):
                if slot >= M:
                    break
                t = start + k * SPAWN_INTERVAL
                typ = int(types[rng.integers(0, len(types))])
                side = int(rng.integers(0, 4))
                if side == 0:
                    ox, oy = rng.uniform(-SPAWN_HALF_W, SPAWN_HALF_W), SPAWN_HALF_H
                elif side == 1:
                    ox, oy = SPAWN_HALF_W, rng.uniform(-SPAWN_HALF_H, SPAWN_HALF_H)
                elif side == 2:
                    ox, oy = rng.uniform(-SPAWN_HALF_W, SPAWN_HALF_W), -SPAWN_HALF_H
                else:
                    ox, oy = -SPAWN_HALF_W, rng.uniform(-SPAWN_HALF_H, SPAWN_HALF_H)
                spawn_tick[e, slot] = t
                off[e, slot] = (ox, oy)
                m = monsters.get(typ)
                if m:
                    hp0[e, slot] = float(m["health"])
                    speed[e, slot] = float(m["speed"])
                    boxW[e, slot] = float(m["boxWidth"])
                    dmg[e, slot] = float(m["damage"])
                    direct[e, slot] = 1.0 if m.get("useDirectSteering") else 0.0
                slot += 1
    return dict(M=M, spawn_tick=spawn_tick, offset=off, hp0=hp0,
                speed=speed, boxW=boxW, dmg=dmg, direct=direct)
