"""Final validation of the co-evolved world generator ("good for all sequence").

All at 480 weeks, fresh seeds, first-completed-episode counting.

1. Cross-table: saved players x saved generators (+ bank reference world).
   Pass: P_final x G_final in 0.62+-0.03; EARLY players clearly below their
   own-era rates vs G_final (skill mediation — if the round-0 player also
   lands ~0.62, the generator built coin-flip worlds); no cycling pattern.
2. Headline CI: P_final x G_final, 8192 episodes (+-1.05%).
3. Sequence curves: per-quarter undecided fraction / outcome mix — losses and
   wins spread across the whole 480 weeks, >25% undecided at week 104.
4. THE acceptance test: train a FRESH random-init player vs the frozen final
   generator; PASS if eval plateaus in 0.62+-0.05 with no upward grind
   (catches both residual exploitability and player-fingerprinting).
5. Predictability probe: week-4 state -> outcome AUC (healthy 0.55-0.80).

Usage: python3 validate_coevo.py [--dir runs/coevolve] [--skip-fresh]
"""

import argparse
import json
import math
from pathlib import Path

import torch

import world_config as W
from env_producer import ProducerEnv
import obs_producer as OB
import policy_producer as PP
import dealer as DL
from train_ppo import collect, gae, ppo_update
from train_dealer_es import make_text_fit_sampler
from coevolve import theta_from_z, GENOME_D, decode_theta_per_env

HERE = Path(__file__).parent


@torch.no_grad()
def play(genome, player, n, weeks, seed, device, sampler, argmax=True,
         quarter_probe=False, week4_probe=False):
    """One generator (or None = bank world) vs one player, n first-episodes.
    Returns win rate + optional per-quarter and week-4 records."""
    env = ProducerEnv(n, device=device, seed=seed, max_weeks=weeks,
                      obs_theta=True, bank_size=4096 if genome is not None else 200_000)
    if genome is not None:
        g2 = genome.view(1, -1)
        env.theta = decode_theta_per_env(g2, n, device)
        env.refresh_pay_mult()
        state = DL.DealerState(n, device)
        env.candidate_source = DL.make_candidate_source(
            g2[:, :DL.N_PARAMS].contiguous(), 1, n, env, state,
            torch.full((n,), 0.62, device=device), sampler)
        raw_reset = env.reset
        env.reset = lambda mask=None: (state.reset(
            mask if mask is not None else torch.ones(n, dtype=torch.bool, device=device)),
            raw_reset(mask))[-1]
        env.reset()
    rng = torch.Generator(device=device).manual_seed(seed + 1)

    wins = torch.zeros(n, device=device)
    eps = torch.zeros(n, device=device)
    end_wk = torch.zeros(n, device=device)
    outc = torch.zeros(n, device=device)
    wk4 = None
    for _ in range(weeks * 9 + 400):
        sf, tk, pr = OB.build_obs(env)
        mask = env.legal_mask()
        logits, _ = PP.apply_policy(player, sf, tk, pr, mask)
        act = logits.argmax(-1) if argmax else torch.multinomial(
            torch.softmax(logits, -1), 1, generator=rng).squeeze(1)
        wk_before = env.s["week"].clone()
        if week4_probe and wk4 is None and bool((wk_before >= 4).any()):
            pass
        env.step(act)
        if week4_probe and wk4 is None:
            crossed = (wk_before < 4) & (env.s["week"] >= 4) & (eps < 1)
            if bool(crossed.all()) or bool((env.s["week"].min() >= 4)):
                s = env.s
                wk4 = torch.stack([
                    s["money"], s["fans"], s["tokens"], s["rep"],
                    s["alive"][:, :12].sum(1).float(), s["releases"],
                    s["stats"][:, :12, W.S["talent"]].mean(1),
                ], dim=1).clone()
        done, out = env.s["done"], env.s["outcome"]
        first = done & (eps < 1)
        wins += (first & ((out == 1) | (out == 2))).float()
        end_wk += first.float() * env.s["week"]
        outc = torch.where(first.bool(), out.float(), outc)
        eps += first.float()
        env.reset(done)
        if bool((eps >= 1).all()):
            break

    res = {"win": float(wins.mean()), "n": n,
           "med_end_wk": float(end_wk.median()),
           "outcomes": {name: float((outc == k).float().mean())
                        for k, name in ((1, "win-fans"), (2, "win-years"),
                                        (3, "bankrupt"), (4, "rep"), (5, "rejects"),
                                        (6, "timeout"))}}
    if quarter_probe:
        res["undecided_at"] = {str(wk): float((end_wk > wk).float().mean())
                               for wk in (26, 52, 104, 208, 320, 480 - 1)}
        res["end_wk_quartiles"] = [float(end_wk.quantile(q)) for q in (0.25, 0.5, 0.75)]
    if week4_probe and wk4 is not None:
        res["_wk4"] = wk4
        res["_won"] = ((outc == 1) | (outc == 2)).float()
    return res


