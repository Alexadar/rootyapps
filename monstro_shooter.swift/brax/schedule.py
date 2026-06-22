"""CPU-precomputed deterministic spawn schedule — mirror of SpawnSchedule.swift.
Per env (own seed) per monster slot: spawn tick (SECONDS), spawn offset, and per-type stats.
Rule-parity (not bit-exact): numpy default_rng != Swift SeededGenerator, but same logic/distributions.

Single-map (`build`) clones one level across all envs. Multi-map (`build_multi`) round-robins a LIST
of levels across the env batch (domain randomization) so one policy generalizes across maps — all
padded to a common M (the max over maps; unused slots stay never-spawn)."""
import numpy as np

SPAWN_HALF_W = 830.0
SPAWN_HALF_H = 650.0
SPAWN_INTERVAL = 1.0


def _fill_env(arrays, e, level, monsters, base_seed, M):
    """Fill env-row `e` of the preallocated arrays from one level (own seeded rng)."""
    spawn_tick, off, hp0, speed, boxW, dmg, direct = arrays
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
        if slot >= M:
            break


def _alloc(n_envs, M):
    return (
        np.full((n_envs, M), 1e30, np.float32),   # spawn_tick (seconds; never-spawn = huge)
        np.zeros((n_envs, M, 2), np.float32),      # offset
        np.ones((n_envs, M), np.float32),          # hp0
        np.zeros((n_envs, M), np.float32),         # speed
        np.ones((n_envs, M), np.float32),          # boxW
        np.zeros((n_envs, M), np.float32),         # dmg
        np.ones((n_envs, M), np.float32),          # direct
    )


def _pack(arrays, M):
    spawn_tick, off, hp0, speed, boxW, dmg, direct = arrays
    return dict(M=M, spawn_tick=spawn_tick, offset=off, hp0=hp0,
                speed=speed, boxW=boxW, dmg=dmg, direct=direct)


def build(level, monsters, base_seed, n_envs, cap=512):
    M = max(min(level["expected_total"], cap), 1)
    arrays = _alloc(n_envs, M)
    for e in range(n_envs):
        _fill_env(arrays, e, level, monsters, base_seed, M)
    return _pack(arrays, M)


def build_multi(levels, monsters, base_seed, n_envs, cap=512):
    """Round-robin `levels` across the env batch: env e uses levels[e % L]. Common M = max over
    maps (shorter maps leave the tail as never-spawn). Returns the same dict shape as `build`,
    plus `assign` (per-env level index) for reporting."""
    L = len(levels)
    M = max(max(min(lv["expected_total"], cap) for lv in levels), 1)
    arrays = _alloc(n_envs, M)
    assign = np.zeros(n_envs, np.int32)
    for e in range(n_envs):
        li = e % L
        assign[e] = li
        _fill_env(arrays, e, levels[li], monsters, base_seed, M)
    out = _pack(arrays, M)
    out["assign"] = assign
    return out
