"""Hunt-Crossley penalty contact oracle (SOURCES.md gap G1) — hand values + invariants + dt-convergence."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import numpy as np
import torch

from oracles.contact import hunt_crossley_force, restitution_from_params
from world_config_drone import WorldConfig

K, LAM = 800.0, 40.0  # WorldConfig hc_stiffness / hc_damping (design values, world_config_drone.py)


def test_zero_force_outside_contact():
    # delta <= 0 => F = 0 exactly, regardless of delta_dot (contact law is one-sided)
    for d in (-0.5, -1e-9, 0.0):
        for dd in (-10.0, 0.0, 10.0):
            f = hunt_crossley_force(torch.tensor(d), torch.tensor(dd), K, LAM)
            assert float(f) == 0.0, (d, dd, float(f))


def test_hand_value_hc1975():
    # F = k*d^n + lam*d^n*ddot; d=0.1 => d^1.5 = 0.0316227766017 (=10^-1.5)
    # elastic: 800*0.0316227766017 = 25.2982212813; damping: 40*0.0316227766017*0.5 = 0.6324555320
    f = hunt_crossley_force(torch.tensor(0.1, dtype=torch.float64), torch.tensor(0.5, dtype=torch.float64), K, LAM)
    assert abs(float(f) - 25.930676813380712) < 1e-9  # sum of the two hand terms above
    f0 = hunt_crossley_force(torch.tensor(0.1, dtype=torch.float64), torch.tensor(0.0, dtype=torch.float64), K, LAM)
    assert abs(float(f0) - 25.298221281347036) < 1e-9  # pure Hertzian spring term k*d^1.5
    # mild separation ddot=-0.5: damping subtracts, still positive => NOT clamped
    fm = hunt_crossley_force(torch.tensor(0.1, dtype=torch.float64), torch.tensor(-0.5, dtype=torch.float64), K, LAM)
    assert abs(float(fm) - 24.665765749313360) < 1e-9  # 25.2982212813 - 0.6324555320


def test_non_adhesive_fast_separation():
    # ddot=-100: raw f = 25.298 + 40*0.0316*(-100) = -101.19 N => clamped to 0 (no sticking)
    f = hunt_crossley_force(torch.tensor(0.1), torch.tensor(-100.0), K, LAM)
    assert float(f) == 0.0
    ddots = torch.linspace(-50.0, 5.0, 111, dtype=torch.float64)
    fs = hunt_crossley_force(torch.full_like(ddots, 0.1), ddots, K, LAM)
    assert torch.all(fs >= 0.0)  # never adhesive at any separation rate


def test_monotone_in_penetration():
    # F strictly increasing in delta for fixed approach rate (both terms scale with d^n)
    ds = torch.linspace(1e-4, 0.5, 50, dtype=torch.float64)
    for dd in (0.0, 0.3):
        fs = hunt_crossley_force(ds, torch.full_like(ds, dd), K, LAM)
        assert torch.all(fs[1:] > fs[:-1]), dd


def test_continuous_at_touchdown():
    # H-C selling point vs Kelvin-Voigt: damping ~ d^n, so F -> 0 as d -> 0+ even at high ddot.
    # d=1e-8, ddot=10: F = 800e-12 + 40e-12*10 = 1.2e-9 N (no impulsive jump at contact onset)
    f = hunt_crossley_force(torch.tensor(1e-8, dtype=torch.float64), torch.tensor(10.0, dtype=torch.float64), K, LAM)
    assert 0.0 < float(f) < 1e-8


def test_restitution_closed_form():
    # e = 1 - (2/3)(lam/k)v (Hunt & Crossley 1975 low-loss expansion, SOURCES G1)
    # k=800, lam=40, v=0.5: e = 1 - (2/3)*0.05*0.5 = 0.9833333333
    assert abs(float(restitution_from_params(K, LAM, 0.5)) - 0.9833333333333333) < 1e-12
    assert float(restitution_from_params(K, 0.0, 3.0)) == 1.0  # lam=0 => perfectly elastic
    assert float(restitution_from_params(K, LAM, 1.0)) < float(restitution_from_params(K, LAM, 0.5))  # e falls with v


def test_worldconfig_params():
    cfg = WorldConfig()
    assert cfg.hc_stiffness == 800.0  # design contact stiffness (world_config_drone.py)
    assert cfg.hc_damping == 40.0     # design contact damping
    assert cfg.hc_exponent == 1.5     # Hertzian sphere exponent (Hunt-Crossley 1975)
    # config restitution at v=1 m/s: 1 - (2/3)*(40/800) = 0.9666666667
    e = float(restitution_from_params(cfg.hc_stiffness, cfg.hc_damping, 1.0))
    assert abs(e - 0.9666666666666667) < 1e-12


def test_batched_matches_single():
    # family [P=2, N=3, K=4] convention: elementwise law, batched == per-element
    d = torch.linspace(-0.05, 0.15, 24, dtype=torch.float64).reshape(2, 3, 4)
    dd = torch.linspace(-2.0, 2.0, 24, dtype=torch.float64).reshape(2, 3, 4)
    out = hunt_crossley_force(d, dd, K, LAM)
    assert out.shape == (2, 3, 4)
    for p in range(2):
        for n in range(3):
            for k in range(4):
                single = hunt_crossley_force(d[p, n, k], dd[p, n, k], K, LAM)
                assert torch.allclose(out[p, n, k], single, atol=0.0, rtol=0.0), (p, n, k)


def _bounce_restitution(dt, v0=0.5, m=1.0):
    """1-D point mass into a wall at x=0 (delta=-x, ddot=-v), semi-implicit Euler on the oracle force."""
    x, v = 0.0, -v0
    for _ in range(int(1.0 / dt)):  # contact lasts ~0.28 s; 1 s is a hard cap
        f = float(hunt_crossley_force(torch.tensor(-x, dtype=torch.float64),
                                      torch.tensor(-v, dtype=torch.float64), K, LAM))
        v += (f / m) * dt
        x += v * dt
        if x >= 0.0 and v > 0.0:
            return v / v0  # rebound speed is exact after separation (F=0), so e is quantization-free
    raise AssertionError("no rebound")


def test_dt_convergence_restitution():
    # Richardson: semi-implicit Euler is O(dt) globally => halving dt halves the error (slope ~1)
    e_ref = _bounce_restitution(2e-5)                      # fine reference, 40x below coarse
    # low-loss closed form at v=0.5: e = 0.9833333 (test_restitution_closed_form); sim must land near it
    assert abs(e_ref - 0.9833333333333333) < 0.01
    err1 = abs(_bounce_restitution(8e-4) - e_ref)
    err2 = abs(_bounce_restitution(4e-4) - e_ref)
    slope = float(np.log2(err1 / err2))
    assert 0.6 < slope < 1.4, (err1, err2, slope)  # first-order convergence, catches O(1) integrator bugs
