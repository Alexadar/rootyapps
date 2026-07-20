"""Terrain oracle: bilinear heightfield + analytic gradient (NR §3.6 Eq. 3.6.3–3.6.5).
Hand values from SOURCES.md 'ground-units-terrain' §4.4 unit-cell vector + plane closed forms.
Node j sits at world -extent + j*(2*extent/(G-1)); hf is [N,G,G] indexed [n, iy, ix]."""
import os
import sys

import numpy as np
import torch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from common.oracles import terrain


def _pt(x, y, dtype=torch.float32):
    """Single world point as [P=1,N=1,K=1,2]."""
    return torch.tensor([[[[x, y]]]], dtype=dtype)


def _plane_hf(a, b, G, extent, dtype=torch.float32):
    """hf[0, iy, ix] = a*x[ix] + b*y[iy] for the tilted plane h = a*x + b*y."""
    nodes = torch.linspace(-extent, extent, G, dtype=dtype)  # node j at -extent + j*2*extent/(G-1)
    return (a * nodes.view(1, 1, G) + b * nodes.view(1, G, 1))


def test_height_at_nodes_exact():
    # Plane h = 0.3*x - 0.7*y on G=5, extent=10 (nodes at -10,-5,0,5,10); bilinear
    # reproduces node values exactly (t=u=0 or 1 at nodes, NR 3.6.5).
    G, extent, a, b = 5, 10.0, 0.3, -0.7
    hf = _plane_hf(a, b, G, extent)
    nodes = torch.linspace(-extent, extent, G)
    for j in range(G):
        for k in range(G):
            h = terrain.height(hf, _pt(float(nodes[j]), float(nodes[k])), extent)
            expected = a * float(nodes[j]) + b * float(nodes[k])  # plane closed form
            assert abs(float(h) - expected) < 1e-5


def test_edge_midpoint_is_linear_interp():
    # On a cell edge the blend degenerates to 1D linear interp of the 2 endpoints (NR 3.6.5
    # with u=0): midpoint value = mean of endpoints. Random bumpy hf, G=5, extent=10.
    torch.manual_seed(0)
    G, extent = 5, 10.0
    hf = torch.randn(1, G, G)
    nodes = torch.linspace(-extent, extent, G)
    # horizontal edge between nodes (ix=1,iy=2) and (ix=2,iy=2): x midpoint, y exactly on row 2
    h = terrain.height(hf, _pt(float((nodes[1] + nodes[2]) / 2), float(nodes[2])), extent)
    assert abs(float(h) - float((hf[0, 2, 1] + hf[0, 2, 2]) / 2)) < 1e-6
    # vertical edge between (ix=3,iy=0) and (ix=3,iy=1)
    h = terrain.height(hf, _pt(float(nodes[3]), float((nodes[0] + nodes[1]) / 2)), extent)
    assert abs(float(h) - float((hf[0, 0, 3] + hf[0, 1, 3]) / 2)) < 1e-6


def test_gradient_constant_on_tilted_plane():
    # Bilinear reproduces any plane exactly (SOURCES §4.4 property), so height_grad must be
    # the constant (a, b) = (0.3, -0.7) at every interior point, atol 1e-4.
    torch.manual_seed(1)
    G, extent, a, b = 5, 10.0, 0.3, -0.7
    hf = _plane_hf(a, b, G, extent)
    xy = (torch.rand(1, 1, 64, 2) * 2 - 1) * (extent * 0.999)  # random pts inside the arena
    g = terrain.height_grad(hf, xy, extent)
    assert torch.allclose(g, torch.tensor([a, b]).expand(1, 1, 64, 2), atol=1e-4)
    # and the heights themselves match the plane closed form h = a*x + b*y
    h = terrain.height(hf, xy, extent)
    assert torch.allclose(h, a * xy[..., 0] + b * xy[..., 1], atol=1e-4)


def test_gradient_matches_finite_differences_on_bumpy_hf():
    # Analytic grad vs central finite differences (eps=1e-3 m << cell 2 m, stays inside one
    # cell where the blend is smooth; NR notes grad jumps only ACROSS edges). float64, tol 1e-3.
    torch.manual_seed(2)
    G, extent, eps = 9, 8.0, 1e-3
    hf = torch.randn(1, G, G, dtype=torch.float64)
    # points at cell-interior fractions t,u in [0.2, 0.8] so the eps-stencil never crosses an edge
    gi = torch.randint(0, G - 1, (1, 1, 32, 2)).double()
    gpos = gi + 0.2 + 0.6 * torch.rand(1, 1, 32, 2, dtype=torch.float64)
    xy = gpos / (G - 1) * 2 * extent - extent  # grid -> world inverse of _to_grid
    g = terrain.height_grad(hf, xy, extent)
    ex = torch.tensor([eps, 0.0], dtype=torch.float64)
    ey = torch.tensor([0.0, eps], dtype=torch.float64)
    fd_x = (terrain.height(hf, xy + ex, extent) - terrain.height(hf, xy - ex, extent)) / (2 * eps)
    fd_y = (terrain.height(hf, xy + ey, extent) - terrain.height(hf, xy - ey, extent)) / (2 * eps)
    assert torch.allclose(g[..., 0], fd_x, atol=1e-3)
    assert torch.allclose(g[..., 1], fd_y, atol=1e-3)


