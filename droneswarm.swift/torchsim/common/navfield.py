"""common.navfield — the quantized 3D geodesic ROUTE field: a shared, scenario-agnostic pathfinder.

Given an occupancy of FORBIDDEN cells + a set of SOURCE cells, it solves the Eikonal equation
|∇d| = 1 over the ALLOWED space (Godunov upwind scheme) → `d` = shortest-route distance to the
nearest source (in metres), and `flow = −∇d` = the unit "walk down the geodesic" direction at every
cell. A drone (or any agent) trilinearly samples `flow` at its position and flies down it — that IS
the whole algorithmic navigator, no planner state, no per-agent search.

This is the exact solver the `arena` combat env grew (env_drone._build_navfield) lifted OUT so BOTH
arena and the `cherrypick` harvesting demo route on the same, unit-tested code (single source of truth
— [[droneswarm-navfield-always]]). The scenario supplies the occupancy + sources + the finite `dist`
init and `fixed` mask; navfield only does the geometry.

Method: branchless Godunov FAST-ITERATIVE / fast-sweeping Eikonal update — solve, per cell,
Σ_i w_i·((d − U_i)₊)² = 1 from the smaller upwind neighbour U_i on each axis (w_i = 1/h_i², h = cell
pitch), giving the TRUE Euclidean geodesic (a plain min-relaxation gives the ℓ¹/octile metric → zigzag
routes). The 3→2→1 causal cascade (use the fewest upwind axes that stays consistent) is done with a
min/max/where compare-swap network + safe-sqrt — NO python `if`, NO data loop, compile-safe, and
differentiable ([[no-loops-in-engine]]).
Refs (this is the STANDARD Godunov Eikonal solver, not one paper's bespoke algorithm):
  * [PAPER] per-cell upwind update  — Rouy & Tourin, "A Viscosity Solutions Approach to Shape-from-Shading",
    SIAM J. Numer. Anal. 29(3), 1992 (the Godunov Eikonal discretization; same update Sethian's fast
    marching and Zhao's fast-sweeping use).
  * [PAPER] parallel fixed-sweep relaxation (Jacobi, NO active list) — the GPU "fast-iterative" framing of
    Jeong & Whitaker, "A Fast Iterative Method for Eikonal Equations", SIAM J. Sci. Comput. 30(5), 2008;
    and Huang, "Improved Fast Iterative Algorithm for Eikonal Equation for GPU Computing",
    arXiv:2106.15869 (2021). We use plain full-grid sweeps -> FIM-inspired, not faithful FIM.
  * [PAPER] flow = -grad(d) trilinearly sampled -> steering — Treuille, Cooper & Popovic, "Continuum Crowds",
    ACM SIGGRAPH 2006.
  * [NOVEL] the update above rewritten BRANCHLESS + DIFFERENTIABLE: the 3->2->1 causal cascade as a
    min/max/where compare-swap network with safe-sqrt — NO python `if`, NO per-cell data loop, so the WHOLE
    solver is one batched GPU kernel chain AND carries gradients (usable as a differentiable potential, not
    only a perception). Standard FMM/FSM are inherently sequential/branchy; this vectorised form is what lets
    it fit 45k differentiable worlds and backprop through the route field ([[no-loops-in-engine]]).
All ops broadcast over arbitrary LEADING batch
dims; the last three dims are the grid (Gz, Gy, Gx) with SQUARE horizontal resolution (Gx == Gy).
"""
import torch
import torch.nn.functional as F

BIG = 1.0e6   # sentinel "unreached" distance; padded boundary + every non-source cell starts here


def geodesic(dist, fixed, wxy, wz, sweeps, big=BIG):
    """Relax an Eikonal distance field to the geodesic solution over the allowed space.

    `dist`  [...,Gz,G,G]  initial distance: 0 at source cells, `big` everywhere else (caller-built).
    `fixed` [...,Gz,G,G]  bool — cells that must NEVER relax (sources AND solids/forbidden). Frozen.
    `wxy`,`wz` scalars    per-axis Eikonal weights = 1/h² (h = xy cell pitch / z cell pitch, metres);
                          f = 1 so the fixed-point `dist` comes out in METRES.
    `sweeps` int          number of Jacobi relaxation passes (fixed unroll — NAV-FIELD-UNROLL-OK).
    Returns the relaxed `dist` [...,Gz,G,G] (same shape/dtype/device). Detach at the call site if the
    field is used only as a perception (arena) rather than a differentiable potential."""
    Gz = dist.shape[-3]; G = dist.shape[-1]                               # grid dims (square xy: G == Gy)
    for _ in range(sweeps):                                              # NAV-FIELD-UNROLL-OK: fixed relaxation
        dp = F.pad(dist, (1, 1, 1, 1, 1, 1), value=big)                 # pad x,y,z -> [...,Gz+2,G+2,G+2]
        zc, yc, xc = slice(1, Gz + 1), slice(1, G + 1), slice(1, G + 1)
        # upwind (smaller) neighbour on each axis
        Ux = torch.minimum(dp[..., zc, yc, :G], dp[..., zc, yc, 2:])     # [...,Gz,G,G] x neighbour
        Uy = torch.minimum(dp[..., zc, :G, xc], dp[..., zc, 2:, xc])     # y neighbour
        Uz = torch.minimum(dp[..., :Gz, yc, xc], dp[..., 2:, yc, xc])    # z neighbour
        # sort the three (U, w) axes ascending by U (three compare-swaps — no python branch)
        u0, w0 = Ux, torch.full_like(Ux, wxy); u1, w1 = Uy, torch.full_like(Uy, wxy)
        m = u0 <= u1; u0, w0, u1, w1 = torch.where(m, u0, u1), torch.where(m, w0, w1), torch.where(m, u1, u0), torch.where(m, w1, w0)
        u2, w2 = Uz, torch.full_like(Uz, wz)
        m = u1 <= u2; u1, w1, u2, w2 = torch.where(m, u1, u2), torch.where(m, w1, w2), torch.where(m, u2, u1), torch.where(m, w2, w1)
        m = u0 <= u1; u0, w0, u1, w1 = torch.where(m, u0, u1), torch.where(m, w0, w1), torch.where(m, u1, u0), torch.where(m, w1, w0)
        d1 = u0 + 1.0 / torch.sqrt(w0)                                   # 1-axis solution (nearest upwind face)
        A2 = w0 + w1; B2 = -2.0 * (w0 * u0 + w1 * u1); C2 = w0 * u0 * u0 + w1 * u1 * u1 - 1.0
        d2 = (-B2 + torch.sqrt(torch.clamp(B2 * B2 - 4.0 * A2 * C2, min=0.0))) / (2.0 * A2)   # 2-axis (safe-sqrt)
        A3 = A2 + w2; B3 = B2 - 2.0 * w2 * u2; C3 = C2 + w2 * u2 * u2     # fold in the 3rd axis
        d3 = (-B3 + torch.sqrt(torch.clamp(B3 * B3 - 4.0 * A3 * C3, min=0.0))) / (2.0 * A3)   # 3-axis (safe-sqrt)
        nb = torch.where(d1 <= u1, d1, torch.where(d2 <= u2, d2, d3))    # causal cascade: fewest upwind axes
        dist = torch.where(fixed, dist, torch.minimum(dist, nb))         # Jacobi relax; sources/solids frozen
    return dist


