"""PPO trainer for the Producer attention policy.

Adapted from monstro/torchsim/ppo_attn.py (clipped surrogate + GAE) for a
masked categorical head and an auto-resetting env.

Reward design (decomposition panel logged every iteration — the froggo rule:
shaping must stay a MINORITY of the terminal term, measured not assumed):
  terminal: +10 win / -10 lose / 0 timeout (timeout value-bootstrapped)
  shaping:  gamma*Phi(s') - Phi(s), Phi = 3*log-fans-norm + 0.5*money-signed-log
  step:     -0.001 per decision (anti-dither)

Training horizon: 104 weeks (truncated, bootstrapped); full-length episodes
are eval-only. keep-best keys on EVAL WIN RATE, never shaped return
(the monstro keep-best pitfall).

Usage: python3 train_ppo.py [--iters 300] [--envs 4096] [--rollout 256] ...
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

LOG_FANS_MAX = math.log1p(W.OBS["fans_log_max"])


def phi(env):
    """Shaping potential [N]."""
    fans_n = (torch.log1p(env.s["fans"].clamp(min=0)) / LOG_FANS_MAX).clamp(0, 1.2)
    m = env.s["money"]
    money_n = (torch.sign(m) * torch.log1p(m.abs() / 1e3) / W.OBS["money_log_div"]).clamp(-1.25, 1.25)
    return 3.0 * fans_n + 0.5 * money_n


TERMINAL = {1: 10.0, 2: 10.0, 3: -10.0, 4: -10.0, 5: -10.0, 6: 0.0}


def terminal_reward(outcome):
    r = torch.zeros_like(outcome)
    for k, v in TERMINAL.items():
        r = torch.where(outcome == k, torch.full_like(r, v), r)
    return r


@torch.no_grad()
def collect(env, params, T, gamma, rng, panel):
    n, dev = env.n, env.device
    SF, TK, PR, MK, A, LP, V, R, D = ([] for _ in range(9))
    acc = {k: torch.zeros((), device=dev) for k in
           ("terminal", "shaping", "step", "win-fans", "win-years",
            "bankrupt", "rep", "rejects", "timeout")}
    ph = phi(env)
    for t in range(T):
        sf, tk, pr = OB.build_obs(env)
        mask = env.legal_mask()
        logits, val = PP.apply_policy(params, sf, tk, pr, mask)
        act = PP.sample(logits, rng)
        logp, _ = PP.logp_entropy(logits, act)

        env.step(act)
        done = env.s["done"].clone()
        out = env.s["outcome"].clone()

        ph_next = phi(env)
        r_shape = gamma * ph_next - ph
        r_term = torch.where(done, terminal_reward(out), torch.zeros_like(ph))
        r_step = torch.full_like(ph, -0.001)
        # truncation bootstrap: timeout (outcome 6) is not a real terminal.
        # Computed unconditionally — an .any() guard here is a GPU->CPU sync
        # every step, costlier than the extra forward.
        trunc = done & (out == 6)
        sf2, tk2, pr2 = OB.build_obs(env)
        _, v_boot = PP.apply_policy(params, sf2, tk2, pr2, env.legal_mask())
        r_term = r_term + trunc.float() * gamma * v_boot
        r = r_term + r_shape + r_step

        # GPU-side accumulation — float()/int() here would sync every step
        acc["terminal"] += r_term.sum()
        acc["shaping"] += r_shape.sum()
        acc["step"] += r_step.sum()
        for k, name in ((1, "win-fans"), (2, "win-years"), (3, "bankrupt"), (4, "rep"), (5, "rejects"), (6, "timeout")):
            acc[name] += (done & (out == k)).sum()

        SF.append(sf); TK.append(tk); PR.append(pr); MK.append(mask)
        A.append(act); LP.append(logp); V.append(val); R.append(r); D.append(done.float())

        env.reset(done)   # masked, sync-free
        ph = phi(env)
    for k, v in acc.items():   # single sync at rollout end
        panel[k] += float(v) if k in ("terminal", "shaping", "step") else int(v)
    return [torch.stack(x) for x in (SF, TK, PR, MK, A, LP, V, R, D)]


def gae(R, V, D, gamma, lam):
    T = R.shape[0]
    adv = torch.zeros_like(R)
    last = torch.zeros_like(R[0])
    for t in range(T - 1, -1, -1):
        nonterm = 1.0 - D[t]
        v_next = V[t + 1] if t + 1 < T else torch.zeros_like(V[0])
        delta = R[t] + gamma * v_next * nonterm - V[t]
        last = delta + gamma * lam * last * nonterm
        adv[t] = last
    return adv, adv + V


def ppo_update(params, opt, batch, clip, epochs, minibatch, vcoef, ent_coef):
    SF, TK, PR, MK, A, LP, V, R, D, ADV, RET = batch
    B = SF.shape[0] * SF.shape[1]
    SFb = SF.reshape(B, -1); TKb = TK.reshape(B, W.N_TOKENS_SLOTS, -1)
    PRb = PR.reshape(B, W.N_TOKENS_SLOTS); MKb = MK.reshape(B, W.N_ACTIONS)
    Ab = A.reshape(B); LPb = LP.reshape(B); ADVb = ADV.reshape(B); RETb = RET.reshape(B)
    pls, vls, ents = [], [], []
    for _ in range(epochs):
        perm = torch.randperm(B, device=SFb.device)
        for i in range(0, B, minibatch):
            mb = perm[i:i + minibatch]
            logits, val = PP.apply_policy(params, SFb[mb], TKb[mb], PRb[mb], MKb[mb])
            logp, entropy = PP.logp_entropy(logits, Ab[mb])
            ratio = (logp - LPb[mb]).exp()
            s1 = ratio * ADVb[mb]
            s2 = torch.clamp(ratio, 1 - clip, 1 + clip) * ADVb[mb]
            pl = -torch.min(s1, s2).mean()
            vl = (val - RETb[mb]).pow(2).mean()
            loss = pl + vcoef * vl - ent_coef * entropy.mean()
            opt.zero_grad(set_to_none=True)
            loss.backward()
            opt.step()
            pls.append(float(pl.detach())); vls.append(float(vl.detach()))
            ents.append(float(entropy.mean().detach()))
    return sum(pls) / len(pls), sum(vls) / len(vls), sum(ents) / len(ents)


@torch.no_grad()
def evaluate(params, n=2048, device="cuda", seed=999, max_steps=12000, argmax=True,
             theta=None, obs_theta=False):
    """Full-length episodes, greedy-argmax policy. Returns outcome stats."""
    env = ProducerEnv(n, device=device, seed=seed, theta=theta, obs_theta=obs_theta)
    rng = torch.Generator(device=device).manual_seed(seed)
    for _ in range(max_steps):
        sf, tk, pr = OB.build_obs(env)
        mask = env.legal_mask()
        logits, _ = PP.apply_policy(params, sf, tk, pr, mask)
        act = logits.argmax(-1) if argmax else PP.sample(logits, rng)
        env.step(act)
        if bool(env.s["done"].all()):
            break
    out = env.s["outcome"]
    stats = {name: float((out == k).float().mean())
             for k, name in ((1, "win-fans"), (2, "win-years"), (3, "bankrupt"),
                             (4, "rep"), (5, "rejects"), (6, "timeout"), (0, "running"))}
    stats["win"] = stats["win-fans"] + stats["win-years"]
    stats["med_weeks"] = float(env.s["week"].median())
    stats["med_log_fans"] = float(torch.log10(env.s["fans"].clamp(min=1)).median())
    return stats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--iters", type=int, default=300)
    ap.add_argument("--envs", type=int, default=4096)
    ap.add_argument("--rollout", type=int, default=256)
    ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--gamma", type=float, default=0.997)
    ap.add_argument("--lam", type=float, default=0.95)
    ap.add_argument("--clip", type=float, default=0.2)
    ap.add_argument("--epochs", type=int, default=4)
    ap.add_argument("--minibatch", type=int, default=16384)
    ap.add_argument("--vcoef", type=float, default=0.5)
    ap.add_argument("--ent0", type=float, default=0.01)
    ap.add_argument("--ent1", type=float, default=0.001)
    ap.add_argument("--train-weeks", type=int, default=104)
    ap.add_argument("--eval-every", type=int, default=20)
    ap.add_argument("--eval-envs", type=int, default=2048)
    ap.add_argument("--device", default="cuda")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--out", default="runs/ppo")
    ap.add_argument("--resume", default=None)
    ap.add_argument("--theta-ladder", default=None,
                    help="generated_worlds.json: train under domain randomization "
                         "over {default + ladder rungs}, theta-aware obs")
    args = ap.parse_args()

    dev = args.device
    outdir = Path(__file__).parent / args.out
    outdir.mkdir(parents=True, exist_ok=True)

    rungs = [{k: W.GEN_KNOBS[k][0] for k in W.KNOB_NAMES}]      # rung 0 = default
    theta = None
    obs_theta = bool(args.theta_ladder)
    if args.theta_ladder:
        ladder = json.load((Path(__file__).parent / args.theta_ladder).open())["ladder"]
        rungs += [r["knobs"] for r in ladder]
        g = torch.Generator().manual_seed(args.seed + 42)
        idx = torch.randint(0, len(rungs), (args.envs,), generator=g)
        theta = {k: torch.tensor([rungs[int(i)].get(k, W.GEN_KNOBS[k][0]) for i in idx],
                                 dtype=torch.float32, device=dev) for k in W.KNOB_NAMES}
        print(f"theta ladder: {len(rungs)} rungs (incl. default), envs randomized")

    Fs = OB.FS + (W.N_OBS_KNOBS if obs_theta else 0)
    env = ProducerEnv(args.envs, device=dev, seed=args.seed, max_weeks=args.train_weeks,
                      theta=theta, obs_theta=obs_theta)
    if args.resume:
        params, meta = PP.load(args.resume, device=dev)
        params = [(Wm.requires_grad_(True), b.requires_grad_(True)) for Wm, b in params]
        print(f"resumed from {args.resume}")
    else:
        params = PP.init_policy(Fs, OB.FM, device=dev, seed=args.seed)
    meta = {"Fs": Fs, "Fm": OB.FM, "d": 32, "H": 128, "Ht": 64, "obs_theta": obs_theta}
    opt = torch.optim.Adam(PP.opt_params(params), lr=args.lr)
    rng = torch.Generator(device=dev).manual_seed(args.seed + 1)

    best_win = -1.0
    log_path = outdir / "train_log.jsonl"
    for it in range(1, args.iters + 1):
        ent_coef = args.ent0 + (args.ent1 - args.ent0) * (it / args.iters)
        panel = {k: 0.0 for k in ("terminal", "shaping", "step")}
        for k in ("win-fans", "win-years", "bankrupt", "rep", "rejects", "timeout"):
            panel[k] = 0
        t0 = time.time()
        SF, TK, PR, MK, A, LP, V, R, D = collect(env, params, args.rollout, args.gamma, rng, panel)
        with torch.no_grad():
            ADV, RET = gae(R, V, D, args.gamma, args.lam)
            ADV = (ADV - ADV.mean()) / (ADV.std() + 1e-6)
        pl, vl, entr = ppo_update(params, opt, (SF, TK, PR, MK, A, LP, V, R, D, ADV, RET),
                                  args.clip, args.epochs, args.minibatch, args.vcoef, ent_coef)
        dt = time.time() - t0
        eps = sum(panel[k] for k in ("win-fans", "win-years", "bankrupt", "rep", "rejects", "timeout"))
        wins = panel["win-fans"] + panel["win-years"]
        rec = {"it": it, "pl": round(pl, 4), "vl": round(vl, 4), "ent": round(entr, 3),
               "train_eps": eps, "train_win": round(wins / max(eps, 1), 3),
               "panel_terminal": round(panel["terminal"], 0), "panel_shaping": round(panel["shaping"], 0),
               "panel_step": round(panel["step"], 0),
               "outcomes": {k: panel[k] for k in ("win-fans", "win-years", "bankrupt", "rep", "rejects", "timeout")},
               "sps": round(args.rollout * args.envs / dt)}
        print(f"[{it:4}] pl {pl:+.3f} vl {vl:.3f} ent {entr:.2f} | eps {eps:5} "
              f"win {rec['train_win']:.3f} | term {panel['terminal']:+.0f} shape {panel['shaping']:+.0f} "
              f"| {rec['sps']:,} sps")

        if it % args.eval_every == 0 or it == args.iters:
            if obs_theta:
                # per-rung eval; keep-best on the MEAN win across rungs
                per_rung = []
                for ri, rk in enumerate(rungs):
                    th = {k: torch.full((args.eval_envs,), float(rk.get(k, W.GEN_KNOBS[k][0])), device=dev)
                          for k in W.KNOB_NAMES}
                    ev = evaluate(params, n=args.eval_envs, device=dev, seed=999 + ri,
                                  theta=th, obs_theta=True)
                    per_rung.append(ev)
                    print(f"      EVAL rung{ri} win {ev['win']:.3f} bankrupt {ev['bankrupt']:.3f} "
                          f"med_weeks {ev['med_weeks']:.0f}")
                mean_win = sum(e["win"] for e in per_rung) / len(per_rung)
                rec["eval"] = {"mean_win": round(mean_win, 4),
                               "rungs": [round(e["win"], 4) for e in per_rung]}
                score_for_best = mean_win
                print(f"      EVAL mean win {mean_win:.3f}")
            else:
                ev = evaluate(params, n=args.eval_envs, device=dev, seed=999)
                rec["eval"] = {k: round(v, 4) for k, v in ev.items()}
                score_for_best = ev["win"]
                print(f"      EVAL win {ev['win']:.3f} (fans {ev['win-fans']:.3f} years {ev['win-years']:.3f}) "
                      f"bankrupt {ev['bankrupt']:.3f} med_weeks {ev['med_weeks']:.0f} "
                      f"med_log_fans {ev['med_log_fans']:.2f}")
            if score_for_best > best_win:
                best_win = score_for_best
                PP.save(params, meta, outdir / "best.json")
                print(f"      new best ({best_win:.3f}) -> {outdir/'best.json'}")
            PP.save(params, meta, outdir / "last.json")
        with log_path.open("a") as f:
            f.write(json.dumps(rec) + "\n")

    PP.save(params, meta, outdir / "last.json")
    print(f"done. best eval win rate: {best_win:.3f}")


if __name__ == "__main__":
    main()