def test_sources_unit_cell_vector():
    # SOURCES §4.4 (NR corner order y1=0,y2=1,y3=3,y4=2; Δx=Δy=1 -> G=2, extent=0.5):
    # hf[iy,ix] = [[y1,y2],[y4,y3]] = [[0,1],[2,3]].
    extent = 0.5
    hf = torch.tensor([[[0.0, 1.0], [2.0, 3.0]]])
    # center t=u=0.5: h = (0+1+3+2)/4 = 1.5 (mean of 4 corners)
    assert abs(float(terrain.height(hf, _pt(0.0, 0.0), extent)) - 1.5) < 1e-6
    # interior t=0.25, u=0.75 -> world (-0.25, 0.25): h = 1.75 (SOURCES §4.4 hand value)
    assert abs(float(terrain.height(hf, _pt(-0.25, 0.25), extent)) - 1.75) < 1e-6
    # gradient there: dh/dx = 0.25*1 + 0.75*1 = 1.0; dh/dy = 0.75*2 + 0.25*2 = 2.0 (SOURCES §4.4)
    g = terrain.height_grad(hf, _pt(-0.25, 0.25), extent)
    assert torch.allclose(g, torch.tensor([[[[1.0, 2.0]]]]), atol=1e-6)
    # corners reproduce exactly: h(-e,-e)=0, h(e,-e)=1, h(e,e)=3, h(-e,e)=2 (NR 3.6.3)
    for (x, y, v) in [(-0.5, -0.5, 0.0), (0.5, -0.5, 1.0), (0.5, 0.5, 3.0), (-0.5, 0.5, 2.0)]:
        assert abs(float(terrain.height(hf, _pt(x, y), extent)) - v) < 1e-6


def test_interpolant_within_corner_bounds():
    # Convex-combination invariant (weights sum to 1, all >=0): min(corners) <= h <= max
    # over the whole field (SOURCES §4.4 property).
    torch.manual_seed(3)
    G, extent = 7, 12.0
    hf = torch.randn(1, G, G) * 5.0
    xy = (torch.rand(1, 1, 256, 2) * 2 - 1) * extent
    h = terrain.height(hf, xy, extent)
    assert float(h.min()) >= float(hf.min()) - 1e-6
    assert float(h.max()) <= float(hf.max()) + 1e-6


def test_batched_shapes_and_vectorization():
    # Family convention [P=2, N=1, K=3]: shapes + a single-element slice equals the batched
    # result at that index (vectorization correctness of the advanced indexing).
    torch.manual_seed(4)
    G, extent = 5, 10.0
    hf = torch.randn(1, G, G)
    xy = (torch.rand(2, 1, 3, 2) * 2 - 1) * extent
    h, g = terrain.height(hf, xy, extent), terrain.height_grad(hf, xy, extent)
    assert h.shape == (2, 1, 3) and g.shape == (2, 1, 3, 2)
    for p in range(2):
        for k in range(3):
            h1 = terrain.height(hf, xy[p : p + 1, :, k : k + 1], extent)
            g1 = terrain.height_grad(hf, xy[p : p + 1, :, k : k + 1], extent)
            assert torch.allclose(h1[0, 0, 0], h[p, 0, k], atol=1e-6)
            assert torch.allclose(g1[0, 0, 0], g[p, 0, k], atol=1e-6)
    # per-env lookup: N=2 with constant fields 5.0 / -3.0 -> each env reads its own hf, grad 0
    hf2 = torch.stack([torch.full((G, G), 5.0), torch.full((G, G), -3.0)])
    xy2 = (torch.rand(2, 2, 3, 2) * 2 - 1) * extent
    h2 = terrain.height(hf2, xy2, extent)
    assert torch.allclose(h2[:, 0], torch.full((2, 3), 5.0), atol=1e-6)
    assert torch.allclose(h2[:, 1], torch.full((2, 3), -3.0), atol=1e-6)
    assert torch.allclose(terrain.height_grad(hf2, xy2, extent), torch.zeros(2, 2, 3, 2), atol=1e-6)
