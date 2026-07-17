"""Balanced target assignment — the swarm-dispersion oracle.

Entropy-regularized optimal transport (Sinkhorn-Knopp; Cuturi, "Sinkhorn Distances", NeurIPS 2013)
between drones and enemies: a doubly-normalized soft matching whose cost is distance, so it RESPECTS
proximity while its balanced marginals SPREAD the swarm evenly across enemies — dispersion instead of
piling onto the nearest target. This is exactly "drone->enemy attention (softmax over enemies) PLUS a
cross-drone normalization": the softmax gives 'who is near what', the column normalization gives
'don't all pick the same one'. It accounts for the FULL joint drone+enemy configuration.

Fully vectorized, LOOP-FREE (the fixed Sinkhorn iterations are UNROLLED — no python loop), deterministic
(a pure function of current positions, so it is re-computed every decision = dynamic re-assignment on
the fly), and count-agnostic (dead drones/enemies carry zero mass via masking). Fed to the control
policy as a per-drone target-direction feature; the net may use or override it.
"""
import torch


def _sinkhorn_iter(K, u, v, a, b, eps):
    """One Sinkhorn row+column rescaling. K [P,N,D,E], u [P,N,D], v [P,N,E] -> (u, v)."""
    u = a / ((K * v[..., None, :]).sum(-1) + eps)            # row scaling  -> [P,N,D]
    v = b / ((K * u[..., :, None]).sum(-2) + eps)            # col scaling  -> [P,N,E]
    return u, v


def balanced_assignment(dist, drone_alive, enemy_alive, temp=0.6, eps=1e-6):
    """Sinkhorn balanced soft assignment. dist [P,N,D,E] drone->enemy distances (in ~O(1) scale units),
    drone_alive [P,N,D], enemy_alive [P,N,E] -> T [P,N,D,E] (rows≈drones, cols≈enemies, balanced).
    4 UNROLLED iterations (no python loop). Dead drones/enemies carry zero mass. temp = entropy reg."""
    P, N, D, E = dist.shape
    m = drone_alive[..., None] * enemy_alive[..., None, :]   # [P,N,D,E] valid-pair mask
    K = torch.exp(-dist / temp) * m                          # masked affinity
    a = drone_alive / (drone_alive.sum(-1, keepdim=True) + eps)   # uniform mass over alive drones
    b = enemy_alive / (enemy_alive.sum(-1, keepdim=True) + eps)   # uniform mass over alive enemies
    u = torch.ones(P, N, D, device=dist.device, dtype=dist.dtype)
    v = torch.ones(P, N, E, device=dist.device, dtype=dist.dtype)
    u, v = _sinkhorn_iter(K, u, v, a, b, eps)
    u, v = _sinkhorn_iter(K, u, v, a, b, eps)
    u, v = _sinkhorn_iter(K, u, v, a, b, eps)
    u, v = _sinkhorn_iter(K, u, v, a, b, eps)
    return u[..., :, None] * K * v[..., None, :]             # transport plan [P,N,D,E]


def target_direction(T, rel_dir, eps=1e-6):
    """Per-drone assigned target = assignment-weighted mean of directions to enemies. T [P,N,D,E],
    rel_dir [P,N,D,E,3] (unit drone->enemy) -> (dir [P,N,D,3] unit, focus [P,N,D]). focus = peak
    assignment weight (1 = committed to a single target, ~1/E = spread thin / no target)."""
    w = T / (T.sum(-1, keepdim=True) + eps)                  # per-drone distribution over enemies
    d = (w[..., None] * rel_dir).sum(-2)                     # [P,N,D,3] weighted-mean direction
    dlen = torch.sqrt((d * d).sum(-1, keepdim=True) + eps)
    return d / dlen, w.amax(-1)
