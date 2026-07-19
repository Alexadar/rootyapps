"""Recurrent drone policy — single-query spatial attention (over the entity tokens) feeding a GRU
LATENT that encodes each drone's history. The point (user's design): don't stack raw past frames —
compress the trajectory into a compact recurrent state h_t = GRU(h_{t-1}, encode(obs_t)), so the
drone can anticipate motion (accel / a target's jinking) that a single frame can't show.

Pipeline PER DRONE (all batched over [P,N,D]):
    q,k,v      from self_feat / tokens        (same masked single-query attention as policy_attn)
    context    = Σ softmax(q·k) v
    e_t        = relu([q ; context]·We)        # spatial encoding of THIS frame
    h_t        = GRU(h_{t-1}, e_t)             # temporal latent (encodes history)
    mu, value  = heads(h_t)

Only the DRONE is recurrent (it is the side that must time a dive); the enemy stays feedforward
(policy_attn). The hidden state h is carried across DECISIONS by the driver (game_loop threads it,
resetting inactive/just-spawned drones to zero). PPO trains it truncation-1: the stored h_in is
detached in the update, so the GRU learns a good one-step latent update without full BPTT.

The masked softmax stays fp32 (fp16-unsafe); the GRU runs fp32 (small, stability). Matmuls may cast.
"""
import math
import torch

_GRU_GATES = ("z", "r", "n")


def init_recur(Fs, Ft, d, H, act, device="cpu", seed=0, std0=0.5, scale=0.1, hover_bias=0.0):
    """H = attention-encoder width AND GRU hidden width. Action head gets 100x-smaller init
    (Andrychowicz: near-zero initial actions -> exploration not an entrenched direction). hover_bias
    biases the THRUST channel so the DEFAULT action hovers (thrust=mg) — else the small-init head
    outputs thrust=0.5*t_max (a climb), so an untrained drone flies UP and never learns to cut thrust
    and descend onto a ground target (diagnosed in the tiny env: drones got over the enemy but never
    descended the last 7.5 m)."""
    g = torch.Generator().manual_seed(seed)
    def W(i, o, s=scale):
        return (torch.randn(i, o, generator=g) * s).to(device).clone().detach().requires_grad_(True)
    def b(o):
        return torch.zeros(o, device=device).clone().detach().requires_grad_(True)
    p = {"Ws": W(Fs, H), "bs": b(H),                            # self/perception encoder (compresses the 192-ray depth grid + base)
         "Wq": W(H, d), "bq": b(d), "Wk": W(Ft, d), "bk": b(d), "Wv": W(Ft, d), "bv": b(d),
         "We": W(2 * d, H), "be": b(H)}
    for gt in _GRU_GATES:                                        # GRU: input(e) and recurrent(h) maps per gate
        p["W" + gt] = W(H, H); p["U" + gt] = W(H, H); p["b" + gt] = b(H)
    p["Wp"] = W(H, act, scale * 0.01); p["bp"] = b(act)         # action head (small init)
    with torch.no_grad():
        p["bp"][0] = hover_bias                                 # thrust channel -> default hover, not climb
    p["Wval"] = W(H, 1); p["bval"] = b(1)
    log_std = torch.full((act,), math.log(std0), device=device).clone().detach().requires_grad_(True)
    return p, log_std


def opt_params(params, log_std):
    return list(params.values()) + [log_std]


def mean_params(params):
    return {k: v.detach() for k, v in params.items()}


def snap(params, log_std):
    return ({k: v.detach().clone() for k, v in params.items()}, log_std.detach().clone())


def apply_recur(params, self_feat, tokens, mask, h_prev, mm_dtype=None):
    """self_feat [...,Fs], tokens [...,K,Ft], mask [...,K], h_prev [...,H] -> (mu [...,act], value [...],
    h_new [...,H]). '...' is the per-drone batch [P,N,D]. Masked single-query attention -> GRU."""
    p = params
    d = p["Wq"].shape[1]
    cast = (lambda x: x.to(mm_dtype)) if mm_dtype is not None else (lambda x: x)
    sf, mf = cast(self_feat), cast(tokens)
    se = torch.relu(torch.matmul(sf, cast(p["Ws"])) + cast(p["bs"]))          # self/perception encoder [...,H] (encodes depth grid)
    q = torch.matmul(se, cast(p["Wq"])) + cast(p["bq"])          # [...,d]  query from the encoded self-embedding
    k = torch.matmul(mf, cast(p["Wk"])) + cast(p["bk"])          # [...,K,d]
    v = torch.matmul(mf, cast(p["Wv"])) + cast(p["bv"])
    score = (k * q.unsqueeze(-2)).sum(-1).float() / math.sqrt(d)              # fp32 softmax
    score = torch.where(mask > 0.5, score, score.new_full((), -1e4))         # fp16-safe mask
    score = score - score.max(-1, keepdim=True).values
    w = torch.exp(score) * mask
    denom = w.sum(-1, keepdim=True)
    w = w / torch.where(denom <= 0, torch.ones_like(denom), denom)
    context = (cast(w[..., None]) * v).sum(-2)                                # [...,d]
    e = torch.relu(torch.matmul(torch.cat([q, context], -1), cast(p["We"])) + cast(p["be"])).float()  # [...,H]
    # GRU cell (fp32)
    h = h_prev
    z = torch.sigmoid(torch.matmul(e, p["Wz"]) + torch.matmul(h, p["Uz"]) + p["bz"])
    r = torch.sigmoid(torch.matmul(e, p["Wr"]) + torch.matmul(h, p["Ur"]) + p["br"])
    n = torch.tanh(torch.matmul(e, p["Wn"]) + torch.matmul(r * h, p["Un"]) + p["bn"])
    h_new = (1.0 - z) * n + z * h
    mu = torch.matmul(h_new, p["Wp"]) + p["bp"]
    val = (torch.matmul(h_new, p["Wval"]) + p["bval"]).squeeze(-1)
    return mu.float(), val.float(), h_new


def save_safetensors(params, log_std, meta, path):
    """Save the recurrent policy as SAFETENSORS: the param tensors (by name) + log_std, with the scalar
    meta (kind + Fs/Ft/d/H/act) as JSON in the header. Zero-copy, mmap-able, safe (no pickle/eval)."""
    import json
    from safetensors.torch import save_file
    t = {k: v.detach().cpu().contiguous() for k, v in params.items()}
    t["log_std"] = log_std.detach().cpu().contiguous()
    save_file(t, path, metadata={"kind": "recurrent", "meta": json.dumps(meta)})


def load_safetensors(path, device="cpu"):
    import json
    from safetensors import safe_open
    t = {}
    with safe_open(path, framework="pt", device=device) as f:      # one pass: header + tensors, on-device
        hdr = f.metadata()
        for k in f.keys():                                         # OFFLINE loop (not the sim hot path)
            t[k] = f.get_tensor(k)
    assert hdr.get("kind") == "recurrent", "not a recurrent policy safetensors"
    log_std = t.pop("log_std")
    return t, log_std, json.loads(hdr["meta"])
