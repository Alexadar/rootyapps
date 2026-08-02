"""Offline precompute for the Producer torchsim (schedule.py pattern).

Everything content-random is precomputed into flat tensors once; the env
hot path only does randint-indexing and arithmetic. Rule-parity with the
TS generators (same distributions), not bit-parity (different RNG).
"""

import json
import math

import torch

import world_config as W

C = W.C


def build_artist_bank(n: int, device: str = "cpu", seed: int = 0) -> dict:
    """[n]-row artist bank matching src/lib/generateArtist.ts distributions.

    Returns dict of tensors: stats [n,9] (STATS order), genre [n], archetype [n],
    trait_score [n], trait_chaos [n], text_fit [n].
    """
    g = torch.Generator(device="cpu").manual_seed(seed)

    def rn(mean, sd):
        # randNorm: Box-Muller, round, clamp 10..90 (clamp applied twice in TS:
        # inside randNorm and after bias — harmless to apply after bias only for
        # base stats, but health/addiction/reputation get no bias)
        z = torch.randn(n, generator=g)
        return torch.round(mean + z * sd).clamp(10, 90)

    gen = C["artistGen"]
    stats = torch.zeros(n, W.N_STATS)
    for name, (mean, sd) in gen["statNorm"].items():
        stats[:, W.S[name]] = rn(mean, sd)

    genre = torch.randint(0, W.N_GENRES, (n,), generator=g)
    archetype = torch.randint(0, W.N_ARCHETYPES, (n,), generator=g)

    # genre bias then clamp (TS: clamp(base + bias, 10, 90))
    bias = torch.zeros(W.N_GENRES, W.N_STATS)
    for gi, gid in enumerate(W.GENRE_IDS):
        for stat, v in gen["genreBias"].get(gid, {}).items():
            bias[gi, W.S[stat]] = v
    stats = (stats + bias[genre]).clamp(10, 90)

    # traits: pickMany(TRAITS, randint(1,3)) — distinct uniform
    tr = torch.tensor([[t["score"], t["chaos"]] for t in C["traits"]], dtype=torch.float32)
    n_traits = torch.randint(1, 4, (n,), generator=g)
    # vectorized distinct sampling: argsort of random keys -> 3 distinct ids/row
    keys = torch.rand(n, W.N_TRAITS, generator=g)
    top3 = keys.argsort(dim=1)[:, :3]                     # [n,3] distinct trait ids
    picked = tr[top3]                                      # [n,3,2]
    mask = (torch.arange(3).unsqueeze(0) < n_traits.unsqueeze(1)).float().unsqueeze(-1)
    trait_sums = (picked * mask).sum(dim=1)                # [n,2]

    # text layer: measured empirical histogram (constant-ish for generated lyrics)
    with (W.DATA_DIR / "text_bonus_dist.json").open() as f:
        tdist = json.load(f)
    fit_hist = tdist["overall"]["fit"]                     # {value: count}
    vals = torch.tensor([float(k) for k in fit_hist.keys()])
    cnts = torch.tensor([float(v) for v in fit_hist.values()])
    cat = torch.multinomial(cnts / cnts.sum(), n, replacement=True, generator=g)
    text_fit = vals[cat]

    return {
        "stats": stats.to(device),
        "genre": genre.to(device),
        "archetype": archetype.to(device),
        "trait_score": trait_sums[:, 0].to(device),
        "trait_chaos": trait_sums[:, 1].to(device),
        "text_fit": text_fit.to(device),
    }


