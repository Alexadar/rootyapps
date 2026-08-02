"""Batched torch environment for Producer Tycoon.

[N] game instances, decision-level stepping: one env step = one atomic
action (95-way masked categorical, world_config action ids); A_END_WEEK
runs the weekly world transition. Rule-parity with the patched TS game
(useGameStore.ts), validated statistically against golden vectors.

Design notes:
- Artists live in 14 token slots: 0..11 roster (alive mask), 12..13 the
  candidate pair. All artist state is [N,14,...] tensors.
- Simplification vs TS (documented): max ONE active need per artist
  (TS allows a list; P(overlap) ~ 0.8%/week — statistical parity holds).
- Producer specialization fixed to 'talented' (what the gate/golden used).
- pregnant/married never occur in TS runs (nothing sets them) — dropped.
- theta (learnable game hyperparams) is a dict of [N] tensors applied on
  top of constants — one batch can run many game balances (Phase 4).
- No python loop over N anywhere; loops over the 12 roster slots or small
  tables are fine (they are O(12) tensor ops, not O(N)).
"""

import torch

import world_config as W
import tables

C = W.C
SF = C["scoreFormula"]
TOUR = C["tour"]
WK = C["weekly"]
WL = C["winLose"]


def _randint(lo, hi, shape, device, gen=None):
    """TS randInt(lo, hi): inclusive both ends. lo/hi may be [.]-broadcast tensors."""
    u = torch.rand(shape, device=device, generator=gen)
    lo = torch.as_tensor(lo, dtype=torch.float32, device=device)
    hi = torch.as_tensor(hi, dtype=torch.float32, device=device)
    return torch.floor(u * (hi - lo + 1)) + lo


def _uniform(lo, hi, shape, device, gen=None):
    u = torch.rand(shape, device=device, generator=gen)
    lo = torch.as_tensor(lo, dtype=torch.float32, device=device)
    hi = torch.as_tensor(hi, dtype=torch.float32, device=device)
    return lo + u * (hi - lo)


