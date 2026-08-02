"""CEM search over game-design hyperparameters theta (Phase 4).

"I don't want to program levels — I want something learnable that does it":
theta = the 16 GEN_KNOBS of world_config (tier payouts, costs, salaries,
event chances, starting money, luck spread, bankruptcy floor). A candidate
theta IS a game balance. Fitness = how close the frozen trained agent's
win rate lands to the target for a difficulty level d, plus shape terms.

Because ProducerEnv takes per-env theta, one batch evaluates the whole CEM
population at once: [P_cand x N_seeds] envs, each block running its own
candidate game. Zero gradient machinery; robust to the game's heavy tails.

Output: a difficulty ladder theta(d) written to
torchsim/data/generated_worlds.json — game-readable knob tables the TS game
could consume directly (no torch on device).

Usage:
  python3 cem_gen.py --policy runs/v1/best.json --targets 0.85,0.6,0.35,0.15
"""

import argparse
import json
import math
import time
from pathlib import Path

import torch

import world_config as W
from env_producer import ProducerEnv
import obs_producer as OB
import policy_producer as PP

KNOB_LO = torch.tensor([W.GEN_KNOBS[k][1] for k in W.KNOB_NAMES])
KNOB_HI = torch.tensor([W.GEN_KNOBS[k][2] for k in W.KNOB_NAMES])
KNOB_DEFAULT = torch.tensor([W.GEN_KNOBS[k][0] for k in W.KNOB_NAMES])


def theta_to_dict(theta_row: torch.Tensor, n: int, device) -> dict:
    """[K] candidate -> per-env theta dict of [n] tensors."""
    return {k: torch.full((n,), float(theta_row[i]), device=device)
            for i, k in enumerate(W.KNOB_NAMES)}


@torch.no_grad()
def eval_population(thetas: torch.Tensor, params, seeds: int, device: str,
                    eval_weeks: int, seed: int, max_steps: int = 4000,
                    obs_theta: bool = False):
    """thetas [P,K] -> dict of per-candidate stats (win rate within eval_weeks,
    bankrupt rate, median weeks, activity mix)."""
    P, K = thetas.shape
    n = P * seeds
    theta = {k: thetas[:, i].repeat_interleave(seeds).to(device)
             for i, k in enumerate(W.KNOB_NAMES)}
    env = ProducerEnv(n, device=device, seed=seed, max_weeks=eval_weeks, theta=theta,
                      obs_theta=obs_theta)
    n_rel = torch.zeros(n, device=device)
    n_tour = torch.zeros(n, device=device)
    for _ in range(max_steps):
        sf, tk, pr = OB.build_obs(env)
        mask = env.legal_mask()
        logits, _ = PP.apply_policy(params, sf, tk, pr, mask)
        act = logits.argmax(-1)
        n_rel += ((act >= W.A_RELEASE) & (act < W.A_RELEASE + 12) & ~env.s["done"]).float()
        n_tour += ((act >= W.A_TOUR) & (act < W.A_TOUR + 12) & ~env.s["done"]).float()
        env.step(act)
        if bool(env.s["done"].all()):
            break
    out = env.s["outcome"].view(P, seeds)
    win = ((out == 1) | (out == 2)).float().mean(1)
    bankrupt = (out == 3).float().mean(1)
    weeks = env.s["week"].view(P, seeds).median(1).values
    tour_share = (n_tour / (n_rel + n_tour).clamp(min=1)).view(P, seeds).mean(1)
    return {"win": win.cpu(), "bankrupt": bankrupt.cpu(), "med_weeks": weeks.cpu(),
            "tour_share": tour_share.cpu()}


def score(stats, target_win: float):
    """Lower is better. Win-rate match + shape penalties:
    - instant games (med_weeks < 24) are boring at any difficulty
    - degenerate strategy mix (all-tours or no-tours) is penalized mildly
    """
    win_term = (stats["win"] - target_win).abs()
    length_pen = torch.relu(24.0 - stats["med_weeks"]) / 24.0 * 0.3
    mix = stats["tour_share"]
    mix_pen = (torch.relu(mix - 0.8) + torch.relu(0.02 - mix)) * 0.5
    return win_term + length_pen + mix_pen


