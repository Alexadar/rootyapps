"""Oracle tests for collide3 — vec3 SDF (box + vertical cylinder) + segment clearance.
Closed-form hand values (standard exact box/cylinder SDF, Quilez form), gradient invariants
(unit-length + outward outside, finite-difference match), mask padding, and [P,N,K] batching.
No integrator in this module -> no dt-convergence test. Run: pytest tests/test_oracle_collide3.py -q
"""
import os
import sys

import numpy as np
import torch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from common.oracles import collide3 as C

BOX = torch.tensor(0.0)   # is_cyl flag: 0 = box
CYL = torch.tensor(1.0)   # is_cyl flag: 1 = cylinder
H_BOX = torch.tensor([1.0, 1.0, 1.0])   # unit box half-extents
H_CYL = torch.tensor([1.0, 1.0, 2.0])   # cylinder: radius=half[0]=1, half-height=half[2]=2


def test_box_sdf_hand_values():
    # (3,4,0) vs unit box: q=(2,3,-1) -> sqrt(2^2+3^2)=sqrt(13)=3.605551 (3-4-5 offset corner form)
    s = C.shape_sdf3(torch.tensor([3.0, 4.0, 0.0]), H_BOX, BOX)
    assert abs(float(s) - np.sqrt(13.0)) < 1e-5
    # center: sdf = -min(half) = -1 (deepest inside face distance)
    assert abs(float(C.shape_sdf3(torch.tensor([0.0, 0.0, 0.0]), H_BOX, BOX)) - (-1.0)) < 1e-5
    # exactly on the +x face -> 0 (surface)
    assert abs(float(C.shape_sdf3(torch.tensor([1.0, 0.0, 0.0]), H_BOX, BOX))) < 1e-5


def test_cyl_sdf_hand_values():
    # radial: (3,0,0), r=3, radius=1 -> 2; axial: (0,0,3), |z|=3, half-height=2 -> 1
    assert abs(float(C.shape_sdf3(torch.tensor([3.0, 0.0, 0.0]), H_CYL, CYL)) - 2.0) < 1e-5
    assert abs(float(C.shape_sdf3(torch.tensor([0.0, 0.0, 3.0]), H_CYL, CYL)) - 1.0) < 1e-5
    # rim corner: (2,0,3) -> d_rad=1, d_ax=1 -> sqrt(2) (2D-box corner form)
    assert abs(float(C.shape_sdf3(torch.tensor([2.0, 0.0, 3.0]), H_CYL, CYL)) - np.sqrt(2.0)) < 1e-5
    # center inside: max(d_rad,d_ax) = max(-1,-2) = -1
    assert abs(float(C.shape_sdf3(torch.tensor([0.0, 0.0, 0.0]), H_CYL, CYL)) - (-1.0)) < 1e-5


def test_grad_unit_length_outside():
    # random points in a shell |dvec| in [3,6]: strictly outside both shapes (circumscribed radii
    # sqrt(3)=1.73 for the box, sqrt(1+4)=2.24 for the cylinder) -> ||grad|| = 1 exactly outside
    torch.manual_seed(0)
    dirs = torch.randn(200, 3)
    dirs = dirs / dirs.norm(dim=-1, keepdim=True)
    pts = dirs * (3.0 + 3.0 * torch.rand(200, 1))
    for half, flag in ((H_BOX, BOX), (H_CYL, CYL)):
        sdf, grad = C.shape_sdf3_grad(pts, half.expand(200, 3), flag.expand(200))
        assert bool((sdf > 0).all())
        assert torch.allclose(grad.norm(dim=-1), torch.ones(200), atol=1e-4, rtol=0.0)


def test_grad_outward_and_matches_finite_difference():
    torch.manual_seed(1)
    dirs = torch.randn(64, 3, dtype=torch.float64)      # float64: fd noise ~eps*sdf/2h kills float32
    dirs = dirs / dirs.norm(dim=-1, keepdim=True)
    pts = dirs * (3.0 + 3.0 * torch.rand(64, 1, dtype=torch.float64))
    h = 1e-4                                            # central-difference step
    for half, flag in ((H_BOX.double(), BOX.double()), (H_CYL.double(), CYL.double())):
        _, grad = C.shape_sdf3_grad(pts, half.expand(64, 3), flag.expand(64))
        # outward: positive projection onto the center->point direction, for every exterior point
        assert bool(((grad * pts).sum(-1) > 0.0).all())
        for ax in range(3):                             # grad_ax = d(sdf)/d(dvec_ax), O(h^2) error
            e = torch.zeros(3, dtype=torch.float64)
            e[ax] = h
            fd = (C.shape_sdf3(pts + e, half.expand(64, 3), flag.expand(64))
                  - C.shape_sdf3(pts - e, half.expand(64, 3), flag.expand(64))) / (2 * h)
            assert torch.allclose(grad[:, ax], fd, atol=1e-3, rtol=0.0)


