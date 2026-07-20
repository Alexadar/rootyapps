# Copied VERBATIM (via froggo.swift/torchsim/policy_attn.py) from monstro_shooter.swift/torchsim/policy_attn.py
# @ ec6a855e — game-agnostic single-query cross-attention. THIRD game to reuse it unchanged; do not fork.
# droneswarm uses it for BOTH sides: the drone brain (self=drone IMU, tokens=nearest drones+enemies) and the
# enemy brain (self=unit state, tokens=nearest drones). count-agnostic masked softmax handles variable
# alive counts; small-init action head; fp16-safe softmax. See oracles/SOURCES not needed here (pure ML).
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
    for idx, (i, o) in enumerate(_SHAPES(Fs, Fm, d, H, act)):
        # ACTION head (idx 4 = (H,act) = Wp) gets 100x-smaller init (Andrychowicz et al. ICLR'21: near-zero,
        # observation-independent initial actions, +66% on Humanoid). With b=0 the initial policy outputs ~0:
        # move=tanh(0)=still, aim direction driven by exploration noise instead of a random ENTRENCHED direction
        # — directly targets the fixed-direction aim collapse. Trunk + value head keep the normal scale.
        s = scale * (0.01 if idx == 4 else 1.0)
        W = (torch.randn(i, o, generator=g) * s).to(device).clone().detach().requires_grad_(True)
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
    # fp16-SAFE masked-softmax constant (this was the ONLY fp16-unsafe spot in this forward). finfo.float32.min
    # ≈ -3.4e38 is OUT of fp16 range (±65504), so on Core ML/ANE it overflowed to -Inf; a fully-masked row then
    # did -Inf - (-Inf) = NaN -> exp(NaN) = NaN, and NaN·alive(=0) = NaN (not 0), which the denom guard below
    # (NaN<=0 is False) does NOT catch -> garbage action. -1e4 is finite in fp16 AND fp32, and exp(-1e4) underflows
    # to exactly 0 in both, so the masked-softmax result is byte-identical to the old finfo.min on fp32 (training
    # & parity unchanged) while staying clean on ANE/fp16. Do NOT raise toward finfo.min "for sharper masking".
    neg = -1e4
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


def save_safetensors(params, log_std, meta, path):
    """Save the attention policy as SAFETENSORS. params is a LIST of (W,b) tuples -> flatten to w0/b0/w1/b1...
    (safetensors needs a flat tensor dict); meta = {Fs,Fm,d,H,act} + count go in the JSON header."""
    import json
    from safetensors.torch import save_file
    t = {}
    for i, (W, b) in enumerate(params):                            # OFFLINE loop (serialization, not the sim)
        t[f"w{i}"] = W.detach().cpu().contiguous(); t[f"b{i}"] = b.detach().cpu().contiguous()
    t["log_std"] = log_std.detach().cpu().contiguous()
    save_file(t, path, metadata={"kind": "attention", "meta": json.dumps(meta), "n": str(len(params))})


def load_safetensors(path, device="cpu"):
    import json
    from safetensors import safe_open
    t = {}
    with safe_open(path, framework="pt", device=device) as f:
        hdr = f.metadata()
        for k in f.keys():
            t[k] = f.get_tensor(k)
    assert hdr.get("kind") == "attention", "not an attention policy safetensors"
    n = int(hdr["n"])
    params = [(t[f"w{i}"], t[f"b{i}"]) for i in range(n)]          # rebuild the (W,b) list in order
    return params, t["log_std"], json.loads(hdr["meta"])
