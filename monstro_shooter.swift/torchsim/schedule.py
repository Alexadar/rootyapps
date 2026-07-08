"""CPU-precomputed deterministic spawn schedule — mirror of SpawnSchedule.swift.
Per env (own seed) per monster slot: spawn tick (SECONDS), spawn offset, and per-type stats.
Rule-parity (not bit-exact): numpy default_rng != Swift SeededGenerator, but same logic/distributions.

Single-map (`build`) clones one level across all envs. Multi-map (`build_multi`) round-robins a LIST
of levels across the env batch (domain randomization) so one policy generalizes across maps — all
padded to a common M (the max over maps; unused slots stay never-spawn).

Each env is independent (seeded `base_seed + e`), so the per-env fill is fanned across CPU cores via
a process pool — output is IDENTICAL to serial (env e always seeded the same), just parallel."""
import os
from concurrent.futures import ProcessPoolExecutor
import numpy as np

SPAWN_HALF_W = 830.0
SPAWN_HALF_H = 650.0
SPAWN_INTERVAL = 1.0


def _fill_env(arrays, row, level, monsters, seed, M):
    """Fill row `row` of the preallocated arrays from one level, RNG seeded by `seed`."""
    spawn_tick, off, hp0, speed, boxW, dmg, direct, mtype, mass = arrays
    shw = level.get("spawn_half_w", SPAWN_HALF_W)     # per-map spawn radius (defaults to legacy box)
    shh = level.get("spawn_half_h", SPAWN_HALF_H)
    rng = np.random.default_rng(seed)
    slot = 0
    for (start, count, types) in level["waves"]:
        for k in range(count):
            if slot >= M:
                break
            t = start + k * SPAWN_INTERVAL
            typ = int(types[rng.integers(0, len(types))])
            side = int(rng.integers(0, 4))
            if side == 0:
                ox, oy = rng.uniform(-shw, shw), shh
            elif side == 1:
                ox, oy = shw, rng.uniform(-shh, shh)
            elif side == 2:
                ox, oy = rng.uniform(-shw, shw), -shh
            else:
                ox, oy = -shw, rng.uniform(-shh, shh)
            spawn_tick[row, slot] = t
            off[row, slot] = (ox, oy)
            mtype[row, slot] = typ
            m = monsters.get(typ)
            if m:
                hp0[row, slot] = float(m["health"])
                speed[row, slot] = float(m["speed"])
                boxW[row, slot] = float(m["boxWidth"])
                dmg[row, slot] = float(m["damage"])
                direct[row, slot] = 1.0 if m.get("useDirectSteering") else 0.0
                mass[row, slot] = float(m.get("mass", 1.0))
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
        np.zeros((n_envs, M), np.int32),           # type (monsterTypeID, for sprite selection)
        np.ones((n_envs, M), np.float32),          # mass (per-type, for body collision/momentum)
    )


def _pack(arrays, M):
    spawn_tick, off, hp0, speed, boxW, dmg, direct, mtype, mass = arrays
    return dict(M=M, spawn_tick=spawn_tick, offset=off, hp0=hp0,
                speed=speed, boxW=boxW, dmg=dmg, direct=direct, type=mtype, mass=mass)


def _fill_chunk(payload):
    """Worker: fill a contiguous env range into its own small arrays (env e -> seed base_seed+e)."""
    env_lo, env_hi, levels, assign, monsters, base_seed, M = payload
    arrays = _alloc(env_hi - env_lo, M)
    for row, e in enumerate(range(env_lo, env_hi)):
        _fill_env(arrays, row, levels[assign[e]], monsters, base_seed + e, M)
    return env_lo, arrays


def _resolve_workers(workers, n_envs):
    if workers is None or workers <= 0:
        workers = os.cpu_count() or 1
    return max(1, min(workers, n_envs))


def _build_rows(levels, assign, monsters, base_seed, n_envs, M, workers):
    arrays = _alloc(n_envs, M)
    w = _resolve_workers(workers, n_envs)
    if w <= 1 or n_envs < 64:                       # serial: small batch / parity tests
        for e in range(n_envs):
            _fill_env(arrays, e, levels[assign[e]], monsters, base_seed + e, M)
        return arrays
    step = (n_envs + w - 1) // w
    chunks = [(lo, min(lo + step, n_envs), levels, assign, monsters, base_seed, M)
              for lo in range(0, n_envs, step)]
    with ProcessPoolExecutor(max_workers=w) as ex:
        for lo, sub in ex.map(_fill_chunk, chunks):
            n = sub[0].shape[0]
            for dst, src in zip(arrays, sub):
                dst[lo:lo + n] = src
    return arrays


