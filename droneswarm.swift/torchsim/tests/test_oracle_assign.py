"""Balanced assignment (Sinkhorn dispersion) oracle — marginals balanced, disperses vs greedy-nearest,
masking of dead agents, and the per-drone target direction. Loop-free, deterministic."""
import os
import sys

import torch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from oracles import assign


def _ones(P, N, D, E):
    return torch.ones(P, N, D), torch.ones(P, N, E)


def test_marginals_balanced():
    """Sinkhorn output rows sum ~ uniform drone mass, cols sum ~ uniform enemy mass (the balance that
    disperses the swarm)."""
    torch.manual_seed(0)
    P, N, D, E = 2, 3, 8, 4
    dist = torch.rand(P, N, D, E) * 2.0
    da, ea = _ones(P, N, D, E)
    T = assign.balanced_assignment(dist, da, ea)
    row = T.sum(-1)                                             # per-drone mass
    col = T.sum(-2)                                             # per-enemy mass
    assert torch.allclose(row, torch.full_like(row, 1.0 / D), atol=2e-2), row
    assert torch.allclose(col, torch.full_like(col, 1.0 / E), atol=2e-2), col


def test_disperses_vs_greedy():
    """With more drones than enemies, balanced assignment spreads drones across ALL enemies, whereas
    greedy-nearest would pile onto whichever enemy is closest. Check every enemy gets real mass."""
    P, N, D, E = 1, 1, 12, 3
    # all drones nearest to enemy 0 (greedy would give enemy 0 everything)
    dist = torch.empty(P, N, D, E)
    dist[..., 0] = 0.1; dist[..., 1] = 1.0; dist[..., 2] = 1.2
    da, ea = _ones(P, N, D, E)
    T = assign.balanced_assignment(dist, da, ea)
    col = T.sum(-2)[0, 0]                                       # per-enemy total mass
    assert (col > 0.15).all(), f"an enemy got starved (not dispersed): {col}"   # each ~1/3 despite proximity skew


def test_dead_agents_carry_no_mass():
    """Dead drones/enemies get ~zero assignment mass (count-agnostic via masking)."""
    P, N, D, E = 1, 1, 6, 4
    dist = torch.rand(P, N, D, E) + 0.5
    da = torch.ones(P, N, D); da[..., 0] = 0.0                  # drone 0 dead
    ea = torch.ones(P, N, E); ea[..., 3] = 0.0                  # enemy 3 dead
    T = assign.balanced_assignment(dist, da, ea)
    assert float(T[0, 0, 0].sum()) < 1e-3                       # dead drone -> no mass
    assert float(T[0, 0, :, 3].sum()) < 1e-3                    # dead enemy -> no mass


def test_target_direction_points_at_assigned_enemy():
    """With ONE alive enemy, the drone is fully assigned it; the target direction equals the unit
    direction to it and focus is 1. (With D<E the balance splits coverage — a separate property.)"""
    P, N, D, E = 1, 1, 3, 1                                    # 3 drones, 1 enemy -> all commit to it
    dist = torch.full((P, N, D, E), 0.5)
    da = torch.ones(P, N, D); ea = torch.ones(P, N, E)
    rel_dir = torch.zeros(P, N, D, E, 3)
    rel_dir[..., 0, :] = torch.tensor([0.6, 0.0, -0.8])       # unit dir to the enemy (down-forward)
    T = assign.balanced_assignment(dist, da, ea)
    d, focus = assign.target_direction(T, rel_dir)
    assert torch.allclose(d[0, 0, 0], torch.tensor([0.6, 0.0, -0.8]), atol=1e-3)
    assert float(focus[0, 0, 0]) > 0.99                        # only one target -> full commit


def test_fewer_drones_than_enemies_splits_coverage():
    """Documented property: with D<E, balanced OT forces each drone to cover multiple enemies (every
    enemy demands equal mass), so a lone drone facing 2 enemies splits ~50/50 rather than committing.
    In the swarm regime (D>=E) drones commit; this test pins the edge behavior so it can't change silently."""
    P, N, D, E = 1, 1, 1, 2
    dist = torch.tensor([[[[0.3, 0.35]]]])                    # both enemies similarly near
    da = torch.ones(P, N, D); ea = torch.ones(P, N, E)
    T = assign.balanced_assignment(dist, da, ea)
    w = (T / T.sum(-1, keepdim=True))[0, 0, 0]
    assert 0.3 < float(w[0]) < 0.7 and 0.3 < float(w[1]) < 0.7   # split, not committed


def test_batched_slice_matches():
    """Vectorization: a batched call equals the per-slice computation."""
    P, N, D, E = 2, 3, 5, 4
    torch.manual_seed(1)
    dist = torch.rand(P, N, D, E) + 0.2
    da, ea = _ones(P, N, D, E)
    T = assign.balanced_assignment(dist, da, ea)
    T00 = assign.balanced_assignment(dist[:1, :1], da[:1, :1], ea[:1, :1])
    assert torch.allclose(T[:1, :1], T00, atol=1e-5)
