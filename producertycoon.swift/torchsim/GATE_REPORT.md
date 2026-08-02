# STEP-0 Degeneracy Gate — Report

**Date:** 2026-07-09 · **Harness:** `scripts/gateRun.ts` (headless, seeded mulberry32 over `Math.random`) · **Analyzer:** `torchsim/gate_analyze.py` · **Protocol:** N=1000 paired seeds × 8 scripted policies, cap 16 actions/week.

## Verdict

1. **Original game (as committed at ef2096a): HARD DEGENERATE — mathematically unwinnable.**
   8000 episodes, **0 wins**, 100% bankruptcy/stall within **20 weeks** of a 480-week game, under every strategy including oracle-informed greedy. Median all-time money *peak* = the starting 5000. Zero tours were ever affordable.
2. **After the balance patch (5 changes below): PASS.**
   Clean skill ladder, all gaps ≥ 10 win-points at p < 1e-59, two distinct viable win paths, sane variance. The game is now worth training an agent on.

## Root cause of unwinnability (measured, then verified in source)

`payRate` in `src/lib/calculateRelease.ts` made **every** release tier below Культовий шедевр lose money on average — and `endWeek` refuses to advance without a release each week (`_weekAdvanced` guard, `useGameStore.ts:460`):

| Tier | avg revenue (old) | avg cost | avg net (old) | avg net (new) |
|---|---|---|---|---|
| Провал | ~2 | 7 500 | **−7 500** | −7 500 (unchanged) |
| Локальний мем | ~95 | 5 000 | **−4 900** | ≈ −2 200 |
| Нормальний реліз | ~920 | 6 500 | **−5 600** | ≈ +6 200 |
| Хіт | ~9 900 | 12 500 | **−2 600** | ≈ +34 500 |
| Культовий шедевр | ~121 000 | 19 000 | +102 000 | ≈ +201 000 |

Forced weekly bleed of ~4–8k from a 5k start hit the −50k bankruptcy floor in 6–13 weeks. Tours (the only money-positive mechanic) cost 15k + pop×500 ≈ 40k up front — never reachable. The loop had no entry point.

## The balance patch

1. **`calculateRelease.ts` TIERS payRate** re-targeted to the net EVs in the table above (Провал stays punishing; quality is now monotonically rewarded).
2. **Starting money 5 000 → 20 000** (`useGameStore.ts` `initialLabel`).
3. **Tour cooldown 4 weeks** (`startTour` blocked while `tour.weeksLeft > 0`; decremented in `endWeek`) — otherwise instant repeatable tours become a money printer under the fixed economy.
4. **Need expiry now applies its happiness penalty** in `endWeek` — previously `ignoreNeed` was strictly dominated by silently waiting out the 2-week timer.
5. **Token stipend: ≥1 token after every `endWeek`** — fixes a real soft-lock: with 0 tokens you cannot release, and without a release you can never end the week again.

## Gate results after the patch (N=1000 per policy)

| Policy | sees | win% | median weeks | median fans | tours (succ%) |
|---|---|---|---|---|---|
| greedy-heuristic | everything | **68.7** | 63 | 100.8M | 6 014 (70%) |
| lean-tourer | tour-EV stats | 43.7 | 224 | 2.1M | 28 242 (72%) |
| never-upgrade | all but purchases | 40.0 | 153 | 1.9M | 26 763 (75%) |
| sign-quality-blind | all but candidate stats | 37.7 | 18 | 74k | 5 715 (63%) |
| all-in-upgrades | money only | 31.9 | 19 | 37k | 0 |
| tour-spam | popularity only | 9.1 | 22 | 37k | 34 966 (34%) |
| sign-release-spam | nothing | 8.3 | 13 | 38k | 0 |
| random-legal | nothing | 0.0 | 6 | 11k | 0 |

Gate criteria: greedy beats every observation-blind policy by ≥ 36.8 pts (McNemar p ≤ 5e-71, KS on log-fans p ≤ 2e-70); **artist stats matter** (quality-blind −31.0 pts); variance sane (within-policy IQR 2.98 < 3 × 3.97 cross-policy spread). Two distinct win paths exist: fans-rush (greedy, week ~63) vs 10-year survival (lean-tourer/never-upgrade) — good sign for strategy diversity in training and for the CEM generator later.

Headroom above greedy is plausible (31% of greedy runs still go bankrupt — risk management is unsolved), so the Phase-3 target "beat greedy by ≥10 pts" is meaningful.

## Additional findings (not patched)

- **The text layer is a constant for auto-generated lyrics.** Across 10 000 generated artists × 48 genre/archetype combos: `textFitBonus` always in [−10, −6] (mean −7.58), `cringeBonus` = 0 always, `scandalPenalty` = 0 always (`torchsim/data/text_bonus_dist.json`). The meme/scandal mechanics only fire on player-written lyrics. For the torch env the layer collapses to ≈ −7.6 ± 1; as game design, generated texts never engaging 400 lines of mechanics is worth revisiting.
- **`startGame` does not reset `labelSlotIndex`** (only `restart` does). Harmless in the current UI flow (restart always precedes), fragile to future flows.
- `charts` state is declared but never populated; `viralExtra` is computed but unused in scoring.

## Artifacts

- `scripts/seededRandom.ts`, `scripts/headless.ts`, `scripts/policies.ts`, `scripts/gateRun.ts`, `scripts/textBonusDist.ts`
- `torchsim/gate_analyze.py` (verdict tool, exits non-zero on FAIL — reusable as a balance regression test)
- `torchsim/data/gate/*.jsonl` (8 000 episodes), `torchsim/data/text_bonus_dist.json`
- Game-source diffs: `src/lib/calculateRelease.ts` (TIERS), `src/store/useGameStore.ts` (5 spots), `src/lib/musicApi.ts` (headless guard)

**Gate to Phase 1: OPEN.** Constants extraction + parity harness may proceed against the patched game.
