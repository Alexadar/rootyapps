"""Quadrotor oracle acceptance — CTBR Level-A quad_step vs SOURCES quadrotor-ctbr closed forms:
hover fixed point (T1), symplectic free-fall recursion (T2), fixed-axis rotation exactness (T3),
rate-lag step response (T8 audit value), quat norm (T4), dt-Richardson slope, batch = single."""
import math
import os
import sys

import numpy as np
import torch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from common.oracles import quadrotor as Q
from world_config_drone import WorldConfig

CFG = WorldConfig()
DT, G, M = CFG.dt, CFG.gravity, CFG.drone_mass   # 0.02 s, 9.81 m/s^2, 0.65 kg
F64 = torch.float64


def _state():
    return (torch.zeros(3, dtype=F64), torch.zeros(3, dtype=F64),
            torch.tensor([1.0, 0.0, 0.0, 0.0], dtype=F64), torch.zeros(3, dtype=F64))


def _step(pos, vel, quat, omega, thrust, omega_cmd, drag_quad=CFG.drag_quad,
          tau=CFG.tau_omega, dt=DT):
    z3, one = torch.zeros(3, dtype=F64), torch.tensor(1.0, dtype=F64)
    return Q.quad_step(pos, vel, quat, omega, torch.tensor(thrust, dtype=F64), omega_cmd,
                       z3, one, M, tau, drag_quad, CFG.drag_lin, G, dt)


def test_hover_fixed_point():
    # SOURCES T1: thrust = m*g = 0.65*9.81 = 6.3765 N cancels gravity exactly; v_air=0 => drag=0.
    pos, vel, quat, omega = _state()
    pos[2] = 10.0
    for _ in range(200):   # 4 s of sim
        pos, vel, quat, omega = _step(pos, vel, quat, omega, M * G, torch.zeros(3, dtype=F64))
    assert abs(float(pos[2]) - 10.0) < 1e-6 and float(vel.norm()) < 1e-6
    assert torch.allclose(quat, torch.tensor([1.0, 0, 0, 0], dtype=F64), atol=1e-9)


def test_free_fall_symplectic_recursion():
    # SOURCES T2 closed form of v-=g*dt; z+=v*dt: z_N = z0 - g*dt^2*N(N+1)/2, v_N = -g*N*dt.
    # N=50, dt=0.02 (t=1 s): z = 10 - 9.81*4e-4*1275 = 4.99690, v = -9.81. Drag off to isolate.
    pos, vel, quat, omega = _state()
    pos[2] = 10.0
    for _ in range(50):
        pos, vel, quat, omega = _step(pos, vel, quat, omega, 0.0, torch.zeros(3, dtype=F64),
                                      drag_quad=0.0)
    assert abs(float(vel[2]) + 9.81) < 1e-12                       # -g*N*dt = -9.81 exactly
    assert abs(float(pos[2]) - (10.0 - G * DT * DT * 50 * 51 / 2)) < 1e-12   # 4.99690
    # symplectic differs from continuous 10-0.5*g*t^2 = 5.095 by exactly g*dt*t/2 = 0.0981
    assert abs((10.0 - 0.5 * G * 1.0**2) - float(pos[2]) - G * DT * 1.0 / 2) < 1e-12
    assert float(vel[0]) == 0.0 and float(vel[1]) == 0.0           # horizontal momentum invariant


def test_constant_yaw_rate_rotates_quat():
    # SOURCES T3 / Sola Eq.(228-229): fixed-axis zeroth-order integration is EXACT for any dt.
    # tau -> 0 (alpha underflows to 0) => omega tracks cmd instantly; w=pi/2 for 1 s => yaw=pi/2.
    pos, vel, quat, omega = _state()
    cmd = torch.tensor([0.0, 0.0, math.pi / 2], dtype=F64)
    for _ in range(50):
        pos, vel, quat, omega = _step(pos, vel, quat, omega, M * G, cmd, tau=1e-9)
    # q = [cos(pi/4), 0, 0, sin(pi/4)] = [0.7071068, 0, 0, 0.7071068]
    assert torch.allclose(quat, torch.tensor([math.cos(math.pi / 4), 0, 0,
                                              math.sin(math.pi / 4)], dtype=F64), atol=1e-9)
    yaw = 2.0 * math.atan2(float(quat[3]), float(quat[0]))
    assert abs(yaw - math.pi / 2) < 1e-9


