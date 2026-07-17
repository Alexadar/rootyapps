"""Oracle acceptance: aero — quadratic body drag + Cheeseman-Bennett ground effect.

Hand values from oracles/SOURCES.md report 'aero-drag-groundeffect': T1 (zero-airspeed => zero
drag), T2 (tanh free-fall closed form, HyperPhysics), T3 (C&B hover ratios 16/15 etc.), T5
(Faessler linear rotor-drag accel -0.544), T6 (Chen & Bai quadratic value 1.285227 m/s^2);
terminal velocity ~22 m/s from WorldConfig (drag_quad doc: v_t = sqrt(a_lat_max/drag_quad)).
"""
import math
import os
import sys

import numpy as np
import torch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from oracles import aero
from world_config_drone import WorldConfig

CFG = WorldConfig()


def test_drag_opposes_air_velocity_and_is_odd():
    torch.manual_seed(0)
    v = torch.randn(64, 3) * 10.0
    a = aero.drag_accel(v, CFG.drag_quad)
    assert float((a * v).sum(-1).max()) < 0.0          # power a.v < 0: drag only dissipates (SOURCES T5 invariant)
    assert torch.allclose(aero.drag_accel(-v, CFG.drag_quad), -a, atol=1e-6, rtol=0)  # odd in v_air


def test_drag_zero_at_zero_airspeed():
    a = aero.drag_accel(torch.zeros(5, 3), CFG.drag_quad, drag_lin=0.3)
    assert torch.all(a == 0.0)                          # exactly 0: both terms are odd in v_air (SOURCES T1)


def test_drag_hand_magnitudes():
    # quadratic: |a| = c2*|v|^2; v=(10,0,0), c2=0.046 (WorldConfig drag_quad) -> a_x = -4.6 m/s^2
    a = aero.drag_accel(torch.tensor([[10.0, 0.0, 0.0]]), 0.046)
    assert abs(float(a[0, 0]) + 4.6) < 1e-5 and float(a[0, 1]) == 0.0 and float(a[0, 2]) == 0.0
    # linear rotor drag (GPD-parity knob): v=(1,0,0), d_x=0.544 1/s -> a=-0.544 (Faessler RA-L 2018, SOURCES T5)
    a = aero.drag_accel(torch.tensor([[1.0, 0.0, 0.0]]), 0.0, drag_lin=0.544)
    assert abs(float(a[0, 0]) + 0.544) < 1e-6
    # published set: Chen & Bai 2022, c2 = 0.5*rho*CdA/m = 0.5*1.225*3.265e-2/0.389; |v|=5
    # -> |a| = c2*25 = 1.285227 m/s^2 (SOURCES T6)
    c2 = 0.5 * 1.225 * 3.265e-2 / 0.389
    a = aero.drag_accel(torch.tensor([[0.0, 5.0, 0.0]]), c2)
    assert abs(float(a[0, 1]) + 1.285227) < 1e-5


def test_terminal_velocity_matches_worldconfig():
    # closed form: drag_quad*v_t^2 = a_lat_max = g*sqrt(T2W^2-1) -> v_t = sqrt(a_lat_max/drag_quad)
    # = sqrt(9.81*sqrt(5.25)/0.046) = 22.105 m/s; WorldConfig documents ~22 (drone_speed_max)
    a_lat_max = CFG.gravity * math.sqrt(CFG.drone_t2w ** 2 - 1.0)   # 22.47753 m/s^2
    v_t = math.sqrt(a_lat_max / CFG.drag_quad)                       # 22.10525 m/s
    assert abs(v_t - CFG.drone_speed_max) < 0.25
    a = aero.drag_accel(torch.tensor([[v_t, 0.0, 0.0]]), CFG.drag_quad)
    assert abs(float(-a[0, 0]) - a_lat_max) < 1e-4                   # drag exactly balances a_lat_max at v_t


