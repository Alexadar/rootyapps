"""Recurrent drone policy — now a GROUP brain: a masked SET self-attention over the alive drones (so the
swarm THINKS AS A GROUP) + a LEARNED per-drone TARGET ASSIGNMENT (bilinear affinity + self-excluded congestion
mean-field), feeding a per-drone single-query attention over the local entity tokens and a GRU latent.

Pipeline PER DRONE (batched over [P,N,D]):
    se        = relu(self_feat·Ws)                          # per-drone self/perception embedding
    context   = Σ softmax(q·k) v   over local top-K tokens  # reactive local context (unchanged)
    g1        = se + attn_over_ALIVE_DRONES(se)             # GROUP layer -> group-aware embedding
    L[d,e]    = bilinear(concat[g1,xy], enemy_encode)       # LEARNED drone->enemy affinity (no hand distance)
    a_soft/hard = congestion(L)                             # self-excluded anti-dogpile; a_hard = one-hot argmax
    tc        = a_soft · enemy_context ; focus = max_e a_soft
    e_t       = relu([q ; context ; tc ; focus]·We)
    h_t       = GRU(h_{t-1}, e_t) ; mu,value = heads(h_t)
    -> returns a_hard [P,N,D,E] (DETACHED one-hot) so the reward routes each drone's homing to its ONE target.

LONE-DRONE property (the key requirement): a_hard = onehot(argmax_e) is decisive at ANY E (never a centroid);
the congestion term load_excl = load - p is IDENTICALLY 0 for a single alive drone (self-cancels); and the group
softmax key-mask keeps the self-diagonal (eye) always valid so D_alive=1 is a well-defined self-transform, no NaN.

The masked softmaxes stay fp32; the GRU runs fp32. Matmuls may cast (mm_dtype).
"""
import math
import torch
import torch.nn.functional as F

_GRU_GATES = ("z", "r", "n")


def _softmax_e(z, e_mask):
    """Masked softmax over the last (ENEMY) axis. z [P,N,D,E], e_mask [P,N,E] -> [P,N,D,E]. Safe denom."""
    m = e_mask[:, :, None, :]                                                 # [P,N,1,E] broadcast over drones
    s = torch.where(m > 0.5, z, z.new_full((), -1e4))
    s = s - s.max(-1, keepdim=True).values
    w = torch.exp(s) * m
    denom = w.sum(-1, keepdim=True)
    return w / torch.where(denom <= 0, torch.ones_like(denom), denom)


def init_recur(Fs, Ft, d, H, act, device="cpu", seed=0, std0=0.5, scale=0.1, hover_bias=0.0,
               self_mag=None, self_scale=None, tok_mag=None, tok_scale=None, Fe=8):
    """H = encoder/GRU width; d = attention width (also the group/affinity/target-context width). Fe = per-enemy
    feature dim of the assignment's enemy set. Action head gets 100x-smaller init; hover_bias biases thrust to hover."""
    g = torch.Generator().manual_seed(seed)
    def W(i, o, s=scale):
        return (torch.randn(i, o, generator=g) * s).to(device).clone().detach().requires_grad_(True)
    def b(o):
        return torch.zeros(o, device=device).clone().detach().requires_grad_(True)
    p = {"Ws": W(Fs, H), "bs": b(H),                            # self/perception encoder
         "Wq": W(H, d), "bq": b(d), "Wk": W(Ft, d), "bk": b(d), "Wv": W(Ft, d), "bv": b(d),
         "We": W(3 * d + 1, H), "be": b(H)}                     # encoder input = [q; context; target-context(d); focus(1)]
    for gt in _GRU_GATES:                                        # GRU: input(e) and recurrent(h) maps per gate
        p["W" + gt] = W(H, H); p["U" + gt] = W(H, H); p["b" + gt] = b(H)
    p["Wp"] = W(H, act, scale * 0.01); p["bp"] = b(act)         # action head (small init)
    with torch.no_grad():
        p["bp"][0] = hover_bias                                 # thrust channel -> default hover, not climb
    p["Wval"] = W(H, 1); p["bval"] = b(1)
    # ---- GROUP LAYER (set self-attention over the alive drones) + LEARNED TARGET ASSIGNMENT ----
    p["Wq_g"] = W(H, d); p["Wk_g"] = W(H, d); p["Wv_g"] = W(H, d)   # group set-self-attention (drones attend to drones)
    p["Wo_g"] = W(d, H); p["bo_g"] = b(H)                            # group read-out back to H
    p["Wze"] = W(Fe, H); p["bze"] = b(H)                            # enemy-set encoder (enemy width = H)
    p["Wa"] = W(H + 2, d); p["Wb"] = W(H, d)                        # bilinear affinity: (group_embed + drone xy) x enemy
    p["Wtc"] = W(H, d)                                              # target-context read-out for the action head
    p["w_cong"] = torch.zeros((), device=device).clone().detach().requires_grad_(True)   # congestion weight (softplus>0)
    # ---- CONTROL GAINS for the differentiable velocity-tracking BASE controller (residual RL: Johannink et al.,
    #      arXiv:1812.03201; diff-sim residual Luo et al., arXiv:2410.03076). Learned scalar leaves, applied via
    #      F.softplus (stay positive+stable) INSIDE _core. Init = softplus^-1(physical) so softplus(leaf)=physical.
    #      Un-prefixed -> auto opt_params (SAPO grads) + snap + save/load. See CTRL_KEYS / ctrl_gains() below. ----
    _ctrl0 = {"v_cruise": 11.0, "tau": 0.1, "t_look": 0.2, "k_v": 2.0, "k_R": 10.0, "v_override": 5.5, "urgency_gain": 0.3}
    for _k, _v in _ctrl0.items():
        p["ctrl_" + _k] = torch.full((), math.log(math.expm1(_v)), device=device).clone().detach().requires_grad_(True)
    # LOT (learnable obs transform): asinh(g*(x-b)) on MAGNITUDE features (env emits them RAW). g,b learnable
    # per-feature vectors (init g=1/scale). _-prefixed masks are excluded from opt_params but saved/loaded.
    def _vec(x, n, fill): return (x if x is not None else torch.full((n,), fill)).to(device).clone().detach()
    ssc = _vec(self_scale, Fs, 1.0); tsc = _vec(tok_scale, Ft, 1.0)
    p["in_sg"] = (1.0 / ssc).requires_grad_(True); p["in_sb"] = b(Fs)
    p["in_tg"] = (1.0 / tsc).requires_grad_(True); p["in_tb"] = b(Ft)
    p["_self_mag"] = _vec(self_mag, Fs, 0.0); p["_tok_mag"] = _vec(tok_mag, Ft, 0.0)
    log_std = torch.full((act,), math.log(std0), device=device).clone().detach().requires_grad_(True)
    return p, log_std


