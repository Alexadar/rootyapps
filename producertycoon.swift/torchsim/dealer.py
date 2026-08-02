"""Learned artist DEALER — a tiny population-batched attention generator.

The stream of weekly candidate artists is the game's real "content". The
dealer replaces the i.i.d. artist bank for candidate slots: conditioned on
[difficulty d, week, game summary] and a K=8 memory of its own recent deals
(single-query attention over them — the proven policy_attn pattern), it emits
distribution parameters for the next candidate pair and samples artists.

Population-batched: all weight matrices carry a leading [P] dim (ES
perturbations), einsum 'pni,pio->pno' — the monstro ES pattern. ~3k params.

Artist parameterization (what the env needs per artist):
  stats[9] (10..90), genre id, archetype id, trait_score, trait_chaos, text_fit.
text_fit is sampled from the measured histogram (not learned — it's a
constant of the text corpus, not a design lever).
"""

import math

import torch

import world_config as W

CTX_DIM = 8          # d, week/480, log-fans, money-log, roster/12, mean-exp/100, tokens/8, 1
MEM_K = 8            # remembered deals
ART_DIM = 20         # 9 stats/80 + genre-oh 6? -> compact: 9 stats + genre/6 + arch/8 + ts/10 + tc/10 -> use 13
# per-candidate output block: 9 stat means + 9 stat log-sigmas + 6 genre logits
# + 8 archetype logits + trait_score (mu, sig) + trait_chaos (mu, sig) = 36
OUT_PER_CAND = 36
D_EMB = 16

# memory token = (game state at deal time, what was dealt) — the user's qkv
# schema: k = game state, q = "what to deal now", v = deal-in-that-state.
# 8 ctx dims (session snapshot) + 13 dealt-artist dims = 21. Attending by
# state similarity lets the dealer see the session TRAJECTORY (how fast this
# player converts what it's given) — the difficulty-inference signal.
MEM_DIM = CTX_DIM + 13

_SHAPES = {
    "Wm": (MEM_DIM, D_EMB), "bm": (D_EMB,),
    "Wq": (CTX_DIM, D_EMB), "bq": (D_EMB,),
    "Wv": (MEM_DIM, D_EMB), "bv": (D_EMB,),
    "Wh": (2 * D_EMB, 32), "bh": (32,),
    "Wo": (32, 2 * OUT_PER_CAND), "bo": (2 * OUT_PER_CAND,),
}
N_PARAMS = sum(int(torch.tensor(s).prod()) for s in _SHAPES.values())


def _param_offsets():
    out, i = {}, 0
    for k, sh in _SHAPES.items():
        n = int(torch.tensor(sh).prod())
        out[k] = (i, i + n)
        i += n
    return out


def init_dealer(pop: int, device="cuda", seed=0, scale=0.1) -> torch.Tensor:
    """Flat [P, N_PARAMS]. Output biases are set so the UNTRAINED dealer deals
    bank-like artists (stat sigma ~12, mid means) — ES then shapes difficulty
    down from a working game instead of up from a dead one (random init deals
    N(50, sigma=1) artists: the agent never wins, fitness gradient ~ flat)."""
    g = torch.Generator().manual_seed(seed)
    flat = torch.randn(pop, N_PARAMS, generator=g) * scale
    off = _param_offsets()["bo"][0]
    for cand in (0, 1):
        base = off + cand * OUT_PER_CAND
        flat[:, base + 9: base + 18] = 12.0    # stat log-sigma -> softplus ~ 12
        flat[:, base + 33] = 2.0               # trait_score sigma ~ 2
        flat[:, base + 35] = 1.0               # trait_chaos sigma ~ 1
    return flat.to(device)


def _unflatten(flat: torch.Tensor) -> dict:
    out, i = {}, 0
    P = flat.shape[0]
    for k, sh in _SHAPES.items():
        n = int(torch.tensor(sh).prod())
        out[k] = flat[:, i:i + n].view(P, *sh)
        i += n
    return out


class DealerState:
    """Per-env deal memory ring [N, K, MEM_DIM] + write cursor."""

    def __init__(self, n, device):
        self.mem = torch.zeros(n, MEM_K, MEM_DIM, device=device)
        self.used = torch.zeros(n, MEM_K, device=device)

    def reset(self, mask):
        m = mask.view(-1, 1, 1)
        self.mem = torch.where(m.expand_as(self.mem), torch.zeros_like(self.mem), self.mem)
        self.used = torch.where(mask.view(-1, 1).expand_as(self.used),
                                torch.zeros_like(self.used), self.used)

    def push(self, artists_feat, env_mask):
        """artists_feat [N,2,MEM_DIM]; shift ring left by 2, append."""
        new_mem = torch.cat([self.mem[:, 2:], artists_feat], dim=1)
        new_used = torch.cat([self.used[:, 2:], torch.ones_like(self.used[:, :2])], dim=1)
        m = env_mask.view(-1, 1, 1)
        self.mem = torch.where(m.expand_as(self.mem), new_mem, self.mem)
        self.used = torch.where(env_mask.view(-1, 1).expand_as(self.used), new_used, self.used)


