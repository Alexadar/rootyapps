"""Masked-categorical attention policy for Producer Tycoon.

Adapted from monstro/torchsim/policy_attn.py (single-query entity attention,
count-agnostic, -1e4 fp16-safe masking) with a discrete head split for
permutation-equivariance:

  q = self.Wq                                   [N,d]
  k,v = tok.Wk, tok.Wv                          [N,14,d]
  context = masked-attn(q, k, v)                [N,d]
  h  = relu([q; context].We + be)               [N,H]   (shared trunk)
  ht = relu([v_m; q].Wt + bt)                   [N,14,Ht] (per-token trunk)
  token verb logits = ht.Wu + bu                [N,14,6]  (release/tour/rehab/
                                                           fire/fulfill/sign)
  pooled logits     = h.Wg + bg                 [N,33]   (endWeek/reject/staff/
                                                          equip/upgrades)
  value             = h.Wval + bval             [N]

Assembled into the 95-id action layout of world_config, masked with -1e4
(NEVER finfo.min — the monstro CoreML/ANE war story), categorical sample.
Action heads (Wu, Wg) get 100x-smaller init (Andrychowicz et al. ICLR'21).
"""

import math

import torch

import world_config as W

# param order: [(Wq,bq),(Wk,bk),(Wv,bv),(We,be),(Wt,bt),(Wu,bu),(Wg,bg),(Wval,bval)]
N_POOLED = 2 + 2 * W.N_STAFF + W.N_EQUIP + 2                     # 33
N_VERBS = 6                                                       # 5 roster + sign

_SHAPES = lambda Fs, Fm, d, H, Ht: [
    (Fs, d), (Fm, d), (Fm, d), (2 * d, H),
    (2 * d, Ht), (Ht, N_VERBS), (H, N_POOLED), (H, 1),
]
ACTION_HEAD_IDX = (5, 6)   # Wu, Wg get the small init


def init_policy(Fs, Fm, d=32, H=128, Ht=64, device="cpu", seed=0, scale=0.1):
    g = torch.Generator().manual_seed(seed)
    params = []
    for idx, (i, o) in enumerate(_SHAPES(Fs, Fm, d, H, Ht)):
        s = scale * (0.01 if idx in ACTION_HEAD_IDX else 1.0)
        Wm = (torch.randn(i, o, generator=g) * s).to(device).requires_grad_(True)
        b = torch.zeros(o, device=device).requires_grad_(True)
        params.append((Wm, b))
    return params


def opt_params(params):
    return [w for wb in params for w in wb]


def snap(params):
    return [(Wm.detach().clone(), b.detach().clone()) for Wm, b in params]


def apply_policy(params, self_feat, tok_feat, present, action_mask):
    """-> (logits [N,95] masked, value [N]). present [N,14] floats,
    action_mask [N,95] bool."""
    (Wq, bq), (Wk, bk), (Wv, bv), (We, be), (Wt, bt), (Wu, bu), (Wg, bg), (Wval, bval) = params
    d = Wq.shape[1]
    q = self_feat @ Wq + bq                                       # [N,d]
    k = tok_feat @ Wk + bk                                        # [N,14,d]
    v = tok_feat @ Wv + bv                                        # [N,14,d]
    score = (k * q.unsqueeze(1)).sum(-1) / math.sqrt(d)           # [N,14]
    score = torch.where(present > 0.5, score, score.new_full((), W.MASK_NEG))
    score = score - score.max(-1, keepdim=True).values
    w = torch.exp(score) * present
    denom = w.sum(-1, keepdim=True)
    w = w / torch.where(denom <= 0, torch.ones_like(denom), denom)
    context = (w.unsqueeze(-1) * v).sum(1)                        # [N,d]

    h = torch.relu(torch.cat([q, context], -1) @ We + be)         # [N,H]
    qb = q.unsqueeze(1).expand_as(v)
    ht = torch.relu(torch.cat([v, qb], -1) @ Wt + bt)             # [N,14,Ht]
    verb = ht @ Wu + bu                                           # [N,14,6]
    pooled = h @ Wg + bg                                          # [N,33]
    value = (h @ Wval + bval).squeeze(-1)                         # [N]

    n = self_feat.shape[0]
    logits = self_feat.new_zeros(n, W.N_ACTIONS)
    logits[:, W.A_END_WEEK] = pooled[:, 0]
    logits[:, W.A_REJECT] = pooled[:, 1]
    logits[:, W.A_SIGN0] = verb[:, W.ROSTER_SLOTS, 5]
    logits[:, W.A_SIGN1] = verb[:, W.ROSTER_SLOTS + 1, 5]
    logits[:, W.A_RELEASE:W.A_RELEASE + 12] = verb[:, :12, 0]
    logits[:, W.A_TOUR:W.A_TOUR + 12] = verb[:, :12, 1]
    logits[:, W.A_REHAB:W.A_REHAB + 12] = verb[:, :12, 2]
    logits[:, W.A_FIRE:W.A_FIRE + 12] = verb[:, :12, 3]
    logits[:, W.A_FULFILL:W.A_FULFILL + 12] = verb[:, :12, 4]
    logits[:, W.A_HIRE:W.A_HIRE + 6] = pooled[:, 2:8]
    logits[:, W.A_FIRE_STAFF:W.A_FIRE_STAFF + 6] = pooled[:, 8:14]
    logits[:, W.A_BUY_EQUIP:W.A_BUY_EQUIP + W.N_EQUIP] = pooled[:, 14:31]
    logits[:, W.A_UPGRADE_STUDIO] = pooled[:, 31]
    logits[:, W.A_UPGRADE_LABEL] = pooled[:, 32]

    logits = torch.where(action_mask, logits, logits.new_full((), W.MASK_NEG))
    return logits, value


def sample(logits, rng=None):
    probs = torch.softmax(logits, dim=-1)
    return torch.multinomial(probs, 1, generator=rng).squeeze(1)


def logp_entropy(logits, actions):
    logp_all = torch.log_softmax(logits, dim=-1)
    logp = logp_all.gather(1, actions.unsqueeze(1)).squeeze(1)
    p = logp_all.exp()
    ent = -(p * logp_all).sum(-1)
    return logp, ent


def save(params, meta, path):
    import json
    out = {"kind": "producer-attn", **meta,
           "w": [Wm.detach().cpu().numpy().reshape(-1).tolist() for Wm, _ in params],
           "b": [b.detach().cpu().numpy().tolist() for _, b in params]}
    json.dump(out, open(path, "w"))


def load(path, device="cpu"):
    import json
    import numpy as np
    d = json.load(open(path))
    assert d.get("kind") == "producer-attn"
    shapes = _SHAPES(d["Fs"], d["Fm"], d["d"], d["H"], d["Ht"])
    params = [(torch.tensor(np.asarray(d["w"][i], np.float32).reshape(shapes[i]), device=device),
               torch.tensor(np.asarray(d["b"][i], np.float32), device=device))
              for i in range(len(shapes))]
    meta = {k: d[k] for k in ("Fs", "Fm", "d", "H", "Ht")}
    meta["obs_theta"] = d.get("obs_theta", False)
    return params, meta