def build_static_tables(device: str = "cpu") -> dict:
    """All content tables as tensors, straight from game_constants.json."""
    t = {}

    tiers = C["tiers"]
    t["tier_listeners"] = torch.tensor([x["listeners"] for x in tiers], dtype=torch.float32, device=device)
    t["tier_fan_rate"] = torch.tensor([x["fanRate"] for x in tiers], device=device)
    t["tier_pay_rate"] = torch.tensor([x["payRate"] for x in tiers], device=device)
    t["tier_cost"] = torch.tensor([x["cost"] for x in tiers], dtype=torch.float32, device=device)
    t["tier_tokens"] = torch.tensor([x["tokenReward"] for x in tiers], dtype=torch.float32, device=device)
    sf = C["scoreFormula"]
    t["tier_thresholds"] = torch.tensor(sf["tierThresholds"], dtype=torch.float32, device=device)
    t["tier_exp"] = torch.tensor(sf["expGain"], dtype=torch.float32, device=device)
    t["tier_rep"] = torch.tensor(sf["repChange"], dtype=torch.float32, device=device)

    t["equip_cost"] = torch.tensor([e["cost"] for e in C["equipment"]], dtype=torch.float32, device=device)
    t["equip_bonus"] = torch.tensor([e["bonus"] for e in C["equipment"]], dtype=torch.float32, device=device)

    t["studio_cost"] = torch.tensor([u["cost"] for u in C["studioUpgrades"]], dtype=torch.float32, device=device)
    t["studio_quality"] = torch.tensor([u["qualityBonus"] for u in C["studioUpgrades"]], dtype=torch.float32, device=device)
    t["label_cost"] = torch.tensor([u["cost"] for u in C["labelSlots"]], dtype=torch.float32, device=device)
    t["label_slots"] = torch.tensor([u["slots"] for u in C["labelSlots"]], dtype=torch.float32, device=device)

    t["staff_salary"] = torch.tensor([C["staff"]["salaries"][r] for r in W.STAFF_ROLES], dtype=torch.float32, device=device)
    t["staff_bonus"] = torch.tensor([C["staff"]["bonuses"][r] for r in W.STAFF_ROLES], dtype=torch.float32, device=device)

    t["need_cost"] = torch.tensor([x["cost"] for x in C["needs"]], dtype=torch.float32, device=device)
    t["need_penalty"] = torch.tensor([x["happinessPenalty"] for x in C["needs"]], dtype=torch.float32, device=device)

    we = C["weekEvents"]
    t["week_event_fx"] = torch.tensor(
        [[e["money"], e["fans"], e["rep"], e["tokens"]] for e in we], dtype=torch.float32, device=device)

    # artist events: gates [17,4] (addLo, addHi, hapLo, hapHi), weights [17],
    # effects [17,9,2] (lo,hi per stat; addiction included via S order)
    ae = C["artistEvents"]
    t["aev_gates"] = torch.tensor(
        [[e["add"][0], e["add"][1], e["hap"][0], e["hap"][1]] for e in ae], dtype=torch.float32, device=device)
    t["aev_weight"] = torch.tensor([e["w"] for e in ae], dtype=torch.float32, device=device)
    fx = torch.zeros(W.N_ARTIST_EVENTS, W.N_STATS, 2, device=device)
    for i, e in enumerate(ae):
        for stat, (lo, hi) in e["fx"].items():
            fx[i, W.S[stat], 0] = lo
            fx[i, W.S[stat], 1] = hi
    t["aev_fx"] = fx

    # archetype weekly effects [8,9]
    arch = torch.zeros(W.N_ARCHETYPES, W.N_STATS, device=device)
    for ai, aid in enumerate(W.ARCHETYPE_IDS):
        for stat, v in C["archetypes"][aid].items():
            arch[ai, W.S[stat]] = v
    t["arch_fx"] = arch

    # genre trends: affinity matrix [6,10], drift [6]
    aff = torch.zeros(W.N_GENRES, W.N_TOPICS, device=device)
    for gi, gid in enumerate(W.GENRE_IDS):
        for topic in C["trends"]["genreAffinity"][gid]:
            aff[gi, W.TOPIC_IDS.index(topic)] = 1.0
    t["genre_affinity"] = aff
    t["genre_drift"] = torch.tensor(
        [C["trends"]["genreDrift"][g] for g in W.GENRE_IDS], dtype=torch.float32, device=device)

    return t