def test_rate_lag_step_response_T8():
    # SOURCES audit of T8: omega_x(2*tau) = pi*(1-e^-2) = 2.7163 (quoted rounded; exact 2.7164243).
    # tau=cfg 0.03 s => 2*tau = 0.06 s = exactly 3 ticks; ZOH update is exact at any dt.
    pos, vel, quat, omega = _state()
    cmd = torch.tensor([math.pi, 0.0, 0.0], dtype=F64)
    prev = 0.0
    for k in range(20):
        pos, vel, quat, omega = _step(pos, vel, quat, omega, M * G, cmd)
        if k == 2:   # after 3 steps: t = 3*0.02 = 0.06 = 2*tau_omega
            assert abs(float(omega[0]) - math.pi * (1.0 - math.exp(-2.0))) < 1e-12
            assert abs(float(omega[0]) - 2.7163) < 1e-3            # SOURCES audit figure
        assert prev - 1e-12 <= float(omega[0]) <= math.pi + 1e-12  # monotone, never overshoots
        prev = float(omega[0])


def test_full_thrust_climbs():
    # WorldConfig derived t_max = T2W*m*g = 2.5*0.65*9.81 = 15.94125 N (published param check).
    assert abs(CFG.drone_t_max - 2.5 * 0.65 * 9.81) < 1e-12
    pos, vel, quat, omega = _state()
    pos, vel, quat, omega = _step(pos, vel, quat, omega, CFG.drone_t_max, torch.zeros(3, dtype=F64))
    # first step from rest (drag sees v=0): v_z = (T2W-1)*g*dt = 1.5*9.81*0.02 = 0.29430
    assert abs(float(vel[2]) - 0.29430) < 1e-12
    assert abs(float(pos[2]) - 0.29430 * DT) < 1e-12               # semi-implicit: p uses NEW v


def test_quat_stays_unit():
    # SOURCES T4 / Sola 4.6: product of unit quats stays unit (+ renorm) — random tumbling.
    torch.manual_seed(0)
    pos, vel, quat, omega = _state()
    for _ in range(2000):
        cmd = (torch.rand(3, dtype=F64) - 0.5) * 40.0              # U(-20,20) rad/s per T4
        pos, vel, quat, omega = _step(pos, vel, quat, omega, M * G, cmd, tau=0.005)
    assert abs(float((quat * quat).sum()) - 1.0) < 1e-12


def test_dt_convergence_richardson():
    # 1-D fall with quadratic drag has closed form v(t) = -v_t*tanh(g*t/v_t), v_t = sqrt(g/c2)
    # = sqrt(9.81/0.046) = 14.6035 m/s. Symplectic Euler is order 1: halving dt halves the error.
    v_t = math.sqrt(G / CFG.drag_quad)
    v_exact = -v_t * math.tanh(G * 1.0 / v_t)                      # at t = 1 s: -8.5589 m/s
    errs = []
    for dt, n in ((DT, 50), (DT / 2, 100)):
        pos, vel, quat, omega = _state()
        for _ in range(n):
            pos, vel, quat, omega = _step(pos, vel, quat, omega, 0.0,
                                          torch.zeros(3, dtype=F64), dt=dt)
        errs.append(abs(float(vel[2]) - v_exact))
    assert 1.6 < errs[0] / errs[1] < 2.4                           # ratio ~2 <=> slope ~1


def test_batched_matches_single():
    torch.manual_seed(1)
    P, N = 2, 3
    pos, vel = torch.randn(P, N, 3, dtype=F64), torch.randn(P, N, 3, dtype=F64)
    quat = torch.nn.functional.normalize(torch.randn(P, N, 4, dtype=F64), dim=-1)
    omega, cmd = torch.randn(P, N, 3, dtype=F64), torch.randn(P, N, 3, dtype=F64)
    wind = torch.randn(P, N, 3, dtype=F64)
    thrust, ge = torch.rand(P, N, dtype=F64) * CFG.drone_t_max, 1.0 + torch.rand(P, N, dtype=F64)
    out = Q.quad_step(pos, vel, quat, omega, thrust, cmd, wind, ge,
                      M, CFG.tau_omega, CFG.drag_quad, CFG.drag_lin, G, DT)
    assert [tuple(o.shape) for o in out] == [(P, N, 3), (P, N, 3), (P, N, 4), (P, N, 3)]
    i, j = 1, 2
    single = Q.quad_step(pos[i, j], vel[i, j], quat[i, j], omega[i, j], thrust[i, j], cmd[i, j],
                         wind[i, j], ge[i, j], M, CFG.tau_omega, CFG.drag_quad, CFG.drag_lin, G, DT)
    for b, s in zip(out, single):                                  # vectorization correctness
        assert torch.allclose(b[i, j], s, atol=1e-12, rtol=0.0)
