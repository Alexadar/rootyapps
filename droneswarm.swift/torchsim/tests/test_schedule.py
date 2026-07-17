"""Schedule pregen — distribution ranges, per-env-seed byte identity (batch == N singles), eval-seed
disjointness, and wind/AA-table determinism (froggo test_schedule idiom)."""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import schedule_drone as S
from world_config_drone import WorldConfig

CFG = WorldConfig()
D, E, O, T = 16, 12, 24, 300


def _build(n, seed=0):
    return S.build(CFG, n, D, E, O, T, base_seed=seed)


def test_shapes_and_ranges():
    b = _build(3)
    assert b["hf"].shape == (3, CFG.terrain_grid, CFG.terrain_grid)
    assert b["obst"].shape == (3, O, 7)
    assert b["e_type"].shape == (3, E) and b["gust"].shape == (3, T, 3)
    assert b["aa_roll"].shape == (3, T, E)
    # heightfield within [0, amp]
    assert b["hf"].min() >= -1e-4 and b["hf"].max() <= CFG.terrain_amp + 1e-3
    # obstacles + enemies inside the arena
    assert np.all(np.abs(b["obst"][..., :2]) <= CFG.arena_half)
    assert np.all(np.abs(b["e_pos0"]) <= CFG.arena_half)
    # AA rolls are uniform(0,1)
    assert b["aa_roll"].min() >= 0.0 and b["aa_roll"].max() <= 1.0
    # enemy types are 0/1 with the fixed tank split
    assert set(np.unique(b["e_type"]).tolist()) <= {0.0, 1.0}
    assert int((b["e_type"] == 1.0).sum(1)[0]) == E // 3


def test_batch_equals_single_bit_identity():
    """env e of an N-build must be byte-identical to a single build at the same seed (base_seed+e)."""
    big = _build(4, seed=0)
    for e in range(4):
        one = _build(1, seed=e)                                   # base_seed=e -> its env0 seeded e == big row e
        for k in ("hf", "obst", "e_type", "e_pos0", "e_head0", "base_pos",
                  "spawn_tick", "spawn_off", "mean_wind", "gust", "aa_roll"):
            assert np.array_equal(big[k][e], one[k][0]), f"{k} row {e} not bit-identical"


def test_seed_determinism():
    a = _build(2, seed=5)
    b = _build(2, seed=5)
    for k in ("hf", "gust", "aa_roll", "e_pos0"):
        assert np.array_equal(a[k], b[k]), f"{k} not deterministic under fixed seed"


def test_eval_seed_disjoint_from_train():
    """Eval seeds start at 10_000 + s*7919 (prime stride) — disjoint from any small-int train seed,
    so eval scenes are genuinely held out."""
    ev = S.build_eval(CFG, 3, D, E, O, T)
    tr = _build(64, seed=0)                                       # train seeds 0..63
    # a held-out eval scene should not coincide with any training scene's heightfield
    for s in range(3):
        assert not any(np.array_equal(ev["hf"][s], tr["hf"][e]) for e in range(64))


def test_gust_is_stationary_turbulence():
    """The pregenerated gust has meaningful, bounded amplitude (a real turbulence signal, not noise
    spikes or a dead flat line)."""
    b = _build(1, seed=1)
    g = b["gust"][0]
    assert np.all(np.isfinite(g))
    assert 0.02 < g.std() < 2.0                                  # turbulence, not calm and not a storm
    # temporally correlated (lag-1 autocorrelation high -> smooth gusts, not white noise)
    u = g[:, 0]
    assert np.corrcoef(u[:-1], u[1:])[0, 1] > 0.8
