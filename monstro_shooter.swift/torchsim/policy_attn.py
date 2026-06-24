"""Single-query cross-attention player policy (the surroundings-aware upgrade to the 8-dim MLP).

The MLP player saw ONE pre-summed threat vector → it could only learn a near-fixed move+aim. This policy
instead takes the per-monster SET obs from `env.player_set_obs` (self_feat [P,N,Fs] + mon_feat [P,N,M,Fm] +
alive mask) and runs ONE query (from the player's own state) over the M monster keys/values:

    q = self·Wq ;  k = mon·Wk ;  v = mon·Wv
    score_m = q·k_m / sqrt(d)        # one dot per monster — O(M), NOT O(M^2)
    w = softmax(score, masked by alive)   # learned per-target WEIGHTS (the "selector")
    context = Σ w_m·v_m              # weighted blend; per-monster v preserves individuals
    h = relu([q ; context]·We) ; mu = h·Wp ; value = h·Wval

This is the AlphaStar-style entity-attention / permutation-invariant set idea, single-query so it's linear
in monster count and count-AGNOSTIC (the mask makes 3 or 16 alive behave identically up to the M capacity).
Shared encoder + two heads (policy mu, value) → one param set, trained with PPO (ppo_attn.py). The enemy
stays MLP. Deploy/Swift can't consume `kind:attention` JSON yet — Core ML export is out of scope here.
"""
import math
import torch

# param order (all 2-D leaf tensors, broadcast over the [P,N] batch — NOT population-stacked):
#   [(Wq,bq),(Wk,bk),(Wv,bv),(We,be),(Wp,bp),(Wval,bval)] + log_std[act]
_SHAPES = lambda Fs, Fm, d, H, act: [(Fs, d), (Fm, d), (Fm, d), (2 * d, H), (H, act), (H, 1)]


def init_attn(Fs, Fm, d, H, act, device="cpu", seed=0, std0=0.5, scale=0.1):
    g = torch.Generator().manual_seed(seed)
    params = []
    for (i, o) in _SHAPES(Fs, Fm, d, H, act):
        W = (torch.randn(i, o, generator=g) * scale).to(device).clone().detach().requires_grad_(True)
        b = torch.zeros(o, device=device).clone().detach().requires_grad_(True)
        params.append((W, b))
    log_std = torch.full((act,), math.log(std0), device=device).clone().detach().requires_grad_(True)
    return params, log_std


def opt_params(params, log_std):
    return [w for wb in params for w in wb] + [log_std]


def mean_params(params):
    return [(W.detach(), b.detach()) for W, b in params]


def snap(params):
    return [(W.detach().clone(), b.detach().clone()) for W, b in params]


def apply_attn(params, self_feat, mon_feat, alive, mm_dtype=None):
    """self_feat [P,N,Fs], mon_feat [P,N,M,Fm], alive [P,N,M] -> (mu [P,N,act], value [P,N]).
    Matmuls optionally in mm_dtype (bf16); the masked softmax ALWAYS runs in fp32 (bf16 exp + finfo.min
    are numerically unsafe). Single query over M; masked so dead/absent monster slots get zero weight."""
    (Wq, bq), (Wk, bk), (Wv, bv), (We, be), (Wp, bp), (Wval, bval) = params
    d = Wq.shape[1]
    cast = (lambda x: x.to(mm_dtype)) if mm_dtype is not None else (lambda x: x)
    sf, mf = cast(self_feat), cast(mon_feat)
    q = torch.matmul(sf, cast(Wq)) + cast(bq)                    # [P,N,d]
    k = torch.matmul(mf, cast(Wk)) + cast(bk)                    # [P,N,M,d]
    v = torch.matmul(mf, cast(Wv)) + cast(bv)                    # [P,N,M,d]
    score = (k * q.unsqueeze(-2)).sum(-1).float() / math.sqrt(d)             # [...,M] -> fp32 for the softmax
    # ⚠ Core ML / fp16 EXPORT CLIFF (the ONLY fp16-unsafe spot in this forward — everything else runs on
    # normalized ~O(1) values that fp16 handles). finfo.float32.min ≈ -3.4e38 is OUT of fp16 range (±65504),
    # so on ANE/fp16 it overflows to -Inf; a fully-masked row then does -Inf - (-Inf) = NaN -> exp(NaN) = NaN,
    # and NaN·alive(=0) = NaN (not 0), which the denom guard below (NaN<=0 is False) does NOT catch -> the
    # softmax/context goes NaN -> garbage action. fp32 is clean (finite const: -3.4e38 - -3.4e38 = 0). When we
    # export to Core ML, FIX this one line for fp16-safety: either pin the export to fp32/CPU, or swap finfo.min
    # for a finite fp16-safe const like -1e4 (exp(-1e4)=0 identically in fp16 AND fp32, so training is unchanged).
    neg = torch.finfo(torch.float32).min
    score = torch.where(alive > 0.5, score, score.new_full((), neg))        # mask dead (finfo.min, not -inf)
    score = score - score.max(-1, keepdim=True).values                      # stability
    w = torch.exp(score) * alive                                            # zero dead rows explicitly
    denom = w.sum(-1, keepdim=True)                                         # [P,N,1]
    w = w / torch.where(denom <= 0, torch.ones_like(denom), denom)          # all-dead -> w=0 (context=0, safe)
    context = (cast(w[..., None]) * v).sum(-2)                              # [...,d]  (sum over M)
    h = torch.relu(torch.matmul(torch.cat([q, context], -1), cast(We)) + cast(be))   # [P,N,H]
    mu = torch.matmul(h, cast(Wp)) + cast(bp)                               # [P,N,act]
    val = (torch.matmul(h, cast(Wval)) + cast(bval)).squeeze(-1)            # [P,N]
    return mu.float(), val.float()