def auc_probe(wk4, won):
    """Logistic regression week-4 features -> outcome, in-torch, report AUC."""
    x = (wk4 - wk4.mean(0)) / wk4.std(0).clamp(min=1e-6)
    y = won
    w = torch.zeros(x.shape[1], device=x.device, requires_grad=True)
    b = torch.zeros(1, device=x.device, requires_grad=True)
    opt = torch.optim.Adam([w, b], lr=0.05)
    for _ in range(300):
        loss = torch.nn.functional.binary_cross_entropy_with_logits(x @ w + b, y)
        opt.zero_grad(); loss.backward(); opt.step()
    with torch.no_grad():
        score = x @ w + b
        pos, neg = score[y > 0.5], score[y < 0.5]
        if len(pos) == 0 or len(neg) == 0:
            return 1.0
        return float((pos.unsqueeze(1) > neg.unsqueeze(0)).float().mean())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="runs/coevolve")
    ap.add_argument("--device", default="cuda")
    ap.add_argument("--skip-fresh", action="store_true")
    ap.add_argument("--fresh-iters", type=int, default=60)
    args = ap.parse_args()
    dev = args.device
    outdir = HERE / args.dir
    sampler = make_text_fit_sampler(dev)

    final = torch.load(outdir / "generator_final.pt", map_location=dev)
    gen_final = final["gen_mean"][0].to(dev)
    ckpts = sorted(outdir.glob("ckpt_r*.pt"))
    picks = [c for i, c in enumerate(ckpts) if (i + 1) % 5 == 0 or c == ckpts[-1]]
    saved = [torch.load(c, map_location=dev) for c in picks]
    p_ref, meta = PP.load(HERE / "runs/v2_ladder/best.json", device=dev)
    players = [("P0_v2ref", p_ref)] + [(f"P{c['round']}", c["player"]) for c in saved]
    gens = [("G_ref(bank)", None)] + [(f"G{c['round']}", c["gen_mean"][0].to(dev)) for c in saved]
    gens.append(("G_final", gen_final))

    print("=== 1. cross-table (2048 eps/cell, 480wk) — win rate ===")
    print(f"{'':12}" + "".join(f"{g[0]:>14}" for g in gens))
    table = {}
    for pi, (pname, pp) in enumerate(players):
        row = []
        for gi, (gname, gg) in enumerate(gens):
            r = play(gg, pp, 2048, 480, 900_000 + pi * 100 + gi, dev, sampler)
            row.append(r["win"])
            table[f"{pname}x{gname}"] = round(r["win"], 4)
        print(f"{pname:12}" + "".join(f"{v:14.3f}" for v in row))

    print("\n=== 2. headline: P_final x G_final, 8192 eps ===")
    pf = players[-1][1]
    head = play(gen_final, pf, 8192, 480, 990_001, dev, sampler, quarter_probe=True,
                week4_probe=True)
    ci = 1.96 * math.sqrt(head["win"] * (1 - head["win"]) / head["n"])
    print(f"win {head['win']:.4f} ± {ci:.4f} | outcomes {head['outcomes']}")
    print(f"undecided at week: {head['undecided_at']}")
    print(f"end-week quartiles: {head['end_wk_quartiles']}")

    auc = auc_probe(head["_wk4"], head["_won"]) if "_wk4" in head else None
    print(f"\n=== 5. predictability: week-4 -> outcome AUC = {auc:.3f} "
          f"({'healthy' if auc and 0.5 <= auc <= 0.85 else 'CHECK'}) ===")

    results = {"cross_table": table,
               "headline": {k: v for k, v in head.items() if not k.startswith("_")},
               "auc_week4": auc}

    if not args.skip_fresh:
        print("\n=== 4. FRESH-PLAYER acceptance test ===")
        fresh = PP.init_policy(OB.FS + W.N_OBS_KNOBS, OB.FM, device=dev, seed=4242)
        opt = torch.optim.Adam(PP.opt_params(fresh), lr=3e-4)
        n = 8192
        env = ProducerEnv(n, device=dev, seed=31337, max_weeks=208, obs_theta=True,
                          bank_size=4096)
        g2 = gen_final.view(1, -1)
        env.theta = decode_theta_per_env(g2, n, dev)
        env.refresh_pay_mult()
        state = DL.DealerState(n, dev)
        env.candidate_source = DL.make_candidate_source(
            g2[:, :DL.N_PARAMS].contiguous(), 1, n, env, state,
            torch.full((n,), 0.62, device=dev), sampler)
        raw_reset = env.reset
        env.reset = lambda mask=None: (state.reset(
            mask if mask is not None else torch.ones(n, dtype=torch.bool, device=dev)),
            raw_reset(mask))[-1]
        env.reset()
        rng = torch.Generator(device=dev).manual_seed(7)
        evals = []
        for it in range(1, args.fresh_iters + 1):
            panel = {k: 0.0 for k in ("terminal", "shaping", "step")}
            for k in ("win-fans", "win-years", "bankrupt", "rep", "rejects", "timeout"):
                panel[k] = 0
            batch = collect(env, fresh, 64, 0.997, rng, panel)
            with torch.no_grad():
                ADV, RET = gae(batch[7], batch[6], batch[8], 0.997, 0.95)
                ADV = (ADV - ADV.mean()) / (ADV.std() + 1e-6)
            ppo_update(fresh, opt, tuple(batch) + (ADV, RET), 0.2, 4, 16384, 0.5, 0.005)
            if it % 5 == 0:
                r = play(gen_final, [(w.detach(), b.detach()) for w, b in fresh],
                         4096, 480, 550_000 + it, dev, sampler)
                evals.append((it, r["win"]))
                print(f"  fresh iter {it:3}: win {r['win']:.3f}")
        last3 = [w for _, w in evals[-3:]]
        xs = torch.tensor([float(i) for i, _ in evals[-6:]])
        ys = torch.tensor([w for _, w in evals[-6:]])
        slope = float(((xs - xs.mean()) * (ys - ys.mean())).sum()
                      / ((xs - xs.mean()) ** 2).sum().clamp(min=1e-9))
        ok_band = all(abs(w - 0.62) <= 0.05 for w in last3)
        ok_slope = slope < 0.005
        print(f"  last-3 in 0.62±0.05: {'PASS' if ok_band else 'FAIL'} {last3}")
        print(f"  slope last 6 evals: {slope:+.4f}/iter ({'PASS' if ok_slope else 'FAIL'})")
        results["fresh_player"] = {"evals": evals, "band": ok_band, "slope": slope}

    json.dump(results, (outdir / "validation.json").open("w"), indent=1)
    print(f"\n-> {outdir/'validation.json'}")


if __name__ == "__main__":
    main()
