"""Ground-unit oracles — unicycle (LaValle 13.16), Helbing social force (Nature 2000 Eq. 1-2),
Tobler hiking factor (NCGIA 93-1). Hand values from SOURCES.md ground-units-terrain §4 + audit."""
import math
import os
import sys

import numpy as np
import torch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from oracles import ground
from world_config_drone import WorldConfig

CFG = WorldConfig()
A_ACC = CFG.sfm_A / CFG.sfm_mass   # Helbing A=2000 N / m=80 kg -> 25.0 m/s^2 accel scale (SOURCES 4.2)


def _one(x):
    return torch.tensor(x, dtype=torch.float64)


def test_unicycle_circle_radius():
    """Constant (v, omega) traces a circle of radius v/omega = 1.5/0.75 = 2.0 (Thrun Eq. 5.5)."""
    v, om, dt = 1.5, 0.75, 0.01
    pos, heading = torch.zeros(2, dtype=torch.float64), _one(0.0)
    n = round(2 * math.pi / (om * dt))                     # ~one full loop (838 steps)
    traj = []
    for _ in range(n):
        pos, heading = ground.unicycle_step(pos, heading, _one(v), _one(om), _one(1.0), dt)
        traj.append(pos)
    traj = torch.stack(traj)
    center = traj.mean(0)                                  # centroid of a uniform full loop = center
    radii = (traj - center).norm(dim=-1)
    assert abs(float(radii.mean()) - 2.0) / 2.0 < 0.02     # radius v/omega within 2%
    assert float(radii.std()) < 1e-3                       # discrete vertices lie on ONE circle
    assert abs(float(heading) - n * om * dt) < 1e-12       # heading integrates exactly


def test_unicycle_straight_and_slope_scaling():
    """omega=0: moves v*dt*T along heading; slope_fac scales distance linearly (Tobler coupling)."""
    p0, th = _one([1.0, -2.0]), _one(0.7)
    p, h = p0.clone(), th.clone()
    for _ in range(40):                                    # T=40 steps, dt=0.05 -> path length 4.0 m
        p, h = ground.unicycle_step(p, h, _one(2.0), _one(0.0), _one(1.0), 0.05)
    # 4*cos(0.7)=3.0593687, 4*sin(0.7)=2.5768707 (closed form v*dt*T along fixed heading)
    assert torch.allclose(p - p0, _one([3.0593687491, 2.5768707490]), atol=1e-9)
    assert float(h) == 0.7                                 # heading untouched when omega=0
    p2 = p0.clone()
    for _ in range(40):
        p2, _ = ground.unicycle_step(p2, th, _one(2.0), _one(0.0), _one(0.5), 0.05)
    assert torch.allclose(p2 - p0, 0.5 * (p - p0), atol=1e-9)   # slope_fac=0.5 halves displacement


def test_unicycle_dt_convergence_richardson():
    """First-order integrator: halving dt halves the endpoint error vs the exact arc (slope ~1)."""
    v, om, T = 1.0, 1.0, 1.0
    exact = _one([math.sin(1.0), 1.0 - math.cos(1.0)])     # x=(v/w)sin(wt), y=(v/w)(1-cos wt)
    errs = []
    for dt in (0.02, 0.01):
        p, h = torch.zeros(2, dtype=torch.float64), _one(0.0)
        for _ in range(round(T / dt)):
            p, h = ground.unicycle_step(p, h, _one(v), _one(om), _one(1.0), dt)
        errs.append(float((p - exact).norm()))
    slope = math.log2(errs[0] / errs[1])
    assert 0.9 < slope < 1.1                               # Richardson: O(dt) global error


def test_tobler_factor_values():
    S = _one([0.0, 0.10, -0.05, -0.10])
    f = ground.tobler_factor(S)
    assert float(f[0]) == 1.0                              # flat: W(0)/W(0) exactly
    assert abs(float(f[1]) - 0.7046881) < 1e-6             # audit value: exp(-0.525)/exp(-0.175)=exp(-0.35)
    assert abs(float(f[2]) - 1.1912462) < 1e-6             # global max at S=-0.05: exp(0.175)
    assert abs(float(f[3]) - 1.0) < 1e-12                  # W(-0.10)=W(0) mirror (SOURCES 4.3)
    # symmetry about S=-0.05: W(S) = W(-0.10-S), and strictly decreasing for S > -0.05
    assert torch.allclose(ground.tobler_factor(_one(0.03)), ground.tobler_factor(_one(-0.13)))
    grid = ground.tobler_factor(torch.linspace(-0.05, 0.5, 30, dtype=torch.float64))
    assert bool((grid[1:] < grid[:-1]).all())


