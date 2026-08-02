"""OpenAI-ES trainer for the artist DEALER (learned content generator).

One dealer network, conditioned on target win rate, learns to deal artist
streams that make the FROZEN v2 agent win at the requested rate — content
as the difficulty lever, instead of (or on top of) the theta knobs, which
stay at defaults here.

Population of E antithetic weight perturbations; each evaluated on
S = 3 targets x seeds_per episodes; ALL E x S games run in ONE batched env
(dealer forward is population-batched). Fitness = mean |win - target|.

Usage: python3 train_dealer_es.py [--gens 60] [--pop 64] [--seeds-per 32]
"""

import argparse
import json
import time
from pathlib import Path

import torch

import world_config as W
from env_producer import ProducerEnv
import obs_producer as OB
import policy_producer as PP
import dealer as DL

TARGETS = [0.85, 0.6, 0.35]


def make_text_fit_sampler(device):
    with (W.DATA_DIR / "text_bonus_dist.json").open() as f:
        tdist = json.load(f)
    vals = torch.tensor([float(k) for k in tdist["overall"]["fit"].keys()], device=device)
    cnts = torch.tensor([float(v) for v in tdist["overall"]["fit"].values()], device=device)
    probs = cnts / cnts.sum()

    def sampler(shape):
        n = int(torch.tensor(shape).prod())
        idx = torch.multinomial(probs, n, replacement=True)
        return vals[idx].view(*shape)
    return sampler


@torch.no_grad()
def eval_dealer_pop_online(flat, agent_params, pop, seeds_per, device, gen_idx,
                           eval_weeks=208, max_steps=3200):
    """flat [E,D] -> fitness [E] (lower better), per-target win matrix [E,3].
    Envs auto-reset; wins/episodes counted online (outcomes are lost at reset)."""
    S = len(TARGETS) * seeds_per
    n = pop * S
    target_row = torch.tensor(TARGETS, device=device).repeat_interleave(seeds_per)
    difficulty = target_row.repeat(pop)

    env = ProducerEnv(n, device=device, seed=10_000 + gen_idx, max_weeks=eval_weeks,
                      obs_theta=True)
    state = DL.DealerState(n, device)
    sampler = make_text_fit_sampler(device)
    env.candidate_source = DL.make_candidate_source(
        flat, pop, S, env, state, difficulty, sampler)
    env.reset()

    wins = torch.zeros(n, device=device)
    eps = torch.zeros(n, device=device)
    dealt_talent = torch.zeros((), device=device)  # running mean probes
    for _ in range(max_steps):
        sf, tk, pr = OB.build_obs(env)
        mask = env.legal_mask()
        logits, _ = PP.apply_policy(agent_params, sf, tk, pr, mask)
        env.step(logits.argmax(-1))
        done = env.s["done"]
        out = env.s["outcome"]
        wins += (done & ((out == 1) | (out == 2))).float()
        eps += done.float()
        state.reset(done)
        env.reset(done)
        if bool((eps.view(pop, S).min() >= 1).all()):
            break

    win_rate = (wins / eps.clamp(min=1)).view(pop, len(TARGETS), seeds_per).mean(-1)  # [E,3]
    tgt = torch.tensor(TARGETS, device=device).unsqueeze(0)
    fitness = (win_rate - tgt).abs().mean(1)                                          # [E]
    no_ep = (eps.view(pop, S).sum(1) == 0)
    fitness = torch.where(no_ep, torch.full_like(fitness, 1.0), fitness)
    return fitness, win_rate


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gens", type=int, default=60)
    ap.add_argument("--pop", type=int, default=64)          # antithetic pairs = pop/2
    ap.add_argument("--seeds-per", type=int, default=32)
    ap.add_argument("--sigma", type=float, default=0.05)
    ap.add_argument("--lr", type=float, default=0.03)
    ap.add_argument("--agent", default="runs/v2_ladder/best.json")
    ap.add_argument("--device", default="cuda")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--out", default="runs/dealer_v1")
    args = ap.parse_args()

    dev = args.device
    outdir = Path(__file__).parent / args.out
    outdir.mkdir(parents=True, exist_ok=True)
    agent_params, meta = PP.load(Path(__file__).parent / args.agent, device=dev)
    assert meta.get("obs_theta"), "dealer training expects the theta-aware v2 agent"

    g = torch.Generator().manual_seed(args.seed)
    mean = DL.init_dealer(1, device=dev, seed=args.seed, scale=0.05)
    half = args.pop // 2

    log_path = outdir / "es_log.jsonl"
    best_fit = float("inf")
    for gen in range(1, args.gens + 1):
        t0 = time.time()
        eps = torch.randn(half, DL.N_PARAMS, generator=g).to(dev)
        noise = torch.cat([eps, -eps], 0)                       # antithetic
        flat = mean + args.sigma * noise                        # [E,D]
        fitness, win_rate = eval_dealer_pop_online(
            flat, agent_params, args.pop, args.seeds_per, dev, gen)
        # rank-shaped ES update (lower fitness = better)
        ranks = fitness.argsort().argsort().float()
        shaped = (ranks / (args.pop - 1)) - 0.5                  # best -> -0.5
        grad = (shaped.unsqueeze(1) * noise).mean(0) / args.sigma
        mean = mean - args.lr * grad.unsqueeze(0)

        fit_best = float(fitness.min())
        best_idx = int(fitness.argmin())
        wr = [round(float(x), 3) for x in win_rate[best_idx]]
        wr_mean = [round(float(x), 3) for x in win_rate.mean(0)]
        rec = {"gen": gen, "fit_best": round(fit_best, 4),
               "fit_mean": round(float(fitness.mean()), 4),
               "best_wr": wr, "pop_wr": wr_mean, "sec": round(time.time() - t0, 1)}
        print(f"[{gen:3}] fit best {fit_best:.4f} mean {float(fitness.mean()):.4f} "
              f"| best wr {wr} (targets {TARGETS}) | {rec['sec']}s")
        with log_path.open("a") as f:
            f.write(json.dumps(rec) + "\n")
        if fit_best < best_fit:
            best_fit = fit_best
            torch.save({"mean": mean.cpu(), "best": flat[best_idx].cpu(),
                        "targets": TARGETS}, outdir / "dealer_best.pt")
    torch.save({"mean": mean.cpu(), "targets": TARGETS}, outdir / "dealer_mean.pt")
    print(f"done. best fitness {best_fit:.4f}")


if __name__ == "__main__":
    main()