def test_grad_inside_points_out_nearest_face():
    # box interior point (0.9,0,0): nearest face is +x -> grad = (1,0,0) exactly
    s, g = C.shape_sdf3_grad(torch.tensor([0.9, 0.0, 0.0]), H_BOX, BOX)
    assert float(s) < 0.0
    assert torch.allclose(g, torch.tensor([1.0, 0.0, 0.0]), atol=1e-6, rtol=0.0)
    # cylinder interior (0.9,0,0): side wall (d_rad=-0.1) beats cap (d_ax=-2) -> radial +x unit
    s, g = C.shape_sdf3_grad(torch.tensor([0.9, 0.0, 0.0]), H_CYL, CYL)
    assert abs(float(s) - (-0.1)) < 1e-5               # max(d_rad,d_ax) = -0.1
    assert torch.allclose(g, torch.tensor([1.0, 0.0, 0.0]), atol=1e-5, rtol=0.0)


def test_segment_clearance_through_and_clear():
    xy = torch.stack([torch.zeros(3)])                  # one unit box at the origin, K=1
    half = H_BOX.expand(1, 3)
    is_cyl = torch.zeros(1)
    mask = torch.ones(1)
    # segment (-5,0,0)->(5,0,0) pierces the box center: sdf(center)=-1, minus radius 0.1 -> -1.1
    c = C.segment_clearance(torch.tensor([-5.0, 0.0, 0.0]), torch.tensor([10.0, 0.0, 0.0]),
                            xy, half, is_cyl, mask, 0.1)
    assert abs(float(c) - (-1.1)) < 1e-4
    # same segment lifted to z=5: closest point (0,0,5), sdf = 5-1 = 4, minus 0.1 -> 3.9
    c = C.segment_clearance(torch.tensor([-5.0, 0.0, 5.0]), torch.tensor([10.0, 0.0, 0.0]),
                            xy, half, is_cyl, mask, 0.1)
    assert abs(float(c) - 3.9) < 1e-4


def test_segment_clearance_padding_never_blocks():
    # two shapes: a blocking box (mask=0, padded) and a far cylinder (mask=1) at (0,20,0)
    xy = torch.tensor([[0.0, 0.0, 0.0], [0.0, 20.0, 0.0]])
    half = torch.stack([H_BOX, H_CYL])
    is_cyl = torch.tensor([0.0, 1.0])
    mask = torch.tensor([0.0, 1.0])
    c = C.segment_clearance(torch.tensor([-5.0, 0.0, 0.0]), torch.tensor([10.0, 0.0, 0.0]),
                            xy, half, is_cyl, mask, 0.1)
    # padded box ignored; live cylinder: closest point (0,0,0), r=20, sdf=19, -0.1 -> 18.9
    assert abs(float(c) - 18.9) < 1e-3


def test_batched_vectorization():
    # family [P,N,K,...] convention: P=2 envs, N=3 agents, K=4 shapes
    torch.manual_seed(2)
    P, N, K = 2, 3, 4
    dvec = torch.randn(P, N, K, 3) * 3.0
    half = 0.5 + torch.rand(P, N, K, 3)
    is_cyl = (torch.rand(P, N, K) > 0.5).float()
    sdf = C.shape_sdf3(dvec, half, is_cyl)
    sdf_g, grad = C.shape_sdf3_grad(dvec, half, is_cyl)
    assert sdf.shape == (P, N, K) and grad.shape == (P, N, K, 3)
    assert torch.allclose(sdf, sdf_g, atol=1e-6, rtol=0.0)
    # single-slice call must equal the batched result at that index (vectorization correctness)
    s12 = C.shape_sdf3(dvec[1, 2], half[1, 2], is_cyl[1, 2])
    assert torch.allclose(s12, sdf[1, 2], atol=0.0, rtol=0.0)
    # segment_clearance batched: p0/d [P,N,3], shapes [P,N,K,...] -> [P,N]
    p0 = torch.randn(P, N, 3)
    d = torch.randn(P, N, 3) * 5.0
    mask = torch.ones(P, N, K)
    c = C.segment_clearance(p0, d, dvec, half, is_cyl, mask, 0.1)
    assert c.shape == (P, N)
    c01 = C.segment_clearance(p0[0, 1], d[0, 1], dvec[0, 1], half[0, 1], is_cyl[0, 1], mask[0, 1], 0.1)
    assert torch.allclose(c01, c[0, 1], atol=1e-6, rtol=0.0)
