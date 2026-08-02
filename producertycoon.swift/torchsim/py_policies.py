"""Vectorized mirrors of the TS gate policies (scripts/policies.ts) for the
statistical parity test: same decision rules, expressed as batched action
selection over the env state. Each returns an action id [N] given env.

Only the three golden policies are mirrored: random-legal,
sign-release-spam, greedy-heuristic.
"""

import torch

import world_config as W

SF = W.C["scoreFormula"]


def expected_score(env) -> torch.Tensor:
    """Deterministic per-artist expected release contribution [N,14]
    (mirrors scripts/headless.ts expectedScore: stats + traitScore)."""
    st = env.s["stats"]
    w = SF["weights"]
    return (st[..., W.S["talent"]] * w["talent"] + st[..., W.S["charisma"]] * w["charisma"]
            + st[..., W.S["popularity"]] * w["popularity"] + st[..., W.S["discipline"]] * w["discipline"]
            + st[..., W.S["reputation"]] * w["reputation"]
            + st[..., W.S["selfConfidence"]] * w["selfConfidence"]
            + st[..., W.S["addiction"]] * w["addiction"]) + env.s["trait_score"]


def _pick_slot(mask_slice: torch.Tensor, scores: torch.Tensor | None = None) -> torch.Tensor:
    """Best legal roster slot per env: argmax(scores) among legal, else 0."""
    if scores is None:
        scores = torch.zeros_like(mask_slice, dtype=torch.float32)
    sc = torch.where(mask_slice, scores, torch.full_like(scores, -1e9))
    return sc.argmax(dim=1)


def random_legal(env, mask: torch.Tensor, rng: torch.Generator,
                 ending: torch.Tensor | None = None) -> torch.Tensor:
    """Mirror of the TS thunk-list sampler + driver: each iteration rolls 25%
    "stop acting"; once stopped (sticky `ending` flag, managed by the runner),
    the env goes straight to endWeek — via the driver's forced-release path
    (release first alive artist; sign first if roster empty) when endWeek is
    blocked. While acting: pick a THUNK uniformly; an illegal thunk wastes the
    iteration, so P(action)=legal_frac per iteration."""
    n, dev = env.n, mask.device
    s = env.s

    if ending is not None and ending.any():
        act_end = torch.full((n,), W.A_END_WEEK, dtype=torch.long, device=dev)
        can_end = mask[:, W.A_END_WEEK]
        # forced path: release FIRST alive artist (TS driver: artists[0])
        rel = mask[:, W.A_RELEASE:W.A_RELEASE + 12]
        first_rel = W.A_RELEASE + rel.float().argmax(1)
        act_end = torch.where(~can_end & rel.any(1), first_rel, act_end)
        sign_ok = mask[:, W.A_SIGN0]
        act_end = torch.where(~can_end & ~rel.any(1) & sign_ok,
                              torch.full_like(act_end, W.A_SIGN0), act_end)
        # fall through to random pick for non-ending envs below
    else:
        act_end = None

    # thunk multiplicities per action id, mirroring policies.ts random-legal
    thunk = torch.zeros_like(mask, dtype=torch.float32)
    alive = s["alive"][:, :12]
    roster = alive.sum(1)
    cap = env.T["label_slots"][s["label_tier"].long()]
    has_room = roster < cap
    thunk[:, W.A_SIGN0] = has_room.float()
    thunk[:, W.A_SIGN1] = has_room.float()
    thunk[:, W.A_REJECT] = 1.0
    tokens_ok = (s["tokens"] >= 1).unsqueeze(1).float()
    thunk[:, W.A_RELEASE:W.A_RELEASE + 12] = alive.float() * tokens_ok
    pop = s["stats"][:, :12, W.S["popularity"]]
    tour_cost = 15000 + torch.round(pop * 500)
    thunk[:, W.A_TOUR:W.A_TOUR + 12] = alive.float() * (s["money"].unsqueeze(1) >= tour_cost).float()
    thunk[:, W.A_REHAB:W.A_REHAB + 12] = (alive & ~s["in_rehab"][:, :12]
                                          & (s["money"] >= 20000).unsqueeze(1)).float()
    thunk[:, W.A_FIRE:W.A_FIRE + 12] = alive.float()
    need_cost = env.T["need_cost"][s["need_id"][:, :12].long()]
    thunk[:, W.A_FULFILL:W.A_FULFILL + 12] = (alive & s["need_active"][:, :12]
                                              & (s["money"].unsqueeze(1) >= need_cost)).float()
    thunk[:, W.A_HIRE:W.A_HIRE + 6] = (~s["staff"]).float()
    thunk[:, W.A_FIRE_STAFF:W.A_FIRE_STAFF + 6] = s["staff"].float()
    eq_cost = env.T["equip_cost"]
    thunk[:, W.A_BUY_EQUIP:W.A_BUY_EQUIP + W.N_EQUIP] = \
        (~s["equip"] & (s["money"].unsqueeze(1) >= eq_cost)).float()
    thunk[:, W.A_UPGRADE_STUDIO] = (s["studio"] < 6).float()   # thunk exists w/o money check
    thunk[:, W.A_UPGRADE_LABEL] = (s["label_tier"] < 5).float()

    legal_thunk = thunk * mask.float()
    legal = legal_thunk.sum(1)
    probs = legal_thunk / legal.clamp(min=1e-9).unsqueeze(1)
    probs = torch.where(legal.unsqueeze(1) > 1e-8, probs, mask.float())
    act = torch.multinomial(probs, 1, generator=rng).squeeze(1)
    if act_end is not None:
        act = torch.where(ending, act_end, act)
    return act