def test_ground_effect_cheeseman_bennett_hand_values():
    R = CFG.rotor_radius
    f = aero.ground_effect_factor(torch.tensor([R, 2 * R, 4 * R]), R, ge_coef=1.0)
    # C&B hover 1/(1-(R/4z)^2): z=R -> 16/15=1.0666667; z=2R -> 1.015873; z=4R -> 1.003922 (SOURCES T3)
    expected = torch.tensor([16.0 / 15.0, 1.0 / (1.0 - 1.0 / 64.0), 1.0 / (1.0 - 1.0 / 256.0)])
    assert torch.allclose(f, expected, atol=1e-5, rtol=0)
    assert abs(float(f[0]) - 1.0666667) < 1e-5                       # 1/(1-(1/4)^2) = 1/0.9375
    # altitude floor: any z <= 0.35R clamps -> 1/(1-(1/1.4)^2) = 2.0416667 (pole at z=R/4 removed)
    f0 = aero.ground_effect_factor(torch.tensor([0.0, 0.01 * R]), R)
    assert torch.allclose(f0, torch.full((2,), 2.0416667), atol=1e-5, rtol=0)


def test_ground_effect_limits_and_knobs():
    R = CFG.rotor_radius
    f = aero.ground_effect_factor(torch.linspace(0.0, 100.0 * R, 400), R)
    assert float(f.min()) >= 1.0                        # augmentation convention: multiplier >= 1 always
    assert abs(float(f[-1]) - 1.0) < 1e-3               # -> 1 far from ground: (1/400)^2 = 6.25e-6 residual
    assert float((f[1:] - f[:-1]).max()) <= 1e-6        # monotone non-increasing with altitude
    # ge_coef blends toward 1: at z=R factor = 1 + 0.5*(16/15 - 1) = 1.0333333
    f_half = aero.ground_effect_factor(torch.tensor([R]), R, ge_coef=0.5)
    assert abs(float(f_half[0]) - (1.0 + 0.5 * (16.0 / 15.0 - 1.0))) < 1e-6
    # ge_max caps: floor_frac=0.26 makes the floored ratio 1/(1-(1/1.04)^2) = 13.25 -> clamped to 4
    f_cap = aero.ground_effect_factor(torch.tensor([0.0]), R, floor_frac=0.26, ge_max=4.0)
    assert float(f_cap[0]) == 4.0


def test_batched_shapes_and_slice_equality():
    torch.manual_seed(1)
    v = torch.randn(2, 3, 4, 3) * 8.0                   # [P=2, N=3, K=4, 3] family convention
    a = aero.drag_accel(v, CFG.drag_quad)
    assert a.shape == (2, 3, 4, 3)
    assert torch.allclose(a[1, 2, 3], aero.drag_accel(v[1, 2, 3], CFG.drag_quad), atol=1e-7, rtol=0)
    z = torch.rand(2, 3, 4) * 2.0                       # [P, N, K] heights
    f = aero.ground_effect_factor(z, CFG.rotor_radius)
    assert f.shape == (2, 3, 4)
    assert torch.allclose(f[0, 1, 2], aero.ground_effect_factor(z[0, 1, 2], CFG.rotor_radius),
                          atol=1e-7, rtol=0)


def test_freefall_dt_convergence_tanh_closed_form():
    # 1-D free fall with quadratic drag: v(t) = v_t*tanh(g*t/v_t), v_t = sqrt(g/c2) = 14.6035 m/s
    # (HyperPhysics quadvfall via SOURCES T2); v(1s) = 8.559606 m/s. Forward Euler is O(dt):
    # halving dt must ~halve the error (Richardson slope ~1). Loops are test-side only.
    g, c2, t_end = CFG.gravity, CFG.drag_quad, 1.0
    v_t = math.sqrt(g / c2)
    v_exact = v_t * math.tanh(g * t_end / v_t)          # 8.559606 m/s
    g_vec = torch.tensor([0.0, 0.0, -g], dtype=torch.float64)
    errs = []
    for dt in (0.01, 0.005, 0.0025):
        v = torch.zeros(1, 3, dtype=torch.float64)
        for _ in range(round(t_end / dt)):
            v = v + dt * (aero.drag_accel(v, c2) + g_vec)
        errs.append(abs(float(-v[0, 2]) - v_exact))
    assert errs[0] < 5e-2                               # dt=0.01 already sub-0.6% of v_t
    assert 0.35 < errs[1] / errs[0] < 0.65              # error ratio ~0.5 per halving
    assert 0.35 < errs[2] / errs[1] < 0.65