class ProducerEnv:
    def __init__(self, n_envs: int, device: str = "cuda", seed: int = 0,
                 bank_size: int = 1_000_000, theta: dict | None = None,
                 max_weeks: int = W.MAX_WEEKS, obs_theta: bool = False,
                 victory_weeks: int | None = None):
        self.obs_theta = obs_theta
        # compressed survival-win horizon for calibration runs (co-evolution);
        # None = the game's true 10 years. Validation must use the default.
        self.victory_weeks = victory_weeks if victory_weeks is not None \
            else C["winLose"]["yearsForVictory"] * 48
        # optional learned content source: (env_mask [N]) -> dict of [N,2,...]
        # candidate fields (see dealer.make_candidate_source). None = artist bank.
        self.candidate_source = None
        self.n = n_envs
        self.device = device
        self.gen = torch.Generator(device=device).manual_seed(seed)
        self.T = tables.build_static_tables(device)
        self.bank = tables.build_artist_bank(bank_size, device, seed=seed + 7777)
        self.bank_size = bank_size
        self.max_weeks = max_weeks

        # theta: [N] tensor per knob; defaults from GEN_KNOBS
        self.theta = {}
        for k, (default, lo, hi) in W.GEN_KNOBS.items():
            v = theta.get(k) if theta else None
            if v is None:
                v = torch.full((n_envs,), float(default), device=device)
            self.theta[k] = v.clamp(lo, hi)
        self.refresh_pay_mult()

        self.reset()

    def refresh_pay_mult(self):
        """Rebuild the cached per-tier pay multiplier [N,5] (Провал stays 1.0).
        MUST be called after mutating self.theta in place (league swaps)."""
        self.pay_mult = torch.stack([
            torch.ones(self.n, device=self.device),
            self.theta["pay_mult_meme"], self.theta["pay_mult_normal"],
            self.theta["pay_mult_hit"], self.theta["pay_mult_cult"],
        ], dim=1)

    # ---------- helpers ----------
    def _draw_artists(self, shape) -> dict:
        idx = torch.randint(0, self.bank_size, shape, device=self.device, generator=self.gen)
        return {k: v[idx] for k, v in self.bank.items()}

    def _new_pair(self, env_mask: torch.Tensor):
        """Regenerate candidate slots 12,13 for envs in [N] bool mask.
        Fixed-shape draw + masked merge — NO host sync (no .sum()/.any())."""
        s = self.s
        fresh = (self.candidate_source(env_mask) if self.candidate_source is not None
                 else self._draw_artists((self.n, 2)))            # [N,2,...]
        m = env_mask.view(self.n, 1)
        sl = slice(W.ROSTER_SLOTS, W.N_TOKENS_SLOTS)
        for k in ("stats", "genre", "archetype", "trait_score", "trait_chaos", "text_fit"):
            mm = m
            while mm.dim() < fresh[k].dim():
                mm = mm.unsqueeze(-1)
            s[k][:, sl] = torch.where(mm.expand_as(fresh[k]), fresh[k], s[k][:, sl])
        s["in_rehab"][:, sl] &= ~m
        s["need_active"][:, sl] &= ~m
        for k in ("rehab_weeks", "tour_cd", "trash_pop", "need_id", "need_weeks"):
            s[k][:, sl] = torch.where(m, torch.zeros_like(s[k][:, sl]), s[k][:, sl])

    # ---------- reset ----------
    def reset(self, mask: torch.Tensor | None = None):
        """Full reset (mask=None) or per-env reset of the envs in [N] bool mask
        (auto-reset for continuous PPO rollouts). Fresh init values are built
        for all N (cheap) and where-merged into the live state."""
        if mask is not None:
            old = self.s
            old_lrt = self.last_release_tier
            # C1: pass the true reset mask down so a learned candidate_source
            # only sees (and remembers) deals for envs actually resetting —
            # an all-ones _new_pair here would flush every env's dealer memory
            # with phantom candidates on every per-step auto-reset call
            self._build_initial_state(pair_mask=mask)   # also rebuilds self.last_release_tier
            fresh = self.s
            merged = {}
            for k in old:
                m = mask
                while m.dim() < old[k].dim():
                    m = m.unsqueeze(-1)
                merged[k] = torch.where(m.expand_as(old[k]), fresh[k], old[k])
            self.s = merged
            self.last_release_tier = torch.where(mask, self.last_release_tier, old_lrt)
            return self.s
        self._build_initial_state()
        return self.s

    def _build_initial_state(self, pair_mask: torch.Tensor | None = None):
        n, dev = self.n, self.device
        Z = lambda *sh: torch.zeros(n, *sh, device=dev)
        self.s = s = {}
        s["money"] = self.theta["start_money_mult"] * float(C["start"]["money"])
        s["fans"] = Z()
        s["tokens"] = torch.full((n,), float(C["start"]["tokens"]), device=dev)
        s["rep"] = torch.full((n,), float(C["start"]["reputation"]), device=dev)
        s["week"] = Z()                    # completed weeks
        s["studio"] = torch.ones(n, device=dev)
        s["label_tier"] = Z()
        s["rejects"] = Z()
        s["week_actions"] = Z()
        s["week_rejects"] = Z()
        s["week_advanced"] = torch.zeros(n, dtype=torch.bool, device=dev)  # false: endWeek OK
        s["prod_level"] = torch.ones(n, device=dev)
        s["prod_xp"] = Z()
        s["prod_xp_next"] = torch.full((n,), float(SF["expToNextBase"]), device=dev)
        s["equip"] = torch.zeros(n, W.N_EQUIP, dtype=torch.bool, device=dev)
        s["staff"] = torch.zeros(n, W.N_STAFF, dtype=torch.bool, device=dev)
        s["releases"] = Z()
        # trends
        s["topic_pop"] = _randint(*C["trends"]["initTopicPop"], (n, W.N_TOPICS), dev, self.gen)
        # direction: 0 rising / 1 peaking / 2 falling; init: 40% rising, 18% falling, rest peaking
        u = torch.rand(n, W.N_TOPICS, device=dev, generator=self.gen)
        s["topic_dir"] = torch.where(u < 0.4, 0.0, torch.where(u < 0.58, 2.0, 1.0))
        s["genre_pop"] = torch.full((n, W.N_GENRES), 50.0, device=dev)
        s["genre_mod"] = Z(W.N_GENRES)
        # artists
        sh = (n, W.N_TOKENS_SLOTS)
        s["stats"] = Z(W.N_TOKENS_SLOTS, W.N_STATS)
        s["genre"] = torch.zeros(sh, dtype=torch.long, device=dev)
        s["archetype"] = torch.zeros(sh, dtype=torch.long, device=dev)
        s["trait_score"] = Z(W.N_TOKENS_SLOTS)
        s["trait_chaos"] = Z(W.N_TOKENS_SLOTS)
        s["text_fit"] = Z(W.N_TOKENS_SLOTS)
        s["alive"] = torch.zeros(sh, dtype=torch.bool, device=dev)
        s["in_rehab"] = torch.zeros(sh, dtype=torch.bool, device=dev)
        s["rehab_weeks"] = Z(W.N_TOKENS_SLOTS)
        s["tour_cd"] = Z(W.N_TOKENS_SLOTS)
        s["trash_pop"] = Z(W.N_TOKENS_SLOTS)
        s["need_active"] = torch.zeros(sh, dtype=torch.bool, device=dev)
        s["need_id"] = Z(W.N_TOKENS_SLOTS)
        s["need_weeks"] = Z(W.N_TOKENS_SLOTS)
        s["done"] = torch.zeros(n, dtype=torch.bool, device=dev)
        s["outcome"] = Z()  # 0 running, 1 win-fans, 2 win-years, 3 bankrupt, 4 rep, 5 rejects, 6 timeout
        # initial genre trends: one update step from 50-baseline
        self._update_trends()
        self._new_pair(pair_mask if pair_mask is not None
                       else torch.ones(n, dtype=torch.bool, device=dev))
        # per-release info panel (for analysis)
        self.last_release_tier = torch.full((n,), -1.0, device=dev)
        return s

    # ---------- action masking ----------
    def legal_mask(self) -> torch.Tensor:
        s = self.s
        n, dev = self.n, self.device
        mask = torch.zeros(n, W.N_ACTIONS, dtype=torch.bool, device=dev)
        alive = s["alive"][:, :W.ROSTER_SLOTS]                    # [N,12]
        roster = alive.sum(1)
        slots = self.T["label_slots"][s["label_tier"].long()]
        money = s["money"]

        can_end = ~s["week_advanced"]
        mask[:, W.A_END_WEEK] = can_end
        can_sign = roster < slots
        mask[:, W.A_SIGN0] = can_sign
        mask[:, W.A_SIGN1] = can_sign
        mask[:, W.A_REJECT] = s["week_rejects"] < W.MAX_REJECTS_PER_WEEK

        tokens_ok = (s["tokens"] >= 1).unsqueeze(1)
        mask[:, W.A_RELEASE:W.A_RELEASE + 12] = alive & tokens_ok

        pop = s["stats"][:, :W.ROSTER_SLOTS, W.S["popularity"]]
        tour_cost = (TOUR["costBase"] + torch.round(pop * TOUR["costPerPop"])) \
            * self.theta["tour_cost_mult"].unsqueeze(1)
        mask[:, W.A_TOUR:W.A_TOUR + 12] = alive & (s["tour_cd"][:, :12] <= 0) \
            & (money.unsqueeze(1) >= tour_cost)

        mask[:, W.A_REHAB:W.A_REHAB + 12] = alive & ~s["in_rehab"][:, :12] \
            & (money >= C["rehab"]["cost"]).unsqueeze(1)
        mask[:, W.A_FIRE:W.A_FIRE + 12] = alive

        need_cost = self.T["need_cost"][s["need_id"][:, :12].long()]
        mask[:, W.A_FULFILL:W.A_FULFILL + 12] = alive & s["need_active"][:, :12] \
            & (money.unsqueeze(1) >= need_cost)

        mask[:, W.A_HIRE:W.A_HIRE + 6] = ~s["staff"]
        mask[:, W.A_FIRE_STAFF:W.A_FIRE_STAFF + 6] = s["staff"]

        equip_cost = self.T["equip_cost"].unsqueeze(0) * self.theta["equip_cost_mult"].unsqueeze(1)
        mask[:, W.A_BUY_EQUIP:W.A_BUY_EQUIP + W.N_EQUIP] = ~s["equip"] \
            & (money.unsqueeze(1) >= equip_cost)

        studio_i = s["studio"].long().clamp(max=5)
        studio_cost = self.T["studio_cost"][studio_i] * self.theta["upgrade_cost_mult"]
        mask[:, W.A_UPGRADE_STUDIO] = (s["studio"] < 6) & (money >= studio_cost)
        tier_i = (s["label_tier"] + 1).long().clamp(max=5)
        label_cost = self.T["label_cost"][tier_i] * self.theta["upgrade_cost_mult"]
        mask[:, W.A_UPGRADE_LABEL] = (s["label_tier"] < 5) & (money >= label_cost)

        # 16-action weekly cap: only endWeek — unless endWeek illegal, then
        # keep release+sign as the escape hatch (mirrors headless driver)
        capped = s["week_actions"] >= W.MAX_ACTIONS_PER_WEEK
        keep = torch.zeros_like(mask)
        keep[:, W.A_END_WEEK] = True
        esc = capped & ~can_end
        keep[:, W.A_SIGN0] = keep[:, W.A_SIGN1] = esc
        keep[:, W.A_RELEASE:W.A_RELEASE + 12] |= esc.unsqueeze(1)
        mask = torch.where(capped.unsqueeze(1), mask & keep, mask)

        mask[s["done"]] = False
        mask[s["done"], W.A_END_WEEK] = True   # no-op action for finished envs
        return mask

    # ---------- step ----------
    def step(self, action: torch.Tensor):
        """action [N] long. Returns (state, done [N] bool, info dict)."""
        s = self.s
        n, dev = self.n, self.device
        act = action.long()
        live = ~s["done"]

        is_end = (act == W.A_END_WEEK) & live
        non_end = live & ~is_end
        s["week_actions"] = s["week_actions"] + non_end.float()

        # --- slot-targeted actions: build (env, slot) index masks [N,12] ---
        def slot_mask(base):
            m = torch.zeros(n, W.N_TOKENS_SLOTS, dtype=torch.bool, device=dev)
            in_range = (act >= base) & (act < base + 12) & live
            sl = (act - base).clamp(0, 11)
            m[torch.arange(n, device=dev), sl] = in_range
            return m

        # SIGN: copy candidate into first free roster slot.
        # Sign masks are mutually exclusive with everything below (one action
        # per env per step), and executing with an all-False mask is a no-op —
        # so NO .any() guards anywhere in this method (each one is a full
        # GPU->CPU sync; they were the throughput killer).
        for ci, a_id in ((0, W.A_SIGN0), (1, W.A_SIGN1)):
            em = (act == a_id) & live
            free = ~s["alive"][:, :W.ROSTER_SLOTS]                       # [N,12]
            first_free = torch.argmax(free.float(), dim=1)               # [N]
            em2 = em & free.any(dim=1)
            src = W.ROSTER_SLOTS + ci
            rows = torch.arange(n, device=dev)[em2]
            dst = first_free[em2]
            for k in ("stats", "genre", "archetype", "trait_score", "trait_chaos",
                      "text_fit", "in_rehab", "rehab_weeks", "tour_cd", "trash_pop",
                      "need_active", "need_id", "need_weeks"):
                s[k][rows, dst] = s[k][rows, src]
            s["alive"][rows, dst] = True
            s["rejects"] = torch.where(em2, torch.zeros_like(s["rejects"]), s["rejects"])
            self._new_pair(em2)

        # REJECT BOTH
        em = (act == W.A_REJECT) & live
        s["rejects"] = s["rejects"] + em.float() * 2
        s["week_rejects"] = s["week_rejects"] + em.float()
        self._new_pair(em)

        # RELEASE
        self._release(slot_mask(W.A_RELEASE))

        # TOUR
        self._tour(slot_mask(W.A_TOUR))

        # REHAB
        hm = slot_mask(W.A_REHAB)
        s["money"] = s["money"] - hm.any(1).float() * C["rehab"]["cost"]
        s["in_rehab"] |= hm
        s["rehab_weeks"] = torch.where(hm, torch.full_like(s["rehab_weeks"], C["rehab"]["weeks"]), s["rehab_weeks"])
        add = s["stats"][..., W.S["addiction"]]
        s["stats"][..., W.S["addiction"]] = torch.where(
            hm, (add - C["rehab"]["addictionDrop"]).clamp(10, 90), add)

        # FIRE artist
        fm = slot_mask(W.A_FIRE)
        s["alive"] &= ~fm

        # FULFILL NEED
        nm = slot_mask(W.A_FULFILL)
        cost = torch.where(nm, self.T["need_cost"][s["need_id"].long()], torch.zeros_like(s["need_weeks"]))
        s["money"] = s["money"] - cost.sum(1)
        hap = s["stats"][..., W.S["happiness"]]
        s["stats"][..., W.S["happiness"]] = torch.where(
            nm, (hap + C["needFulfillHappiness"]).clamp(10, 90), hap)
        s["need_active"] &= ~nm

        # HIRE / FIRE STAFF
        for r in range(W.N_STAFF):
            s["staff"][:, r] |= (act == W.A_HIRE + r) & live
            s["staff"][:, r] &= ~((act == W.A_FIRE_STAFF + r) & live)

        # BUY EQUIPMENT
        em = (act >= W.A_BUY_EQUIP) & (act < W.A_BUY_EQUIP + W.N_EQUIP) & live
        eq = (act - W.A_BUY_EQUIP).clamp(0, W.N_EQUIP - 1)
        rows = torch.arange(n, device=dev)[em]
        s["equip"][rows, eq[em]] = True
        s["money"] = s["money"] - em.float() * self.T["equip_cost"][eq] * self.theta["equip_cost_mult"]

        # UPGRADES
        em = (act == W.A_UPGRADE_STUDIO) & live
        cost = self.T["studio_cost"][s["studio"].long().clamp(max=5)] * self.theta["upgrade_cost_mult"]
        s["money"] = s["money"] - em.float() * cost
        s["studio"] = s["studio"] + em.float()

        em = (act == W.A_UPGRADE_LABEL) & live
        cost = self.T["label_cost"][(s["label_tier"] + 1).long().clamp(max=5)] * self.theta["upgrade_cost_mult"]
        s["money"] = s["money"] - em.float() * cost
        s["label_tier"] = s["label_tier"] + em.float()

        # END WEEK
        self._end_week(is_end)

        return s, s["done"], {}

    # ---------- release (vectorized over [N,14] mask) ----------
    def _release(self, rm: torch.Tensor):
        s, dev, n = self.s, self.device, self.n
        env_m = rm.any(1)                                          # [N]
        st = s["stats"]
        w = SF["weights"]
        base = (st[..., W.S["talent"]] * w["talent"] + st[..., W.S["charisma"]] * w["charisma"]
                + st[..., W.S["popularity"]] * w["popularity"] + st[..., W.S["discipline"]] * w["discipline"]
                + st[..., W.S["reputation"]] * w["reputation"] + st[..., W.S["selfConfidence"]] * w["selfConfidence"]
                + st[..., W.S["addiction"]] * w["addiction"])       # [N,14]

        equip_bonus = (s["equip"].float() * self.T["equip_bonus"]).sum(1)          # [N]
        staff_b = s["staff"].float() * self.T["staff_bonus"]                        # [N,6]
        sound = staff_b[:, W.STAFF_ROLES.index("soundEngineer")]
        pr = staff_b[:, W.STAFF_ROLES.index("pr")]
        lawyer = staff_b[:, W.STAFF_ROLES.index("lawyer")] * 0.01
        accountant = staff_b[:, W.STAFF_ROLES.index("accountant")] * 0.01
        manager = staff_b[:, W.STAFF_ROLES.index("manager")] * 0.5
        security = staff_b[:, W.STAFF_ROLES.index("security")] * 0.3

        level_mult = 1 + (s["prod_level"] - 1) * 0.1
        producer_bonus = torch.round(5 * level_mult)               # talented spec
        profit_mult = 1.0 * (1 + lawyer)                            # talented: no profit bonus

        studio_q = self.T["studio_quality"][(s["studio"] - 1).long().clamp(0, 5)]
        tech = (equip_bonus + sound + producer_bonus) * SF["techEquipStaffProducerMult"] \
            + (s["studio"] * SF["studioLevelCoef"] + studio_q) * SF["studioMult"]   # [N]
        manager_b = manager * SF["managerMult"]
        pr_b = pr * SF["prMult"]
        security_eff = -security * 0.15

        gmod = s["genre_mod"].gather(1, s["genre"])                 # [N,14]
        trend_b = (gmod * SF["trendMult"]).clamp(-SF["trendClamp"], SF["trendClamp"])
        freak_b = (s["trash_pop"] * SF["freakMult"]).clamp(0, SF["freakClamp"])

        chaos_mult = (1 + security_eff).clamp(min=0.1)              # [N]
        chaos = s["trait_chaos"] * chaos_mult.unsqueeze(1)
        luck = _randint(SF["luck"][0], SF["luck"][1], (n, W.N_TOKENS_SLOTS), dev, self.gen) \
            * self.theta["luck_spread_mult"].unsqueeze(1)

        score = (base + tech.unsqueeze(1) + manager_b.unsqueeze(1) + pr_b.unsqueeze(1)
                 + trend_b + freak_b + s["trait_score"] + chaos * SF["chaosMult"]
                 + luck + s["text_fit"]).clamp(*SF["scoreClamp"])   # [N,14]

        # right=True: score==threshold belongs to the higher tier (TS `<` checks)
        tier = torch.bucketize(score, self.T["tier_thresholds"], right=True)  # [N,14] 0..4

        li = self.T["tier_listeners"][tier]                          # [N,14,2]
        listeners = _randint(li[..., 0], li[..., 1], (n, W.N_TOKENS_SLOTS), dev, self.gen)
        fr = self.T["tier_fan_rate"][tier]
        fans = torch.round(listeners * _uniform(fr[..., 0], fr[..., 1], (n, W.N_TOKENS_SLOTS), dev, self.gen)
                           * self.theta["fan_rate_mult"].unsqueeze(1))
        pr_t = self.T["tier_pay_rate"][tier]
        revenue = listeners * _uniform(pr_t[..., 0], pr_t[..., 1], (n, W.N_TOKENS_SLOTS), dev, self.gen) \
            * self.pay_mult.gather(1, tier)
        co = self.T["tier_cost"][tier]
        cost = _randint(co[..., 0], co[..., 1], (n, W.N_TOKENS_SLOTS), dev, self.gen) \
            * self.theta["release_cost_mult"].unsqueeze(1)
        adj_cost = torch.round(cost * (1 - accountant.unsqueeze(1)))
        money = torch.round(revenue * profit_mult.unsqueeze(1) - adj_cost)
        tk = self.T["tier_tokens"][tier]
        tokens = torch.floor(_randint(tk[..., 0], tk[..., 1], (n, W.N_TOKENS_SLOTS), dev, self.gen)
                             * self.theta["token_reward_mult"].unsqueeze(1))

        rmf = rm.float()
        s["money"] = s["money"] + (money * rmf).sum(1)
        s["fans"] = (s["fans"] + (fans * rmf).sum(1)).clamp(min=0)
        s["tokens"] = s["tokens"] + (tokens * rmf).sum(1) - rm.any(1).float()
        s["releases"] = s["releases"] + rm.any(1).float()

        pb = SF["popBoost"]
        pop_boost = torch.round((score - pb["sub"]) / pb["div"]).clamp(pb["clamp"][0], pb["clamp"][1])
        pop = s["stats"][..., W.S["popularity"]]
        s["stats"][..., W.S["popularity"]] = torch.where(rm, (pop + pop_boost).clamp(10, 90), pop)

        # producer xp / rep (per env: the released artist's tier)
        tier_env = (tier * rm.long()).sum(1)                        # exactly one slot set
        env_m_f = env_m.float()
        s["prod_xp"] = s["prod_xp"] + self.T["tier_exp"][tier_env] * env_m_f
        for _ in range(3):  # enough level-ups per single release
            up = s["prod_xp"] >= s["prod_xp_next"]
            s["prod_xp"] = torch.where(up, s["prod_xp"] - s["prod_xp_next"], s["prod_xp"])
            s["prod_level"] = s["prod_level"] + up.float()
            s["prod_xp_next"] = torch.where(up, torch.round(s["prod_xp_next"] * SF["expToNextMult"]), s["prod_xp_next"])
        s["rep"] = (s["rep"] + self.T["tier_rep"][tier_env] * env_m_f).clamp(0, 100)

        s["week_advanced"] = s["week_advanced"] & ~env_m            # release unlocks endWeek
        self.last_release_tier = torch.where(env_m, tier_env.float(), self.last_release_tier)

    # ---------- tour ----------
    def _tour(self, tm: torch.Tensor):
        s, dev, n = self.s, self.device, self.n
        st = s["stats"]
        pop = st[..., W.S["popularity"]]
        tw = TOUR["weights"]
        manager = (s["staff"][:, W.STAFF_ROLES.index("manager")].float()
                   * self.T["staff_bonus"][W.STAFF_ROLES.index("manager")] * 0.5)
        gmod = s["genre_mod"].gather(1, s["genre"])
        base = (pop * tw["popularity"] + st[..., W.S["charisma"]] * tw["charisma"]
                + st[..., W.S["reputation"]] * tw["reputation"] + gmod * tw["trend"]
                + manager.unsqueeze(1) * tw["manager"])
        health = st[..., W.S["health"]]
        pen = torch.where(health < TOUR["healthPenaltyBelow"],
                          (TOUR["healthPenaltyBelow"] - health) * TOUR["healthPenaltyMult"],
                          torch.zeros_like(health))
        luck = _randint(TOUR["luck"][0], TOUR["luck"][1], (n, W.N_TOKENS_SLOTS), dev, self.gen)
        total = (base + luck - pen).clamp(0, 100)
        success = total >= TOUR["successThreshold"]

        sc, fl = TOUR["success"], TOUR["fail"]
        rev_s = (torch.round(pop * sc["revPerPop"] + total * sc["revPerTotal"]
                             + _randint(*sc["revNoise"], (n, W.N_TOKENS_SLOTS), dev, self.gen))
                 ).clamp(*sc["revClamp"])
        rev_f = (pop * fl["revPerPop"]
                 + _randint(*fl["revNoise"], (n, W.N_TOKENS_SLOTS), dev, self.gen)).clamp(*fl["revClamp"])
        fans_s = torch.round((pop * sc["fansPerPop"] + total * sc["fansPerTotal"]).clamp(*sc["fansClamp"]))
        fans_f = _randint(fl["fansMin"], torch.round(pop * fl["fansPerPopMax"]).clamp(min=fl["fansMin"]),
                          (n, W.N_TOKENS_SLOTS), dev, self.gen)
        revenue = torch.where(success, rev_s, rev_f) * self.theta["tour_rev_mult"].unsqueeze(1)
        fans = torch.where(success, fans_s, fans_f)
        cost = (TOUR["costBase"] + torch.round(pop * TOUR["costPerPop"])) \
            * self.theta["tour_cost_mult"].unsqueeze(1)

        tmf = tm.float()
        s["money"] = s["money"] + ((revenue - cost) * tmf).sum(1)
        s["fans"] = s["fans"] + (fans * tmf).sum(1)

        d_pop = torch.where(success,
                            _randint(*TOUR["onSuccess"]["popGain"], (n, W.N_TOKENS_SLOTS), dev, self.gen),
                            -_randint(*TOUR["onFail"]["popLoss"], (n, W.N_TOKENS_SLOTS), dev, self.gen))
        d_hap = torch.where(success, torch.full_like(pop, TOUR["onSuccess"]["happinessGain"]),
                            torch.full_like(pop, -TOUR["onFail"]["happinessLoss"]))
        d_health = torch.where(success, torch.zeros_like(pop),
                               torch.full_like(pop, -TOUR["onFail"]["healthLoss"]))
        for stat, d in (("popularity", d_pop), ("happiness", d_hap), ("health", d_health)):
            v = st[..., W.S[stat]]
            st[..., W.S[stat]] = torch.where(tm, (v + d).clamp(10, 90), v)
        s["tour_cd"] = torch.where(tm, torch.full_like(s["tour_cd"], float(TOUR["cooldownWeeks"])), s["tour_cd"])

    # ---------- weekly transition ----------
    def _update_trends(self, em: torch.Tensor | None = None):
        """Trend drift for envs in [N] mask em (None = all)."""
        s, dev, n = self.s, self.device, self.n
        TR = C["trends"]
        if em is None:
            em = torch.ones(n, dtype=torch.bool, device=dev)
        em1 = em.unsqueeze(1)
        # topics
        drift = _randint(*TR["topicDrift"], (n, W.N_TOPICS), dev, self.gen)
        pop = (s["topic_pop"] + drift).clamp(*TR["topicClamp"])
        d = s["topic_dir"]
        u = torch.rand(n, W.N_TOPICS, device=dev, generator=self.gen)
        d = torch.where((d == 0) & (pop > 70), torch.ones_like(d), d)              # rising->peaking
        d = torch.where((d == 1) & (u < 0.4), torch.full_like(d, 2.0), d)          # peaking->falling
        d = torch.where((d == 2) & (pop < 30), torch.zeros_like(d), d)             # falling->rising
        s["topic_pop"] = torch.where(em1, pop, s["topic_pop"])
        s["topic_dir"] = torch.where(em1, d, s["topic_dir"])
        # genres: affinity influence summed over each genre's topics
        infl = ((pop > 60).float() - (pop < 30).float()
                + (d == 0).float() - (d == 2).float()) @ self.T["genre_affinity"].t()  # [N,6]
        old = s["genre_pop"]
        new = old + _randint(*TR["genreStep"], (n, W.N_GENRES), dev, self.gen) \
            + torch.round(self.T["genre_drift"] * TR["genreDriftMult"]) + infl
        jump = (torch.rand(n, W.N_GENRES, device=dev, generator=self.gen) < TR["genreJumpChance"]).float()
        new = new + jump * _randint(*TR["genreJump"], (n, W.N_GENRES), dev, self.gen)
        new = old + (new - old).clamp(-TR["genreMaxChange"], TR["genreMaxChange"])
        new = torch.round(new).clamp(*TR["genreClamp"])
        mod = (torch.round((new - old) * TR["modMult"])
               + _randint(*TR["modNoise"], (n, W.N_GENRES), dev, self.gen)).clamp(*TR["modClamp"])
        s["genre_pop"] = torch.where(em1, new, s["genre_pop"])
        s["genre_mod"] = torch.where(em1, mod, s["genre_mod"])

    def _end_week(self, em: torch.Tensor):
        """Weekly transition for envs in [N] bool mask em (endWeek action)."""
        s, dev, n = self.s, self.device, self.n
        alive = s["alive"]
        am = alive & em.unsqueeze(1)                                # [N,14] artists to update
        st = s["stats"]

        # 1. archetype weekly effects + jitter
        d = self.T["arch_fx"][s["archetype"]].clone()               # [N,14,9]
        for stat, rng in WK["jitter"].items():
            d[..., W.S[stat]] += _randint(*rng, (n, W.N_TOKENS_SLOTS), dev, self.gen)
        # conditionals use pre-update values (TS mutates a local copy sequentially;
        # conditions read the post-archetype/jitter values — replicate by applying
        # base delta first, then conditionals on the intermediate values)
        stx = torch.where(am.unsqueeze(-1), st + d, st)
        hap, health, add = stx[..., W.S["happiness"]], stx[..., W.S["health"]], stx[..., W.S["addiction"]]
        cond = torch.zeros_like(stx)
        cond[..., W.S["discipline"]] += (hap < WK["lowHappiness"]["below"]).float() * WK["lowHappiness"]["discipline"]
        cond[..., W.S["happiness"]] += (health < WK["lowHealth"]["below"]).float() * WK["lowHealth"]["happiness"]
        cond[..., W.S["discipline"]] += (health < WK["lowHealth"]["below"]).float() * WK["lowHealth"]["discipline"]
        cond[..., W.S["health"]] += (add > WK["highAddiction"]["above"]).float() * WK["highAddiction"]["health"]
        cond[..., W.S["happiness"]] += (add > WK["highAddiction"]["above"]).float() * WK["highAddiction"]["happiness"]
        stx = stx + torch.where(am.unsqueeze(-1), cond, torch.zeros_like(cond))

        # 2. freak emergence
        fe = WK["freakEmergence"]
        sc = stx[..., W.S["selfConfidence"]]
        tal = stx[..., W.S["talent"]]
        emerge = am & (sc > fe["selfConfidenceAbove"]) & (tal < fe["talentBelow"]) \
            & (torch.rand(n, W.N_TOKENS_SLOTS, device=dev, generator=self.gen) < fe["chance"])
        s["trash_pop"] = torch.where(
            emerge, (s["trash_pop"] + _randint(*fe["trashPopGain"], (n, W.N_TOKENS_SLOTS), dev, self.gen))
            .clamp(*fe["trashPopClamp"]), s["trash_pop"])
        stx[..., W.S["popularity"]] = stx[..., W.S["popularity"]] \
            + emerge.float() * _randint(*fe["popGain"], (n, W.N_TOKENS_SLOTS), dev, self.gen)

        # 3. rehab tick
        reh = am & s["in_rehab"]
        s["rehab_weeks"] = torch.where(reh, s["rehab_weeks"] - 1, s["rehab_weeks"])
        stx[..., W.S["health"]] = torch.where(
            reh, (stx[..., W.S["health"]] + C["rehab"]["weeklyHealthGain"]).clamp(10, 90), stx[..., W.S["health"]])
        stx[..., W.S["addiction"]] = torch.where(
            reh, (stx[..., W.S["addiction"]] - C["rehab"]["weeklyAddictionDrop"]).clamp(10, 90), stx[..., W.S["addiction"]])
        s["in_rehab"] = s["in_rehab"] & (s["rehab_weeks"] > 0)

        # 4. needs: tick, expire (penalty — STEP-0 patch), maybe new
        ticking = am & s["need_active"]
        s["need_weeks"] = torch.where(ticking, s["need_weeks"] - 1, s["need_weeks"])
        expired = ticking & (s["need_weeks"] <= 0)
        stx[..., W.S["happiness"]] = stx[..., W.S["happiness"]] \
            - expired.float() * self.T["need_penalty"][s["need_id"].long()]
        s["need_active"] = s["need_active"] & ~expired
        p_need = self.theta["need_chance"].unsqueeze(1) * WK["needInnerChance"]
        new_need = am & ~s["in_rehab"] & ~s["need_active"] \
            & (torch.rand(n, W.N_TOKENS_SLOTS, device=dev, generator=self.gen) < p_need)
        nid = torch.randint(0, W.N_NEEDS, (n, W.N_TOKENS_SLOTS), device=dev, generator=self.gen).float()
        s["need_id"] = torch.where(new_need, nid, s["need_id"])
        s["need_weeks"] = torch.where(new_need, torch.full_like(s["need_weeks"], float(WK["needWeeks"])), s["need_weeks"])
        s["need_active"] |= new_need

        # 5. artist events (weighted pick among gate-eligible templates)
        add2 = stx[..., W.S["addiction"]]
        hap2 = stx[..., W.S["happiness"]]
        gates = self.T["aev_gates"]                                  # [17,4]
        elig = (add2.unsqueeze(-1) >= gates[:, 0]) & (add2.unsqueeze(-1) <= gates[:, 1]) \
            & (hap2.unsqueeze(-1) >= gates[:, 2]) & (hap2.unsqueeze(-1) <= gates[:, 3])  # [N,14,17]
        happens = am & (torch.rand(n, W.N_TOKENS_SLOTS, device=dev, generator=self.gen)
                        < self.theta["artist_event_chance"].unsqueeze(1))
        wgt = elig.float() * self.T["aev_weight"]
        wsum = wgt.sum(-1, keepdim=True)
        happens = happens & (wsum.squeeze(-1) > 0)
        probs = torch.where(wsum > 0, wgt / wsum.clamp(min=1e-9), torch.ones_like(wgt) / W.N_ARTIST_EVENTS)
        ev = torch.multinomial(probs.view(-1, W.N_ARTIST_EVENTS), 1, generator=self.gen).view(n, W.N_TOKENS_SLOTS)
        fx = self.T["aev_fx"][ev]                                    # [N,14,9,2]
        d_ev = _randint(fx[..., 0], fx[..., 1], (n, W.N_TOKENS_SLOTS, W.N_STATS), dev, self.gen)
        stx = stx + d_ev * happens.float().unsqueeze(-1)

        # clamp all stats + write back
        s["stats"] = torch.where(am.unsqueeze(-1), stx.clamp(*WK["statClamp"]), s["stats"])

        # 6. tour cooldown tick
        s["tour_cd"] = torch.where(am, (s["tour_cd"] - 1).clamp(min=0), s["tour_cd"])

        # 7. staff salaries + week event
        salaries = (s["staff"].float() * self.T["staff_salary"]).sum(1) * self.theta["salary_mult"]
        wev = (torch.rand(n, device=dev, generator=self.gen) < self.theta["week_event_chance"]) & em
        wev_id = torch.randint(0, W.N_WEEK_EVENTS, (n,), device=dev, generator=self.gen)
        fx = self.T["week_event_fx"][wev_id] * wev.float().unsqueeze(1)  # [N,4] money,fans,rep,tokens

        emf = em.float()
        s["money"] = s["money"] + emf * (-salaries + fx[:, 0])
        s["fans"] = (s["fans"] + emf * fx[:, 1]).clamp(min=0)
        s["rep"] = (s["rep"] + emf * fx[:, 2]).clamp(0, 100)
        s["tokens"] = torch.where(em, (s["tokens"] + fx[:, 3]).clamp(min=WK["tokenStipendMin"]), s["tokens"])

        # 8. trends drift only for envs whose week is ending
        self._update_trends(em)

        # 9. win/lose
        roster = s["alive"][:, :W.ROSTER_SLOTS].sum(1)
        s["week"] = s["week"] + emf
        lose_money = s["money"] < self.theta["bankruptcy_floor"]
        lose_rej = (roster == 0) & (s["rejects"] > WL["rejectsForGameOver"])
        lose_rep = s["rep"] <= WL["repGameOverAt"]
        win_fans = s["fans"] >= WL["fansForVictory"]
        win_years = (s["week"] >= self.victory_weeks) & (roster > 0)
        timeout = s["week"] >= self.max_weeks

        newly = em & ~s["done"]
        # victory has precedence over game-over (TS assigns 'victory' last)
        for val, cond in ((1.0, win_fans), (2.0, win_years),
                          (3.0, lose_money), (4.0, lose_rep), (5.0, lose_rej), (6.0, timeout)):
            hit = newly & cond & (s["outcome"] == 0)
            s["outcome"] = torch.where(hit, torch.full_like(s["outcome"], val), s["outcome"])
        s["done"] = s["done"] | (newly & (s["outcome"] > 0))

        # 10. week reset: new pair, counters
        self._new_pair(em)
        s["rejects"] = torch.where(em, torch.zeros_like(s["rejects"]), s["rejects"])
        s["week_actions"] = torch.where(em, torch.zeros_like(s["week_actions"]), s["week_actions"])
        s["week_rejects"] = torch.where(em, torch.zeros_like(s["week_rejects"]), s["week_rejects"])
        s["week_advanced"] = s["week_advanced"] | em