def cem(params, target_win: float, device: str, pop=24, elite=6, iters=20,
        seeds=192, eval_weeks=208, seed0=1234, init_mean=None, log=print,
        obs_theta: bool = False):
    K = W.N_KNOBS
    lo, hi = KNOB_LO, KNOB_HI
    mean = ((init_mean if init_mean is not None else KNOB_DEFAULT) - lo) / (hi - lo)  # normalized
    std = torch.full((K,), 0.25)
    g = torch.Generator().manual_seed(seed0)
    best_theta, best_score = None, float("inf")
    for it in range(iters):
        z = torch.randn(pop, K, generator=g) * std + mean
        z = z.clamp(0, 1)
        z[0] = mean.clamp(0, 1)                       # elite carryover / default probe
        thetas = lo + z * (hi - lo)
        stats = eval_population(thetas, params, seeds, device, eval_weeks, seed=seed0 + it,
                                obs_theta=obs_theta)
        sc = score(stats, target_win)
        order = sc.argsort()
        el = z[order[:elite]]
        mean = 0.7 * el.mean(0) + 0.3 * mean          # smoothed update
        std = 0.7 * el.std(0) + 0.3 * std
        std = std.clamp(0.02, 0.4)
        if float(sc[order[0]]) < best_score:
            best_score = float(sc[order[0]])
            best_theta = thetas[order[0]].clone()
        log(f"  [cem {it:2}] best {float(sc[order[0]]):.3f} (win {float(stats['win'][order[0]]):.3f} "
            f"wk {float(stats['med_weeks'][order[0]]):.0f} tours {float(stats['tour_share'][order[0]]):.2f}) "
            f"| pop win {float(stats['win'].mean()):.3f} std {float(std.mean()):.3f}")
    return best_theta, best_score


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--policy", required=True)
    ap.add_argument("--targets", default="0.85,0.6,0.35,0.15",
                    help="target win rates, easy->hard")
    ap.add_argument("--device", default="cuda")
    ap.add_argument("--pop", type=int, default=24)
    ap.add_argument("--elite", type=int, default=6)
    ap.add_argument("--iters", type=int, default=20)
    ap.add_argument("--seeds", type=int, default=192)
    ap.add_argument("--eval-weeks", type=int, default=208)
    ap.add_argument("--out", default="data/generated_worlds.json")
    args = ap.parse_args()

    params, meta = PP.load(Path(__file__).parent / args.policy
                           if not Path(args.policy).is_absolute() else args.policy,
                           device=args.device)
    obs_theta = bool(meta.get("obs_theta", False)) if isinstance(meta, dict) else False
    targets = [float(t) for t in args.targets.split(",")]
    ladder = []
    init = None
    for target in targets:
        print(f"=== target win rate {target} ===")
        t0 = time.time()
        theta, sc = cem(params, target, args.device, pop=args.pop, elite=args.elite,
                        iters=args.iters, seeds=args.seeds, eval_weeks=args.eval_weeks,
                        init_mean=init, obs_theta=obs_theta)
        init = theta.clone()   # warm-start the next (harder) rung
        knobs = {k: round(float(theta[i]), 4) for i, k in enumerate(W.KNOB_NAMES)}
        ladder.append({"target_win": target, "score": round(sc, 4), "knobs": knobs})
        print(f"  -> score {sc:.3f} in {time.time()-t0:.0f}s: {knobs}")

    out_path = Path(__file__).parent / args.out
    json.dump({"policy": args.policy, "eval_weeks": args.eval_weeks, "ladder": ladder},
              out_path.open("w"), indent=1)
    print(f"ladder -> {out_path}")


if __name__ == "__main__":
    main()
