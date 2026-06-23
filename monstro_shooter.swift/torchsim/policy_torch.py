"""Torch MLP — same math as policy.py / GPUPolicy.swift (weights stored [in,out], relu chain then
linear). Functional apply so ES can batch a whole population by giving W shape [P,in,out] (a leading
population dim). JSON load/save uses the SAME {sizes,w,b} format → weights round-trip to MLX / Core ML.
"""
import json
import numpy as np
import torch


def init_mlp(sizes, device="cpu", seed=0, scale=0.1):
    g = torch.Generator().manual_seed(seed)
    params = []
    for i in range(1, len(sizes)):
        W = torch.randn(sizes[i - 1], sizes[i], generator=g) * scale
        b = torch.zeros(sizes[i])
        params.append((W.to(device), b.to(device)))
    return params


def apply_mlp(params, x, mm_dtype=None):
    """params: list of (W,b). Single net: W [in,out], x [...,in]. Batched population: W [P,in,out],
    x [P,N,in] -> [P,N,out] (torch.matmul broadcasts the batched P dim).
    mm_dtype (e.g. torch.bfloat16): run the matmuls in low precision and return fp32. The MLPs are the
    per-monster bottleneck (~43% of the tick) and MEMORY-bound, so bf16 halves their traffic -> ~1.3x on
    the full rollout. The SIM stays fp32 (only the policy forward is cast) — game logic is unaffected; this
    only changes the learned policy's training trajectory (and the parity checksum), so it's opt-in."""
    h = x if mm_dtype is None else x.to(mm_dtype)
    n = len(params)
    for i, (W, b) in enumerate(params):
        Wd, bd = (W, b) if mm_dtype is None else (W.to(mm_dtype), b.to(mm_dtype))
        h = torch.matmul(h, Wd) + (bd.unsqueeze(-2) if W.dim() == 3 else bd)
        if i < n - 1:
            h = torch.relu(h)
    return h if mm_dtype is None else h.float()


def apply_enemy(params, obs, mm_dtype=None):
    """Per-monster apply. obs [P,N,M,in]. Center params (W [in,out]) broadcast over P,N,M.
    Population params (W [P,in,out]) need N,M flattened so the batched matmul lines up with P."""
    W0 = params[0][0]
    if W0.dim() == 2:
        return apply_mlp(params, obs, mm_dtype)
    Pn, N, M, inp = obs.shape
    out = apply_mlp(params, obs.reshape(Pn, N * M, inp), mm_dtype)
    return out.reshape(Pn, N, M, -1)


def stack_population(params_list):
    """[net0_params, net1_params, ...] -> single params with a leading P dim on every W,b."""
    P = len(params_list)
    L = len(params_list[0])
    return [(torch.stack([params_list[p][l][0] for p in range(P)], 0),
             torch.stack([params_list[p][l][1] for p in range(P)], 0)) for l in range(L)]


def to_json(params, sizes, path):
    d = {"sizes": list(sizes),
         "w": [W.detach().cpu().numpy().reshape(-1).tolist() for W, _ in params],
         "b": [b.detach().cpu().numpy().tolist() for _, b in params]}
    json.dump(d, open(path, "w"))


def from_json(path, device="cpu"):
    d = json.load(open(path))
    sizes = d["sizes"]
    params = []
    for i in range(len(d["w"])):
        inc, outc = sizes[i], sizes[i + 1]
        W = torch.tensor(np.array(d["w"][i], np.float32).reshape(inc, outc), device=device)
        b = torch.tensor(np.array(d["b"][i], np.float32), device=device)
        params.append((W, b))
    return params, sizes


class MLPModule(torch.nn.Module):
    """nn.Module wrapper for Core ML export (torch.jit.trace / coremltools torch frontend)."""
    def __init__(self, params):
        super().__init__()
        self.ws = torch.nn.ParameterList([torch.nn.Parameter(W.clone(), requires_grad=False) for W, _ in params])
        self.bs = torch.nn.ParameterList([torch.nn.Parameter(b.clone(), requires_grad=False) for _, b in params])

    def forward(self, x):
        h = x
        n = len(self.ws)
        for i in range(n):
            h = torch.matmul(h, self.ws[i]) + self.bs[i]
            if i < n - 1:
                h = torch.relu(h)
        return h
