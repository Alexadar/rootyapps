"""Observation builder: env state -> (self_feat [N,Fs], tok_feat [N,14,Fm], alive [N,14]).

Every feature is BOUNDED and SCALE-INVARIANT (the monstro desertion-bug rule):
money/fans span 6 orders of magnitude, so they enter as clamped signed-logs,
and every purchasable enters as a log-affordability ratio
clamp(log10(cost / max(money,1)), -2, 2) / 2 — "can I afford it" survives any
absolute scale. Normalizers live in world_config.OBS (train == deploy).
"""

import math

import torch

import world_config as W

C = W.C
O = W.OBS

# token feature channels
FM = 9 + W.N_GENRES + W.N_ARCHETYPES + 3 + 4 + 3 + 1 + 1   # 35
FS = 2 + 1 + 1 + 1 + 3 + 2 + 2 + W.N_STAFF + 2 + W.N_TOPICS + 2 * W.N_GENRES + 3 + 3  # 48
LOG_FANS_MAX = math.log1p(O["fans_log_max"])


def _money_log(m):
    return (torch.sign(m) * torch.log1p(m.abs() / 1e3) / O["money_log_div"]).clamp(-1.25, 1.25)


def _afford(cost, money):
    return (torch.log10(cost.clamp(min=1) / money.clamp(min=1)) / O["afford_clamp"]).clamp(-1, 1)


def build_obs(env):
    s = env.s
    n, dev = env.n, env.device

    # ---- token features [N,14,FM] ----
    stats = (s["stats"] - O["stat_center"]) / O["stat_div"]                        # [N,14,9]
    genre_oh = torch.nn.functional.one_hot(s["genre"], W.N_GENRES).float()
    arch_oh = torch.nn.functional.one_hot(s["archetype"], W.N_ARCHETYPES).float()
    traits = torch.stack([s["trait_score"] / 10.0, s["trait_chaos"] / 10.0,
                          s["text_fit"] / 10.0], dim=-1)
    status = torch.stack([s["in_rehab"].float(), (s["rehab_weeks"] / 4.0).clamp(0, 1.5),
                          (s["tour_cd"] / 4.0).clamp(0, 1.5), (s["trash_pop"] / 30.0).clamp(0, 1)], dim=-1)
    need_cost = env.T["need_cost"][s["need_id"].long()]
    needs = torch.stack([
        s["need_active"].float(),
        torch.where(s["need_active"], _afford(need_cost, s["money"].unsqueeze(1)), torch.zeros_like(need_cost)),
        torch.where(s["need_active"], env.T["need_penalty"][s["need_id"].long()] / 20.0,
                    torch.zeros_like(need_cost)),
    ], dim=-1)
    is_cand = torch.zeros(n, W.N_TOKENS_SLOTS, 1, device=dev)
    is_cand[:, W.ROSTER_SLOTS:, 0] = 1.0
    gmod = (s["genre_mod"].gather(1, s["genre"]) / 20.0).unsqueeze(-1)             # own-genre trend
    tok = torch.cat([stats, genre_oh, arch_oh, traits, status, needs, is_cand, gmod], dim=-1)

    # token presence mask: roster alive + candidates always present
    present = s["alive"].clone()
    present[:, W.ROSTER_SLOTS:] = True

    # ---- self features [N,FS] ----
    money = s["money"]
    fans = s["fans"]
    studio_cost = env.T["studio_cost"][s["studio"].long().clamp(max=5)] * env.theta["upgrade_cost_mult"]
    label_cost = env.T["label_cost"][(s["label_tier"] + 1).long().clamp(max=5)] * env.theta["upgrade_cost_mult"]
    eq_cost = env.T["equip_cost"].unsqueeze(0) * env.theta["equip_cost_mult"].unsqueeze(1)
    cheapest_unowned = torch.where(s["equip"], torch.full_like(eq_cost, 1e9), eq_cost).min(dim=1).values
    roster = s["alive"][:, :W.ROSTER_SLOTS].sum(1)
    cap = env.T["label_slots"][s["label_tier"].long()]
    week_phase = 2 * math.pi * (s["week"] % 48) / 48.0

    self_feat = torch.cat([
        _money_log(money).unsqueeze(1),
        (money / O["money_lin_div"]).clamp(-2, 2).unsqueeze(1),
        (torch.log1p(fans.clamp(min=0)) / LOG_FANS_MAX).clamp(0, 1.2).unsqueeze(1),
        (s["tokens"] / O["tokens_div"]).clamp(0, 2).unsqueeze(1),
        (s["rep"] / 100.0).unsqueeze(1),
        (s["week"] / O["week_div"]).unsqueeze(1),
        torch.sin(week_phase).unsqueeze(1), torch.cos(week_phase).unsqueeze(1),
        (s["studio"] / 6.0).unsqueeze(1), (s["label_tier"] / 5.0).unsqueeze(1),
        (roster / 12.0).unsqueeze(1), ((cap - roster) / 12.0).unsqueeze(1),
        s["staff"].float(),
        ((s["equip"].float() * env.T["equip_bonus"]).sum(1) / 60.0).unsqueeze(1),
        s["equip"].float().mean(1).unsqueeze(1),
        s["topic_pop"] / 100.0,
        s["genre_pop"] / 100.0,
        s["genre_mod"] / 20.0,
        _afford(studio_cost, money).unsqueeze(1),
        _afford(label_cost, money).unsqueeze(1),
        _afford(cheapest_unowned, money).unsqueeze(1),
        (s["rejects"] / 6.0).clamp(0, 2).unsqueeze(1),
        (s["week_actions"] / W.MAX_ACTIONS_PER_WEEK).unsqueeze(1),
        s["week_advanced"].float().unsqueeze(1),
    ], dim=1)

    # theta-aware agents (round 2+): normalized game-balance knobs in the obs,
    # so ONE policy plays the whole difficulty ladder (and the in-game advisor
    # can be difficulty-conditioned)
    if getattr(env, "obs_theta", False):
        th = torch.stack([(env.theta[k] - W.GEN_KNOBS[k][1])
                          / (W.GEN_KNOBS[k][2] - W.GEN_KNOBS[k][1])
                          for k in W.OBS_KNOB_NAMES], dim=1)
        self_feat = torch.cat([self_feat, th], dim=1)

    return self_feat, tok, present.float()