def dealer_forward(flat, ctx, mem, used):
    """flat [P,D], ctx [P,S,CTX_DIM], mem [P,S,K,MEM_DIM], used [P,S,K]
    -> raw output [P,S,2*OUT_PER_CAND]."""
    p = _unflatten(flat)
    q = torch.einsum("psi,pio->pso", ctx, p["Wq"]) + p["bq"].unsqueeze(1)          # [P,S,d]
    k = torch.einsum("pski,pio->psko", mem, p["Wm"]) + p["bm"].unsqueeze(1).unsqueeze(1)
    v = torch.einsum("pski,pio->psko", mem, p["Wv"]) + p["bv"].unsqueeze(1).unsqueeze(1)
    score = (k * q.unsqueeze(2)).sum(-1) / math.sqrt(D_EMB)                        # [P,S,K]
    score = torch.where(used > 0.5, score, score.new_full((), W.MASK_NEG))
    score = score - score.max(-1, keepdim=True).values
    w = torch.exp(score) * used
    denom = w.sum(-1, keepdim=True)
    w = w / torch.where(denom <= 0, torch.ones_like(denom), denom)
    context = (w.unsqueeze(-1) * v).sum(2)                                          # [P,S,d]
    h = torch.relu(torch.einsum("psi,pio->pso", torch.cat([q, context], -1), p["Wh"])
                   + p["bh"].unsqueeze(1))
    return torch.einsum("psi,pio->pso", h, p["Wo"]) + p["bo"].unsqueeze(1)          # [P,S,72]


def sample_artists(raw, gen, text_fit_sampler):
    """raw [P,S,2*OUT_PER_CAND] -> dict of [P*S*2] artist fields + mem feats [P,S,2,MEM_DIM].
    Bounded decode: stat mu in 10..90 via sigmoid, sigma in 1..15 via softplus-clamp."""
    P, S, _ = raw.shape
    r = raw.view(P, S, 2, OUT_PER_CAND)
    mu = torch.sigmoid(r[..., 0:9]) * 80 + 10
    sig = torch.nn.functional.softplus(r[..., 9:18]).clamp(1.0, 15.0)
    stats = (mu + sig * torch.randn(mu.shape, device=mu.device, generator=gen)).round().clamp(10, 90)
    genre = torch.multinomial(
        torch.softmax(r[..., 18:24], -1).view(-1, 6), 1, generator=gen).view(P, S, 2)
    arch = torch.multinomial(
        torch.softmax(r[..., 24:32], -1).view(-1, 8), 1, generator=gen).view(P, S, 2)
    ts_mu = torch.tanh(r[..., 32]) * 15.0
    ts_sig = torch.nn.functional.softplus(r[..., 33]).clamp(0.5, 8.0)
    trait_score = (ts_mu + ts_sig * torch.randn(ts_mu.shape, device=mu.device, generator=gen)).clamp(-15, 21)
    tc_mu = torch.sigmoid(r[..., 34]) * 10.0
    tc_sig = torch.nn.functional.softplus(r[..., 35]).clamp(0.3, 5.0)
    trait_chaos = (tc_mu + tc_sig * torch.randn(tc_mu.shape, device=mu.device, generator=gen)).clamp(0, 10)
    text_fit = text_fit_sampler((P, S, 2))

    mem_feat = torch.cat([
        (stats - 50) / 40,
        (genre.float().unsqueeze(-1) / 6.0),
        (arch.float().unsqueeze(-1) / 8.0),
        (trait_score / 10).unsqueeze(-1),
        (trait_chaos / 10).unsqueeze(-1),
    ], dim=-1)                                                     # [P,S,2,13]

    flat = lambda x: x.reshape(-1)
    fields = {
        "stats": stats.reshape(-1, 9),
        "genre": flat(genre).long(),
        "archetype": flat(arch).long(),
        "trait_score": flat(trait_score),
        "trait_chaos": flat(trait_chaos),
        "text_fit": flat(text_fit),
    }
    return fields, mem_feat


def make_candidate_source(flat_params, pop, seeds_per, env, state: DealerState,
                          difficulty: torch.Tensor, text_fit_sampler):
    """Returns the env hook: (env_mask [N]) -> fresh dict for [N,2] candidates.
    N = pop * seeds_per; ctx built from live env state; memory updated for
    masked envs only."""
    n = pop * seeds_per

    def source(env_mask):
        s = env.s
        exp_proxy = s["stats"][..., :3].mean(-1)                   # cheap quality proxy
        roster_alive = s["alive"][:, :12]
        mean_exp = (exp_proxy[:, :12] * roster_alive).sum(1) / roster_alive.sum(1).clamp(min=1)
        ctx = torch.stack([
            difficulty,
            s["week"] / 480.0,
            (torch.log1p(s["fans"].clamp(min=0)) / math.log1p(1e8)).clamp(0, 1.2),
            (torch.sign(s["money"]) * torch.log1p(s["money"].abs() / 1e3) / 8).clamp(-1.25, 1.25),
            roster_alive.sum(1) / 12.0,
            mean_exp / 100.0,
            (s["tokens"] / 8.0).clamp(0, 2),
            torch.ones_like(difficulty),
        ], dim=1)                                                   # [N,CTX]
        raw = dealer_forward(flat_params,
                             ctx.view(pop, seeds_per, CTX_DIM),
                             state.mem.view(pop, seeds_per, MEM_K, MEM_DIM),
                             state.used.view(pop, seeds_per, MEM_K))
        fields, mem_feat = sample_artists(raw, env.gen, text_fit_sampler)
        # memory token = [game state at deal time ; dealt artist]
        ctx_tok = ctx.view(n, 1, CTX_DIM).expand(-1, 2, -1)
        state.push(torch.cat([ctx_tok, mem_feat.view(n, 2, -1)], dim=-1), env_mask)
        # reshape to [N,2,...] as _new_pair expects
        out = {}
        for k, v in fields.items():
            out[k] = v.view(n, 2, *v.shape[1:])
        return out

    return source