CTRL_KEYS = ("v_cruise", "tau", "t_look", "k_v", "k_R", "v_override", "urgency_gain")   # base-controller gains


def ctrl_gains(params):
    """View {name: raw_leaf} of the base-controller gains (softplus applied in _core). Env reads this so the
    gains train via SAPO's analytic gradient through the differentiable sim, and save/load with the model."""
    return {k: params["ctrl_" + k] for k in CTRL_KEYS}


def opt_params(params, log_std):
    return [v for k, v in params.items() if not k.startswith("_")] + [log_std]   # skip _-prefixed constants (LOT masks)


def mean_params(params):
    return {k: v.detach() for k, v in params.items()}


def snap(params, log_std):
    return ({k: v.detach().clone() for k, v in params.items()}, log_std.detach().clone())


def apply_recur(params, self_feat, tokens, mask, enemy_feat, e_mask, d_mask, dp_xy, h_prev, mm_dtype=None):
    """self_feat [P,N,D,Fs], tokens [P,N,D,K,Ft], mask [P,N,D,K], enemy_feat [P,N,E,Fe], e_mask [P,N,E],
    d_mask [P,N,D], dp_xy [P,N,D,2] -> (mu, value, h_new, a_hard [P,N,D,E] DETACHED one-hot target per drone)."""
    p = params
    d = p["Wq"].shape[1]
    cast = (lambda x: x.to(mm_dtype)) if mm_dtype is not None else (lambda x: x)
    # LOT: learnable per-feature normalizer on RAW magnitude features (asinh; no dead-gradient clamp). fp32, pre-cast.
    if "in_sg" in p:
        sm, tm = p["_self_mag"], p["_tok_mag"]
        self_feat = torch.where(sm > 0.5, torch.asinh(p["in_sg"] * (self_feat - p["in_sb"])), self_feat)
        tokens = torch.where(tm > 0.5, torch.asinh(p["in_tg"] * (tokens - p["in_tb"])), tokens)
    sf, mf = cast(self_feat), cast(tokens)
    se = torch.relu(torch.matmul(sf, cast(p["Ws"])) + cast(p["bs"]))          # [P,N,D,H] per-drone self embedding
    # --- LOCAL reactive context: per-drone single-query attention over the top-K entity tokens (unchanged) ---
    q = torch.matmul(se, cast(p["Wq"])) + cast(p["bq"])          # [P,N,D,d]
    k = torch.matmul(mf, cast(p["Wk"])) + cast(p["bk"])          # [P,N,D,K,d]
    v = torch.matmul(mf, cast(p["Wv"])) + cast(p["bv"])
    score = (k * q.unsqueeze(-2)).sum(-1).float() / math.sqrt(d)              # fp32 softmax
    score = torch.where(mask > 0.5, score, score.new_full((), -1e4))
    score = score - score.max(-1, keepdim=True).values
    w = torch.exp(score) * mask
    denom = w.sum(-1, keepdim=True)
    w = w / torch.where(denom <= 0, torch.ones_like(denom), denom)
    context = (cast(w[..., None]) * v).sum(-2)                                # [P,N,D,d]
    # --- GROUP LAYER: masked SET self-attention over the ALIVE-DRONE axis (fp32; D,E are small) ---
    seg = se.float()                                                         # [P,N,D,H]
    Dn = seg.shape[-2]
    Qd = torch.matmul(seg, p["Wq_g"]); Kd = torch.matmul(seg, p["Wk_g"]); Vd = torch.matmul(seg, p["Wv_g"])  # [P,N,D,d]
    S = torch.einsum('pnid,pnjd->pnij', Qd, Kd) / math.sqrt(d)               # [P,N,D,D]
    eye = torch.eye(Dn, device=seg.device)[None, None]                      # [1,1,D,D] self-diagonal
    km = torch.maximum(d_mask[:, :, None, :], eye)                          # [P,N,D,D] alive keys + always self
    S = torch.where(km > 0.5, S, S.new_full((), -1e4))
    S = S - S.max(-1, keepdim=True).values
    wS = torch.exp(S) * km
    wS = wS / torch.where(wS.sum(-1, keepdim=True) <= 0, torch.ones_like(wS[..., :1]), wS.sum(-1, keepdim=True))
    g1 = seg + torch.relu(torch.matmul(torch.einsum('pnij,pnjd->pnid', wS, Vd), p["Wo_g"]) + p["bo_g"])   # [P,N,D,H]
    # --- LEARNED ASSIGNMENT: bilinear affinity + self-excluded congestion mean-field (fp32) ---
    ze = torch.relu(torch.matmul(enemy_feat.float(), p["Wze"]) + p["bze"])   # [P,N,E,H]
    qa = torch.matmul(torch.cat([g1, dp_xy.float()], -1), p["Wa"])          # [P,N,D,d]
    ka = torch.matmul(ze, p["Wb"])                                          # [P,N,E,d]
    L = torch.einsum('pndh,pneh->pnde', qa, ka) / math.sqrt(d)             # [P,N,D,E] learned drone->enemy logits
    em = e_mask[:, :, None, :]                                             # [P,N,1,E]
    L = torch.where(em > 0.5, L, L.new_full((), -1e4))
    z = L
    for _ in range(2):                                                     # GROUP-CONGEST-UNROLL-OK (fixed 2 rounds)
        pe = _softmax_e(z, e_mask) * d_mask[..., None]                     # [P,N,D,E] each drone's soft claim (0 if dead)
        load = pe.sum(2)                                                   # [P,N,E] total teammate claim per enemy
        z = L - F.softplus(p["w_cong"]) * (load[:, :, None, :] - pe)       # self-EXCLUDED -> vanishes for a lone drone
    a_soft = _softmax_e(z, e_mask)                                         # [P,N,D,E] differentiable target distribution
    z_al = torch.where(em > 0.5, z, z.new_full((), -1e9))
    a_hard = (z_al >= z_al.max(-1, keepdim=True).values).float() * em     # [P,N,D,E] one-hot over an ALIVE enemy
    a_hard = a_hard / torch.where(a_hard.sum(-1, keepdim=True) <= 0, torch.ones_like(a_hard[..., :1]), a_hard.sum(-1, keepdim=True))
    a_hard = a_hard.detach()                                              # DETACHED -> reward routing carries no gradient
    # --- ACTION: fold the (soft) assigned target into the encoder input ---
    tc = torch.einsum('pnde,pneh->pndh', a_soft, torch.matmul(ze, p["Wtc"]))   # [P,N,D,d] target context
    focus = a_soft.amax(-1, keepdim=True)                                     # [P,N,D,1] how committed (1 = decisive)
    e = torch.relu(torch.matmul(torch.cat([q, context, cast(tc), cast(focus)], -1), cast(p["We"])) + cast(p["be"])).float()
    # GRU cell (fp32)
    h = h_prev
    zg = torch.sigmoid(torch.matmul(e, p["Wz"]) + torch.matmul(h, p["Uz"]) + p["bz"])
    rg = torch.sigmoid(torch.matmul(e, p["Wr"]) + torch.matmul(h, p["Ur"]) + p["br"])
    ng = torch.tanh(torch.matmul(e, p["Wn"]) + torch.matmul(rg * h, p["Un"]) + p["bn"])
    h_new = (1.0 - zg) * ng + zg * h
    mu = torch.matmul(h_new, p["Wp"]) + p["bp"]
    val = (torch.matmul(h_new, p["Wval"]) + p["bval"]).squeeze(-1)
    return mu.float(), val.float(), h_new, a_hard


def save_safetensors(params, log_std, meta, path):
    """Save the recurrent policy as SAFETENSORS: param tensors (by name) + log_std, meta (kind + dims) as JSON header."""
    import json
    from safetensors.torch import save_file
    t = {k: v.detach().cpu().contiguous() for k, v in params.items()}
    t["log_std"] = log_std.detach().cpu().contiguous()
    save_file(t, path, metadata={"kind": "recurrent", "meta": json.dumps(meta)})


def load_safetensors(path, device="cpu"):
    import json
    from safetensors import safe_open
    t = {}
    with safe_open(path, framework="pt", device=device) as f:
        hdr = f.metadata()
        for k in f.keys():                                         # OFFLINE loop (not the sim hot path)
            t[k] = f.get_tensor(k)
    assert hdr.get("kind") == "recurrent", "not a recurrent policy safetensors"
    log_std = t.pop("log_std")
    return t, log_std, json.loads(hdr["meta"])
