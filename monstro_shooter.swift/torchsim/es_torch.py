"""Evolution Strategies in torch — mirrored sampling + centered-rank shaping (mirror brax/es.py,
GPUES.swift). Gradient-free: perturb a net's weights, evaluate the whole population in ONE batched
rollout (the population is the leading [P] dim), nudge toward the rank-weighted mean.

`fitness(stacked_params) -> [P]` evaluates all P members at once (P = 2*pop, plus then minus)."""
import torch


def _centered_ranks(f):
    # f: [P] tensor -> centered ranks in [-0.5, 0.5]
    order = torch.argsort(torch.argsort(f))
    return order.float() / max(f.numel() - 1, 1) - 0.5


def perturb(center, noise, sigma):
    """center: list of (W,b). noise: list of (nW,nb) each [pop, *shape]. Returns stacked [2*pop,...]."""
    out = []
    for (W, b), (nW, nb) in zip(center, noise):
        Wb = torch.cat([W[None] + sigma * nW, W[None] - sigma * nW], 0)   # [2pop, in, out]
        bb = torch.cat([b[None] + sigma * nb, b[None] - sigma * nb], 0)
        out.append((Wb, bb))
    return out


def sample_noise(center, pop, gen, device):
    # gen is a CPU generator (MPS/CUDA generators are finicky); sample on CPU, move to device.
    return [(torch.randn(pop, *W.shape, generator=gen).to(device),
             torch.randn(pop, *b.shape, generator=gen).to(device)) for W, b in center]


def update(center, noise, fits, pop, sigma, lr):
    """Apply one ES step. fits: [2*pop]. Returns new center (list of (W,b))."""
    w = _centered_ranks(fits)
    wd = (w[:pop] - w[pop:])                                   # mirrored weights [pop]
    scale = lr / (2 * pop * sigma)
    new = []
    for (W, b), (nW, nb) in zip(center, noise):
        gW = (wd.reshape((pop,) + (1,) * W.dim()) * nW).sum(0)
        gb = (wd.reshape((pop,) + (1,) * b.dim()) * nb).sum(0)
        new.append((W + scale * gW, b + scale * gb))
    return new


def es_step(center, fitness, pop, gen, device, sigma=0.1, lr=0.05):
    """One ES iteration: sample, evaluate population, return (new_center, best_fit, center_fit_proxy)."""
    noise = sample_noise(center, pop, gen, device)
    stacked = perturb(center, noise, sigma)
    fits = fitness(stacked)                                    # [2*pop]
    new = update(center, noise, fits, pop, sigma, lr)
    return new, float(fits.max()), float(fits.mean())
