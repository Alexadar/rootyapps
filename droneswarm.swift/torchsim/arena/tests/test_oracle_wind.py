"""Wind oracle tests — Dryden OU series (SOURCES wind T2/T3/T4/T11), audit spatial-corr oracle
rho(20 m, L_u=94.73 m)=0.8097, log-shear hand values (SOURCES T6), wind_at broadcast."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import numpy as np
import torch

from common.oracles.wind import dryden_series_np, dryden_length_scales, shear_factor, wind_at
from world_config_drone import WorldConfig

DT, V, SIG3, L3 = 1.0 / 50.0, 8.0, [1.0, 1.0, 1.0], [60.0, 60.0, 30.0]  # WorldConfig-like params


def test_dryden_recursion_identity_and_v_floor():
    # Implementation identity (SOURCES T2): replay the same seed's white noise through a hand AR(1)
    # x[k] = phi*x[k-1] + sigma*sqrt(1-phi^2)*eta[k]  (exact-OU, Gillespie 1996 via SOURCES [S12]).
    # V_mean=1.0 < v_floor=2.0 exercises the floor: phi must use V=2.0.
    T = 200
    out = dryden_series_np(np.random.default_rng(3), T, DT, 1.0, SIG3, L3, v_floor=2.0)
    white = np.random.default_rng(3).standard_normal((T, 3))  # the function's only rng call
    phi = np.exp(-DT * 2.0 / np.asarray(L3))                  # floored V=2.0
    sig = np.asarray(SIG3) * np.sqrt(1.0 - phi * phi)
    x = np.zeros(3)
    for k in range(T):
        x = phi * x + sig * white[k]
        assert np.allclose(out[k], x, atol=1e-5)              # float32 output vs float64 hand loop


def test_dryden_stationary_variance():
    # Exact-OU discretization => stationary Var = sigma^2 exactly (SOURCES T3(ii); the Euler AR(1)
    # alternative would inflate it by 1/(1 - dt*V/(2L))). Fixed seed => deterministic sample.
    s = dryden_series_np(np.random.default_rng(0), 400000, DT, V, SIG3, L3)
    var = s.astype(np.float64).var(axis=0)
    assert np.all(np.abs(var - 1.0) < 0.05)                   # sigma^2 = 1, within 5%


def test_dryden_lag1_autocorrelation():
    # AR(1) coefficient phi = exp(-dt*V/L_u) = exp(-0.16/60) = 0.9973369 (SOURCES T4 form).
    s = dryden_series_np(np.random.default_rng(0), 200000, DT, V, SIG3, L3)
    x = s[:, 0].astype(np.float64)
    assert abs(np.corrcoef(x[:-1], x[1:])[0, 1] - 0.9973369) < 0.02


def test_spatial_correlation_audit_oracle():
    # Audit oracle: frozen-turbulence spatial corr rho(r) = exp(-r/L); with the MIL-F-8785C
    # h=50 ft, W20=20 ft/s scale L_u = 310.79 ft = 94.73 m (SOURCES T1), rho(20 m) = 0.8097.
    assert abs(np.exp(-20.0 / 94.73) - 0.8097) < 1e-4
    # Series realization of the same number: by Taylor r = V*tau => lag = r/(V*dt) = 125 ticks.
    s = dryden_series_np(np.random.default_rng(0), 200000, DT, V, [1, 1, 1], [94.73, 94.73, 94.73])
    x = s[:, 0].astype(np.float64)
    assert abs(np.corrcoef(x[:-125], x[125:])[0, 1] - 0.8097) < 0.05


def test_dryden_determinism():
    # SOURCES T11: same seed => bitwise-equal series (zero-runtime-RNG determinism relies on this).
    a = dryden_series_np(np.random.default_rng(7), 1000, DT, V, SIG3, L3)
    b = dryden_series_np(np.random.default_rng(7), 1000, DT, V, SIG3, L3)
    c = dryden_series_np(np.random.default_rng(8), 1000, DT, V, SIG3, L3)
    assert np.array_equal(a, b) and not np.array_equal(a, c) and np.isfinite(a).all()


def test_dryden_length_scales_order():
    # [L_u, L_v, L_w] = [L_uv, L_uv, L_w] — horizontal scales for u,v; vertical for w.
    assert np.array_equal(dryden_length_scales(50.0, 30.0, 60.0), [60.0, 60.0, 30.0])


def test_shear_factor_hand_values():
    # SOURCES T6 (z0=0.03 m, z_ref=10 m): s(2) = ln(2/.03)/ln(10/.03) = 4.199705/5.809143 = 0.722947;
    # s(50) = 7.418581/5.809143 = 1.277053; forest z0=1: s(2) = ln2/ln10 = 0.301030; s(z_ref) = 1.
    s = shear_factor(torch.tensor([2.0, 50.0, 10.0]), 0.03, 10.0)
    assert torch.allclose(s, torch.tensor([0.722947, 1.277053, 1.0]), atol=1e-5)
    assert abs(float(shear_factor(torch.tensor(2.0), 1.0, 10.0)) - 0.301030) < 1e-5
    cfg = WorldConfig()
    assert abs(float(shear_factor(torch.tensor(cfg.wind_z_ref), cfg.wind_z0, cfg.wind_z_ref)) - 1.0) < 1e-6


def test_shear_factor_monotone_and_floor():
    # Monotone increasing in z; below z0 the clamp z >= 1.001*z0 pins the factor near
    # ln(1.001)/ln(z_ref/z0) = 9.995e-4/3.401197 = 2.9387e-4 (z0=0.2, z_ref=6, WorldConfig values).
    z = torch.tensor([0.5, 1.0, 2.0, 6.0, 20.0])
    s = shear_factor(z, 0.2, 6.0)
    assert torch.all(s[1:] > s[:-1])
    under = float(shear_factor(torch.tensor(0.05), 0.2, 6.0))
    assert 0.0 <= under and abs(under - 2.9387e-4) < 1e-6


def test_wind_at_shape_broadcast_and_hand_value():
    # wind_at(gust_t[N,3], mean_wind[N,3], z_agl[P,N,D]) -> [P,N,D,3]; total = (mean+gust)*shear(z).
    P, N, D = 2, 3, 4
    z0, z_ref = 0.2, 6.0                                       # WorldConfig wind_z0 / wind_z_ref
    g = torch.arange(N * 3, dtype=torch.float32).reshape(N, 3) * 0.1
    m = torch.tensor([[4.0, 0.0, 0.0], [0.0, -2.0, 0.0], [1.0, 1.0, 0.0]])
    z = torch.rand(P, N, D) * 20.0 + 0.5
    w = wind_at(g, m, z, z0, z_ref)
    assert w.shape == (P, N, D, 3)
    for p in range(P):                                        # vectorization: each element == scalar formula
        for n in range(N):
            for d in range(D):
                sf = float(shear_factor(z[p, n, d], z0, z_ref))
                assert torch.allclose(w[p, n, d], (m[n] + g[n]) * sf, atol=1e-6)
    # Single-slice call equals the batched result at that index.
    assert torch.allclose(wind_at(g, m, z[0:1], z0, z_ref), w[0:1], atol=0.0, rtol=0.0)
    # Hand value: mean=(4,0,0), gust=(1,-1,0.5) at z=z_ref => shear=1 => (5,-1,0.5) exactly.
    w1 = wind_at(torch.tensor([[1.0, -1.0, 0.5]]), torch.tensor([[4.0, 0.0, 0.0]]),
                 torch.full((1, 1, 1), z_ref), z0, z_ref)
    assert torch.allclose(w1[0, 0, 0], torch.tensor([5.0, -1.0, 0.5]), atol=1e-6)