class AttnDeployModule(torch.nn.Module):
    """CONVERSION-ONLY (export scaffolding — not training, not runtime). Wraps the forward so torch.jit.trace
    can capture it for Core ML; at runtime the *Core ML model* does inference in Swift, not this module.
    Fixed-M, single-player forward for Core ML export. REUSES apply_attn so the deployed math is
    bit-identical to training (no reimplementation = no torch-vs-CoreML drift). Inputs are one tick for
    one player: self_feat [Fs], mon_feat [M, Fm], alive [M] (1=live slot, 0=dead/empty). Output: mu [act]
    — the MEAN action (value head + log_std are training-only, dropped at deploy). M is the fixed slot
    capacity; mask the unused slots and the masked softmax gives them zero weight (count-agnostic)."""

    def __init__(self, params):
        super().__init__()
        self._n = len(params)
        for i, (W, b) in enumerate(params):
            self.register_buffer(f"W{i}", W.detach().clone().float())
            self.register_buffer(f"b{i}", b.detach().clone().float())

    def forward(self, self_feat, mon_feat, alive):
        params = [(getattr(self, f"W{i}"), getattr(self, f"b{i}")) for i in range(self._n)]
        sf = self_feat.unsqueeze(0).unsqueeze(0)        # [1,1,Fs]
        mf = mon_feat.unsqueeze(0).unsqueeze(0)         # [1,1,M,Fm]
        al = alive.unsqueeze(0).unsqueeze(0)            # [1,1,M]
        mu, _ = apply_attn(params, sf, mf, al)          # mu [1,1,act]
        return mu.reshape(-1)                           # [act]


def numpy_forward(params_np, log_std, meta, self_feat, mon_feat, alive):
    """CONVERSION-ONLY (export-time parity oracle — does NOT ship / does NOT run in the game). torch-free
    numpy mirror of apply_attn (mean head only), used to check the converted Core ML model didn't drift
    when the env can't run CoreML.predict. params_np = list of (W[in,out], b[out]) numpy arrays."""
    import numpy as np
    (Wq, bq), (Wk, bk), (Wv, bv), (We, be), (Wp, bp), _value_head = params_np   # value head dropped at deploy
    d = Wq.shape[1]
    q = self_feat @ Wq + bq                              # [d]
    k = mon_feat @ Wk + bk                               # [M,d]
    v = mon_feat @ Wv + bv                               # [M,d]
    score = (k * q[None, :]).sum(-1) / np.sqrt(d)        # [M]
    score = np.where(alive > 0.5, score, np.finfo(np.float32).min)
    score = score - score.max()
    w = np.exp(score) * alive
    denom = w.sum()
    w = w / (denom if denom > 0 else 1.0)
    context = (w[:, None] * v).sum(0)                    # [d]
    h = np.maximum(np.concatenate([q, context]) @ We + be, 0.0)   # [H]
    return (h @ Wp + bp).astype(np.float32)              # [act]


def to_json(params, log_std, meta, path):
    """meta = {Fs,Fm,d,H,act}. Discriminated JSON (kind=attention) — distinct from the MLP {sizes,w,b}."""
    import json
    out = {"kind": "attention", **meta,
           "w": [W.detach().cpu().numpy().reshape(-1).tolist() for W, _ in params],
           "b": [b.detach().cpu().numpy().tolist() for _, b in params],
           "log_std": log_std.detach().cpu().numpy().tolist()}
    json.dump(out, open(path, "w"))


def from_json(path, device="cpu"):
    import json
    import numpy as np
    d = json.load(open(path))
    assert d.get("kind") == "attention", "not an attention policy json"
    shapes = _SHAPES(d["Fs"], d["Fm"], d["d"], d["H"], d["act"])
    params = [(torch.tensor(np.asarray(d["w"][i], np.float32).reshape(shapes[i]), device=device),
               torch.tensor(np.asarray(d["b"][i], np.float32), device=device)) for i in range(len(shapes))]
    log_std = torch.tensor(np.asarray(d["log_std"], np.float32), device=device)
    meta = {k: d[k] for k in ("Fs", "Fm", "d", "H", "act")}
    return params, log_std, meta