def flow_from_dist(dist, step, zst):
    """Unit route direction `flow = −∇dist` (points DOWN the geodesic, toward the nearest source).

    `dist` [...,Gz,G,G]; `step` = xy cell pitch (m); `zst` = z cell pitch (m). Returns [...,Gz,G,G,3]
    (x,y,z). REPLICATE-pad the boundary: a BIG pad here would poison the one-sided edge difference
    (esp. the ground plane) and flip the flow to point straight up — a bug we already paid for. Interior
    walls keep their BIG inside `dist`, so the flow still repels off real obstacles. Caller should zero
    the flow inside forbidden cells (navfield stays geometry-only)."""
    Gz = dist.shape[-3]; G = dist.shape[-1]
    dpad = F.pad(dist, (1, 1, 1, 1, 1, 1), mode="replicate")
    gx = (dpad[..., 1:Gz + 1, 1:G + 1, 2:] - dpad[..., 1:Gz + 1, 1:G + 1, :G]) / (2.0 * step)   # d/dx per METRE
    gy = (dpad[..., 1:Gz + 1, 2:, 1:G + 1] - dpad[..., 1:Gz + 1, :G, 1:G + 1]) / (2.0 * step)   # d/dy per METRE
    gz = (dpad[..., 2:, 1:G + 1, 1:G + 1] - dpad[..., :Gz, 1:G + 1, 1:G + 1]) / (2.0 * zst)     # d/dz per METRE
    flow = torch.stack([-gx, -gy, -gz], -1)                              # [...,Gz,G,G,3]
    return flow / (flow.norm(dim=-1, keepdim=True) + 1e-6)              # unit 3D route direction


def sample3(dist3, flow3, pos, extent, zlo, zhi):
    """Trilinear-sample the field at world positions. `dist3` [B,Gz,G,G]; `flow3` [B,Gz,G,G,3];
    `pos` [B,Q,3] query points (Q agents/probes per field). `extent` = xy half-size (world spans
    [-extent, extent] in x and y), [zlo, zhi] = the z span the grid covers. Returns `geo [B,Q]`
    (geodesic distance) + `flow [B,Q,3]` (unit route dir). Mirrors env_drone._sample_nav3 but with the
    grid geometry passed in rather than read off `self`, so any scenario can call it."""
    B, Q, _ = pos.shape
    xn = (pos[..., 0] / extent).clamp(-1.0, 1.0)                          # x -> [-1,1]
    yn = (pos[..., 1] / extent).clamp(-1.0, 1.0)                          # y -> [-1,1]
    zn = ((pos[..., 2] - zlo) / (zhi - zlo) * 2.0 - 1.0).clamp(-1.0, 1.0) # z -> [-1,1]
    Gz, G = dist3.shape[-3], dist3.shape[-1]
    grid = torch.stack([xn, yn, zn], -1).reshape(B, Q, 1, 1, 3)          # [B,Q,1,1,3] (x,y,z) for grid_sample
    fld = torch.cat([dist3[..., None], flow3], -1).permute(0, 4, 1, 2, 3).reshape(B, 4, Gz, G, G)   # [B,4,Gz,G,G]
    s = F.grid_sample(fld, grid, mode="bilinear", align_corners=True).reshape(B, 4, Q).permute(0, 2, 1)   # [B,Q,4]
    geo = s[..., 0]                                                       # [B,Q] geodesic distance
    flow = s[..., 1:4]                                                    # [B,Q,3] 3D route direction
    flow = flow / (flow.norm(dim=-1, keepdim=True) + 1e-6)              # re-unit after interpolation
    return geo, flow