def test_social_force_two_agent_symmetry():
    """Symmetric pair at rest, no drive: repulsion is equal-and-opposite (Newton pair antisymmetry)."""
    pos = _one([[-0.5, 0.0], [0.5, 0.0]])                  # d = 1.0 m
    zero = torch.zeros_like(pos)
    acc = ground.social_force(pos, zero, zero, _one([1.0, 1.0]),
                              A_ACC, CFG.sfm_B, CFG.soldier_tau, CFG.soldier_radius)
    # (2000/80)*exp((2*0.35 - 1.0)/0.08) = 25*exp(-3.75) = 0.5879436 m/s^2 (Helbing Eq. 2 / WorldConfig)
    assert torch.allclose(acc[0], _one([-0.5879436464, 0.0]), atol=1e-7)
    assert torch.allclose(acc[0], -acc[1], atol=1e-12)     # momentum invariant (SOURCES 4.2)


def test_social_force_dead_agents():
    pos = _one([[-0.5, 0.0], [0.5, 0.0], [-0.6, 0.0]])     # agent 2 dead, right next to agent 0
    zero = torch.zeros_like(pos)
    des = _one([[0.0, 0.0], [0.0, 0.0], [1.0, 0.0]])       # dead agent even WANTS to move
    acc = ground.social_force(pos, zero, des, _one([1.0, 1.0, 0.0]),
                              A_ACC, CFG.sfm_B, CFG.soldier_tau, CFG.soldier_radius)
    assert torch.all(acc[2] == 0.0)                        # dead -> zero accel despite desired_vel
    acc2 = ground.social_force(pos[:2], zero[:2], zero[:2], _one([1.0, 1.0]),
                               A_ACC, CFG.sfm_B, CFG.soldier_tau, CFG.soldier_radius)
    assert torch.allclose(acc[0], acc2[0], atol=1e-12)     # dead neighbor exerts no repulsion


def test_social_force_driving_term_alone():
    """Single agent, no neighbors: accel = (v0 e - v)/tau (Helbing Eq. 1 driving term)."""
    pos, vel = _one([[0.0, 0.0]]), _one([[0.5, -0.25]])
    des = _one([[1.5, 0.0]])
    acc = ground.social_force(pos, vel, des, _one([1.0]),
                              A_ACC, CFG.sfm_B, CFG.soldier_tau, CFG.soldier_radius)
    # ((1.5-0.5)/0.5, (0+0.25)/0.5) = (2.0, 0.5), tau=0.5 (Helbing 2000)
    assert torch.allclose(acc, _one([[2.0, 0.5]]), atol=1e-12)


def test_social_force_wall_term():
    """SDF wall push (Helbing Eq. 3 exponential term): A*exp((r - sdf)/B) along +grad."""
    pos = _one([[0.0, 0.0]])
    zero = torch.zeros_like(pos)
    acc = ground.social_force(pos, zero, zero, _one([1.0]),
                              A_ACC, CFG.sfm_B, CFG.soldier_tau, CFG.soldier_radius,
                              obst_sdf=_one([0.5]), obst_grad=_one([[0.0, 1.0]]))
    # 25*exp((0.35-0.5)/0.08) = 25*exp(-1.875) = 3.8338742 m/s^2, pushed along +y gradient
    assert torch.allclose(acc, _one([[0.0, 3.8338741711]]), atol=1e-7)


def test_batched_vectorization():
    """[P=2,N=3] unicycle and [P=2,E=4] social force: batch slice == single-element call."""
    g = torch.Generator().manual_seed(0)
    pos = torch.randn(2, 3, 2, generator=g, dtype=torch.float64)
    hd = torch.randn(2, 3, generator=g, dtype=torch.float64)
    v = torch.rand(2, 3, generator=g, dtype=torch.float64)
    om = torch.randn(2, 3, generator=g, dtype=torch.float64)
    sf = torch.rand(2, 3, generator=g, dtype=torch.float64)
    p_b, h_b = ground.unicycle_step(pos, hd, v, om, sf, 0.05)
    assert p_b.shape == (2, 3, 2) and h_b.shape == (2, 3)
    p_1, h_1 = ground.unicycle_step(pos[1, 2], hd[1, 2], v[1, 2], om[1, 2], sf[1, 2], 0.05)
    assert torch.allclose(p_b[1, 2], p_1, atol=1e-12) and torch.allclose(h_b[1, 2], h_1, atol=1e-12)
    sp = torch.randn(2, 4, 2, generator=g, dtype=torch.float64)
    sv = torch.randn(2, 4, 2, generator=g, dtype=torch.float64) * 0.3
    sd = torch.randn(2, 4, 2, generator=g, dtype=torch.float64)
    al = _one([[1.0, 1.0, 0.0, 1.0], [1.0, 1.0, 1.0, 1.0]])
    a_b = ground.social_force(sp, sv, sd, al, A_ACC, CFG.sfm_B, CFG.soldier_tau, CFG.soldier_radius)
    assert a_b.shape == (2, 4, 2)
    a_0 = ground.social_force(sp[0], sv[0], sd[0], al[0],
                              A_ACC, CFG.sfm_B, CFG.soldier_tau, CFG.soldier_radius)
    assert torch.allclose(a_b[0], a_0, atol=1e-12)