def sign_release_spam(env, mask: torch.Tensor, rng: torch.Generator) -> torch.Tensor:
    """Sign first candidate while slots free; release every artist while
    tokens last; endWeek."""
    n, dev = env.n, mask.device
    act = torch.full((n,), W.A_END_WEEK, dtype=torch.long, device=dev)
    rel = mask[:, W.A_RELEASE:W.A_RELEASE + 12]
    has_rel = rel.any(1)
    act = torch.where(has_rel, W.A_RELEASE + _pick_slot(rel), act)
    can_sign = mask[:, W.A_SIGN0]
    act = torch.where(can_sign, torch.full_like(act, W.A_SIGN0), act)
    # fallback if endWeek illegal and nothing else picked
    illegal = ~mask.gather(1, act.unsqueeze(1)).squeeze(1)
    any_legal = mask.float().argmax(dim=1)
    return torch.where(illegal, any_legal, act)


def greedy_heuristic(env, mask: torch.Tensor, rng: torch.Generator,
                     released_this_week: torch.Tensor | None = None) -> torch.Tensor:
    """Priority mirror of policies.ts greedyWeek: sign-better / needs / rehab /
    EV-tours / staff / ROI-equipment / upgrades / best-release. One action per
    step; priorities encode the same weekly order."""
    n, dev = env.n, mask.device
    s = env.s
    st = s["stats"]
    exp = expected_score(env)                                        # [N,14]
    money = s["money"]

    act = torch.full((n,), W.A_END_WEEK, dtype=torch.long, device=dev)
    chosen = torch.zeros(n, dtype=torch.bool, device=dev)

    def choose(cond, a):
        nonlocal act, chosen
        legal = mask.gather(1, a.unsqueeze(1)).squeeze(1)
        take = cond & legal & ~chosen
        act = torch.where(take, a, act)
        chosen |= take

    # --- release best artist with exp>=30 while tokens>=1 (highest priority
    # AFTER management, but in one-action-per-step form releases happen when
    # nothing above triggers; ordering below mirrors greedyWeek top-down) ---

    # 1. sign: best candidate if roster empty/below half cap or better than median
    # (TS median = sorted[floor(len/2)] — the UPPER middle for even counts);
    # TS sign loop runs only while actionsLeft > 4
    e0, e1 = exp[:, 12], exp[:, 13]
    best_cand = torch.where(e0 >= e1, torch.full_like(act, W.A_SIGN0), torch.full_like(act, W.A_SIGN1))
    best_score = torch.maximum(e0, e1)
    alive = s["alive"][:, :12]
    roster = alive.sum(1).long()
    cap = env.T["label_slots"][s["label_tier"].long()]
    rexp = torch.where(alive, exp[:, :12], torch.full_like(exp[:, :12], torch.inf))
    sorted_exp, _ = rexp.sort(dim=1)                      # alive values first? inf sorts last
    med_idx = (roster // 2).clamp(max=11)
    med = sorted_exp.gather(1, med_idx.unsqueeze(1)).squeeze(1)
    med = torch.where(roster > 0, med, torch.full_like(med, -1e9))
    budget_ok = s["week_actions"] < (W.MAX_ACTIONS_PER_WEEK - 4)
    want_sign = budget_ok & ((roster == 0) | (roster < cap / 2) | (best_score > med))
    choose(want_sign, best_cand)
    # reject if not signing (up to 2/week) and roster has room
    want_reject = budget_ok & ~want_sign & (roster < cap) & (s["week_rejects"] < 2)
    choose(want_reject, torch.full_like(act, W.A_REJECT))

    # 2. cheap needs (cost<10k, money>30k)
    need_cost = env.T["need_cost"][s["need_id"][:, :12].long()]
    nm = s["need_active"][:, :12] & (need_cost < 10000) & (money > 30000).unsqueeze(1)
    choose(nm.any(1), W.A_FULFILL + _pick_slot(nm))

    # 3. rehab: addiction>65, money>60k
    hm = alive & (st[:, :12, W.S["addiction"]] > 65) & ~s["in_rehab"][:, :12] & (money > 60000).unsqueeze(1)
    choose(hm.any(1), W.A_REHAB + _pick_slot(hm))

    # 4. tours: base>=37, health>=45, money >= cost+10k
    tb = (st[:, :12, W.S["popularity"]] * 0.3 + st[:, :12, W.S["charisma"]] * 0.15
          + st[:, :12, W.S["reputation"]] * 0.1)
    tour_cost = 15000 + torch.round(st[:, :12, W.S["popularity"]] * 500)
    tm = alive & (tb >= 37) & (st[:, :12, W.S["health"]] >= 45) & ~s["in_rehab"][:, :12] \
        & (s["tour_cd"][:, :12] <= 0) & (money.unsqueeze(1) >= tour_cost + 10000)
    tour_budget = s["week_actions"] < (W.MAX_ACTIONS_PER_WEEK - 2)   # TS: actionsLeft > 2
    choose(tour_budget & tm.any(1), W.A_TOUR + _pick_slot(tm, tb))

    # TS weekly order: purchases happen BEFORE releases — same-week release
    # income must not fund purchases (upper-tail money parity)
    pre_release = torch.ones(n, dtype=torch.bool, device=dev) \
        if released_this_week is None else ~released_this_week

    # 5. staff: soundEngineer+pr at week>=4 & money>50k; mgr/acc/lawyer >150k; security >200k
    week = s["week"]
    for role, cond in (("soundEngineer", (week >= 4) & (money > 50000)),
                       ("pr", (week >= 4) & (money > 50000)),
                       ("manager", money > 150000), ("accountant", money > 150000),
                       ("lawyer", money > 150000), ("security", money > 200000)):
        r = W.STAFF_ROLES.index(role)
        choose(pre_release & cond & ~s["staff"][:, r], torch.full_like(act, W.A_HIRE + r))
    # fire staff if broke
    broke = money < 0
    for r in range(W.N_STAFF):
        choose(broke & s["staff"][:, r], torch.full_like(act, W.A_FIRE_STAFF + r))

    # 6. equipment by ROI when money > 3x cost
    eq_cost = env.T["equip_cost"]
    roi = env.T["equip_bonus"] / eq_cost
    can_buy = ~s["equip"] & (money.unsqueeze(1) > eq_cost * 3) & pre_release.unsqueeze(1)
    roi_m = torch.where(can_buy, roi.unsqueeze(0).expand(n, -1), torch.full((n, W.N_EQUIP), -1e9, device=dev))
    choose(can_buy.any(1), W.A_BUY_EQUIP + roi_m.argmax(1))

    # 7. upgrades with 2x margin (label only when roster at cap)
    label_cost = env.T["label_cost"][(s["label_tier"] + 1).long().clamp(max=5)]
    choose(pre_release & (roster >= cap) & (s["label_tier"] < 5) & (money > label_cost * 2),
           torch.full_like(act, W.A_UPGRADE_LABEL))
    studio_cost = env.T["studio_cost"][s["studio"].long().clamp(max=5)]
    choose(pre_release & (s["studio"] < 6) & (money > studio_cost * 2),
           torch.full_like(act, W.A_UPGRADE_STUDIO))

    # 8. release best exp>=30 while tokens>=1; if endWeek blocked, release anything
    rel_ok = mask[:, W.A_RELEASE:W.A_RELEASE + 12]
    good = rel_ok & (exp[:, :12] >= 30)
    choose(good.any(1), W.A_RELEASE + _pick_slot(good, exp[:, :12]))
    must = s["week_advanced"] & rel_ok.any(1)
    choose(must, W.A_RELEASE + _pick_slot(rel_ok, exp[:, :12]))

    # fallback legality
    legal = mask.gather(1, act.unsqueeze(1)).squeeze(1)
    return torch.where(legal, act, mask.float().argmax(dim=1))


POLICIES = {
    "random-legal": random_legal,
    "sign-release-spam": sign_release_spam,
    "greedy-heuristic": greedy_heuristic,
}
