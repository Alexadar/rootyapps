"""Heightfield terrain oracle — bilinear height + analytic gradient over a regular grid.

Standard bilinear interpolation of a regular [G,G] heightfield (cite: any graphics/geomatics text;
the scheme monstro used for flow-field sampling, generalized). World xy in [-extent,extent] maps to
grid coords in [0,G-1]; height is the bilinear blend of the 4 surrounding nodes; the gradient is the
EXACT analytic derivative of that blend, so the slope a unit feels matches the height it stands on.

Batched over the FAMILY CONVENTION: entity tensors are [P, N, K, ...] (P=rollout copies, N=envs,
K=agents). hf is [N,G,G] (per-env terrain). Per-env node lookup uses advanced indexing (memory-light,
no [.,GG] expansion) — fully loop-free. NO python loops.
"""
import torch


def _sample_nodes(hf, ix, iy):
    """hf [N,G,G]; ix,iy [P,N,K] integer grid indices -> node heights [P,N,K]. Advanced indexing:
    h[p,n,k] = hf[n, iy[p,n,k], ix[p,n,k]]. Env axis is dim 1 (family convention). Loop-free."""
    N = hf.shape[0]
    P, _, K = ix.shape
    n_idx = torch.arange(N, device=hf.device).view(1, N, 1).expand(P, N, K)
    return hf[n_idx, iy, ix]


def _to_grid(xy, extent, G):
    """World xy [P,N,K,2] in [-extent,extent] -> (ix,iy floor [P,N,K], tx,ty frac [P,N,K]). col=x, row=y."""
    norm = (xy / extent).clamp(-1.0, 1.0)
    g = (norm + 1.0) * 0.5 * (G - 1)                              # [0,G-1]
    gi = torch.floor(g).long().clamp(0, G - 2)
    tf = (g - gi.to(g.dtype)).clamp(0.0, 1.0)
    return gi[..., 0], gi[..., 1], tf[..., 0], tf[..., 1]


def height(hf, xy, extent):
    """Bilinear terrain height. hf [N,G,G], xy [P,N,K,2] -> [P,N,K]. Loop-free."""
    G = hf.shape[1]
    ix, iy, tx, ty = _to_grid(xy, extent, G)
    h00 = _sample_nodes(hf, ix, iy)
    h10 = _sample_nodes(hf, ix + 1, iy)
    h01 = _sample_nodes(hf, ix, iy + 1)
    h11 = _sample_nodes(hf, ix + 1, iy + 1)
    return (h00 * (1 - tx) * (1 - ty) + h10 * tx * (1 - ty)
            + h01 * (1 - tx) * ty + h11 * tx * ty)


def height_grad(hf, xy, extent):
    """Analytic gradient d(height)/d(world xy). hf [N,G,G], xy [P,N,K,2] -> [P,N,K,2]. Exact
    derivative of the bilinear blend; chain rule d(grid)/d(world) = (G-1)/(2 extent). Loop-free."""
    G = hf.shape[1]
    ix, iy, tx, ty = _to_grid(xy, extent, G)
    h00 = _sample_nodes(hf, ix, iy)
    h10 = _sample_nodes(hf, ix + 1, iy)
    h01 = _sample_nodes(hf, ix, iy + 1)
    h11 = _sample_nodes(hf, ix + 1, iy + 1)
    dh_dgx = (h10 - h00) * (1 - ty) + (h11 - h01) * ty
    dh_dgy = (h01 - h00) * (1 - tx) + (h11 - h10) * tx
    dg_dw = (G - 1) / (2.0 * extent)
    return torch.stack([dh_dgx * dg_dw, dh_dgy * dg_dw], dim=-1)
