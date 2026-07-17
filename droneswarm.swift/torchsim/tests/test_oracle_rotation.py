"""Oracle tests: quaternion algebra (Hamilton, w-first) vs SOURCES quadrotor-ctbr T3/T4 vectors."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import math
import numpy as np
import torch

from oracles import rotation


def test_identity_rotates_to_self():
    q = torch.tensor([1.0, 0.0, 0.0, 0.0])  # identity quaternion: rotation by 0
    v = torch.tensor([0.3, -1.7, 2.5])
    assert torch.allclose(rotation.quat_rotate(q, v), v, atol=1e-7, rtol=0)


def test_90deg_about_z_maps_x_to_y():
    # q = [cos(45deg), 0, 0, sin(45deg)] is a +90deg rotation about +z (half-angle form)
    s = math.sqrt(0.5)
    q = torch.tensor([s, 0.0, 0.0, s])
    v = rotation.quat_rotate(q, torch.tensor([1.0, 0.0, 0.0]))
    assert torch.allclose(v, torch.tensor([0.0, 1.0, 0.0]), atol=1e-6, rtol=0)  # x-axis -> y-axis


def test_fixed_axis_exactness_sources_t3():
    # SOURCES T3: omega=[0,0,pi] rad/s, q0=[1,0,0,0]; t=0.5 s => q=[0.7071068,0,0,0.7071068]
    q0 = torch.tensor([1.0, 0.0, 0.0, 0.0], dtype=torch.float64)
    om = torch.tensor([0.0, 0.0, math.pi], dtype=torch.float64)
    q_exact = torch.tensor([0.7071068, 0.0, 0.0, 0.7071068], dtype=torch.float64)  # T3 vector
    q_one = rotation.quat_integrate(q0, om, 0.5)          # one big step
    q_many = q0
    for _ in range(100):                                   # 100 steps of dt=0.005, same total angle
        q_many = rotation.quat_integrate(q_many, om, 0.005)
    # Sola Eq. (228)-(229): zeroth-order product is EXACT for a fixed axis => both match closed form
    assert torch.allclose(q_one, q_exact, atol=1e-7, rtol=0)
    assert torch.allclose(q_many, q_exact, atol=1e-7, rtol=0)
    # T3 t=1 s => q=[0,0,0,1]
    assert torch.allclose(rotation.quat_integrate(q0, om, 1.0),
                          torch.tensor([0.0, 0.0, 0.0, 1.0], dtype=torch.float64), atol=1e-7, rtol=0)
    # T3 double cover: omega=(2*pi/sqrt(3))*(1,1,1), t=1 s (total angle 2*pi) => q=[-1,0,0,0], NOT +1
    om2 = torch.full((3,), 2.0 * math.pi / math.sqrt(3.0), dtype=torch.float64)
    q = q0
    for _ in range(1000):                                  # N=1000 steps per T3, tol 1e-6
        q = rotation.quat_integrate(q, om2, 1e-3)
    assert torch.allclose(q, torch.tensor([-1.0, 0.0, 0.0, 0.0], dtype=torch.float64), atol=1e-6, rtol=0)


def test_norm_preservation_1e5_steps_float64():
    # SOURCES T4 / Sola sec 4.6.2: product of unit quaternions is unit by construction
    torch.manual_seed(0)
    q = torch.tensor([1.0, 0.0, 0.0, 0.0], dtype=torch.float64)
    omegas = (torch.rand(100_000, 3, dtype=torch.float64) - 0.5) * 0.4  # random small rates U(-0.2,0.2)
    for i in range(100_000):
        q = rotation.quat_integrate(q, omegas[i], 0.01)
    assert abs(float(torch.linalg.norm(q)) - 1.0) < 1e-9  # T4 float64 bound


def test_body_z_axis_identity_and_tilt():
    q_id = torch.tensor([1.0, 0.0, 0.0, 0.0])
    assert torch.allclose(rotation.body_z_axis(q_id), torch.tensor([0.0, 0.0, 1.0]), atol=1e-7, rtol=0)
    # 30deg tilt about +x: q=[cos15,sin15,0,0]; R_x(30deg)*e_z = (0,-sin30,cos30) = (0,-0.5,0.8660254)
    q = torch.tensor([math.cos(math.radians(15.0)), math.sin(math.radians(15.0)), 0.0, 0.0])
    bz = rotation.body_z_axis(q)
    assert torch.allclose(bz, torch.tensor([0.0, -0.5, 0.8660254]), atol=1e-6, rtol=0)
    # closed-form third column must equal the generic rotate of e_z
    assert torch.allclose(bz, rotation.quat_rotate(q, torch.tensor([0.0, 0.0, 1.0])), atol=1e-6, rtol=0)


def test_sinc_guard_near_zero_and_grad_finite():
    # quat_from_rotvec at ||phi||~1e-9 must hit the sinc guard: finite, ~identity [1,0,0,0]
    q = rotation.quat_from_rotvec(torch.tensor([1e-9, 1e-9, 1e-9]))
    assert torch.isfinite(q).all()
    assert torch.allclose(q, torch.tensor([1.0, 0.0, 0.0, 0.0]), atol=1e-8, rtol=0)
    # SOURCES IMPLEMENTATION MANDATES: torch.where both-branch 0/0 must not NaN-poison backward
    phi = torch.zeros(3, requires_grad=True)
    rotation.quat_from_rotvec(phi).sum().backward()
    assert torch.isfinite(phi.grad).all()


def test_batched_pnk_slice_equals_single():
    # family convention [P,N,K,...]: P=2 policies, N=3 agents, K=4 whatever
    torch.manual_seed(1)
    phi = torch.randn(2, 3, 4, 3) * 0.7
    v = torch.randn(2, 3, 4, 3)
    q = rotation.quat_from_rotvec(phi)
    assert q.shape == (2, 3, 4, 4)
    vr = rotation.quat_rotate(q, v)
    bz = rotation.body_z_axis(q)
    qi = rotation.quat_integrate(q, v, 0.01)  # reuse v as omega, shape check
    assert vr.shape == (2, 3, 4, 3) and bz.shape == (2, 3, 4, 3) and qi.shape == (2, 3, 4, 4)
    # vectorization correctness: slice [1,2,3] of the batched result == single-element call
    assert torch.allclose(q[1, 2, 3], rotation.quat_from_rotvec(phi[1, 2, 3]), atol=1e-7, rtol=0)
    assert torch.allclose(vr[1, 2, 3], rotation.quat_rotate(q[1, 2, 3], v[1, 2, 3]), atol=1e-6, rtol=0)
    assert torch.allclose(qi[0, 0, 1], rotation.quat_integrate(q[0, 0, 1], v[0, 0, 1], 0.01), atol=1e-7, rtol=0)
    # unit norm across the whole batch (Exp of a rotvec is unit by construction)
    assert torch.allclose(torch.linalg.norm(q, dim=-1), torch.ones(2, 3, 4), atol=1e-6, rtol=0)


def _integrate_varying(n_steps):
    """Zeroth-order integrate omega(t)=(sin 2pi t, cos 2pi t, 1) over t in [0,1], left-endpoint."""
    dt = 1.0 / n_steps
    q = torch.tensor([1.0, 0.0, 0.0, 0.0], dtype=torch.float64)
    for k in range(n_steps):
        t = k * dt
        om = torch.tensor([math.sin(2 * math.pi * t), math.cos(2 * math.pi * t), 1.0], dtype=torch.float64)
        q = rotation.quat_integrate(q, om, dt)
    return q


def test_dt_convergence_richardson():
    # Sola zeroth-order is first-order accurate for a MOVING axis: halving dt ~ halves error (slope~1)
    q_ref = _integrate_varying(8192)  # fine-dt reference, error ~1/8192 << coarse errors
    e = [float(torch.linalg.norm(_integrate_varying(n) - q_ref)) for n in (64, 128, 256)]
    assert e[0] > e[1] > e[2] > 0
    slope01 = float(np.log2(e[0] / e[1]))  # expected ~1.0 for a first-order method
    slope12 = float(np.log2(e[1] / e[2]))
    assert 0.7 < slope01 < 1.3, (e, slope01)
    assert 0.7 < slope12 < 1.3, (e, slope12)