def _arena(levels, assign, n_envs):
    """Per-env arena half-size (from the level each env is assigned)."""
    return np.array([float(levels[assign[e]].get("arena_half", 6000.0)) for e in range(n_envs)], np.float32)


def _rocks(levels, assign, n_envs, K):
    """Per-env static rock array [N,K,4] (x, y, r, shape: 0=circle/1=square half-extent), padded to a common K
    (unused slots -> r 0 = never-collide). Like _arena, rocks are per-MAP, indexed by assign."""
    out = np.zeros((n_envs, max(K, 1), 4), np.float32)
    for e in range(n_envs):
        rk = levels[assign[e]].get("rocks", [])
        if rk:
            arr = np.asarray(rk, np.float32)
            if arr.shape[1] == 3:                      # legacy [x,y,r] -> circles (shape column 0)
                arr = np.pad(arr, ((0, 0), (0, 1)))
            out[e, :arr.shape[0]] = arr
    return out


def _max_rocks(levels):
    return max((len(lv.get("rocks", [])) for lv in levels), default=0)


def build(level, monsters, base_seed, n_envs, cap=512, workers=None):
    M = max(min(level["expected_total"], cap), 1)
    assign = np.zeros(n_envs, np.int32)
    arrays = _build_rows([level], assign, monsters, base_seed, n_envs, M, workers)
    out = _pack(arrays, M)
    out["arena_half"] = _arena([level], assign, n_envs)
    out["rocks"] = _rocks([level], assign, n_envs, _max_rocks([level]))
    return out


def build_multi(levels, monsters, base_seed, n_envs, cap=512, workers=None):
    """Round-robin `levels` across the env batch: env e uses levels[e % L]. Common M = max over
    maps (shorter maps leave the tail as never-spawn). Returns the same dict shape as `build`,
    plus `assign` (per-env level index) for reporting."""
    L = len(levels)
    M = max(max(min(lv["expected_total"], cap) for lv in levels), 1)
    assign = (np.arange(n_envs, dtype=np.int32) % L)
    arrays = _build_rows(levels, assign, monsters, base_seed, n_envs, M, workers)
    out = _pack(arrays, M)
    out["assign"] = assign
    out["arena_half"] = _arena(levels, assign, n_envs)
    out["rocks"] = _rocks(levels, assign, n_envs, _max_rocks(levels))
    return out


def build_eval(levels, monsters, seeds, cap=1024, base_seed=1000, seed_stride=7919):
    """Batched schedule for the (len(levels) x seeds) eval games packed into ONE env batch, so eval
    plays every held-out game in a single vectorized rollout instead of one game at a time. Game
    (map i, seed s) -> env e = i*seeds + s, filled with seed `base_seed + s*seed_stride` so it is
    byte-identical to an independent single-env build() of that map+seed (slot fill is cap-independent;
    shorter maps leave the tail as never-spawn). Returns (sched, real_tot[N], assign[N]); real_tot[e]
    = that game's spawnable-monster count (the per-game "all cleared" threshold), assign[e] = map index.
    The `for e` here is schedule SETUP (config baking, not the per-tick sim)."""
    L, S = len(levels), seeds
    N = L * S
    M = max(max(min(lv["expected_total"], cap) for lv in levels), 1)
    arrays = _alloc(N, M)
    arena = np.empty(N, np.float32)
    real_tot = np.empty(N, np.float32)
    assign = np.empty(N, np.int32)
    for e in range(N):
        li, sd = e // S, e % S
        lv = levels[li]
        _fill_env(arrays, e, lv, monsters, base_seed + sd * seed_stride, M)
        arena[e] = float(lv.get("arena_half", 6000.0))
        real_tot[e] = float(min(max(lv["expected_total"], 1), M))
        assign[e] = li
    out = _pack(arrays, M)
    out["arena_half"] = arena
    out["rocks"] = _rocks(levels, assign, N, _max_rocks(levels))
    return out, real_tot, assign
