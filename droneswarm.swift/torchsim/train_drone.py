"""droneswarm co-evolution trainer — drone brain (CTBR) vs coevolving enemy brain (unicycle/social-
force + anti-air), both PPO over the shared attention policy. Follows monstro train_torch anatomy,
simplified per froggo train_froggo:

  * --enemy-every K   : the enemy trains 1-in-K iters (the drones get K-1 PPO steps each) — slows the
                        arms race so the drone side can converge (monstro cadence gate).
  * --enemy-pool N    : PSRO-lite league — the drones train against a random snapshot from the last N
                        enemies, damping Red-Queen oscillation.
  * --keep-best       : eval vs a FIXED reference enemy (frozen iter-0 snapshot) every --eval-every and
                        keep the peak-clear% checkpoint, NOT the (possibly collapsed) final weights.
  * --freeze-enemy    : escape hatch — freeze the enemy entirely so the drones converge vs a static foe
                        (use if the AA-armed enemy runs away before the swarm can fly).
  * AA curriculum     : --aa-warmup ramps enemy anti-air lethality 0->1 (env.set_aa_scale, no recompile).

The eval metric is CLEAR% = enemies killed / total, vs the fixed reference — an absolute progress
signal, not the co-evolution arms race. Reward weights are set BEFORE torch.compile(env._core).
"""
import argparse
import json
import math
import os
import random
import time

import numpy as np
import torch

import policy_attn as AT
import policy_recur as RE
import ppo_team as PPO
import schedule_drone as S
from env_drone import EnvDrone, game_loop
from world_config_drone import WorldConfig

EVAL_VS_CHOICES = ("fixed", "live")     # ONE source of truth (monstro's train_multi mismatch bug avoided)


def snap_d(params, log_std):            # drone = recurrent (dict params)
    return RE.snap(params, log_std)


def snap_e(params, log_std):            # enemy = feedforward attention (list-of-tuples params)
    return (AT.snap(params), log_std.detach().clone())


def pick_device(arg):
    if arg != "auto":
        return arg
    if torch.cuda.is_available():
        return "cuda"
    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return "mps"
    return "cpu"


@torch.no_grad()
def evaluate(env, dparams, eparams, K_dec, H, mm_dtype=None):
    """Deterministic (mean-action) rollout of the RECURRENT drone vs the given feedforward enemy.
    Returns (clear_pct, full_clear, exchange_ratio, mean_kills). clear% = kills / E."""
    def dfn(sf, tk, mk, ef, em, dm, dpxy, h_in):                 # recurrent GROUP drone (mean action + target assignment)
        mu, _, h_new, a_hard = RE.apply_recur(dparams, sf, tk, mk, ef, em, dm, dpxy, h_in, mm_dtype)
        return mu, h_new, a_hard
    efn = lambda sf, tk, mk: AT.apply_attn(eparams, sf, tk, mk, mm_dtype)[0]
    s = game_loop(env, dfn, efn, 1, K_dec, drone_recur=True, latent_h=H)
    E = env.E
    kills = s["kills"][0]                                        # [N]
    losses = s["losses"][0]
    clear = float((kills / E).mean())
    full = float((kills >= E - 0.5).float().mean())
    exch = float((kills / (losses + 1.0)).mean())
    return clear, full, exch, float(kills.mean())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", default="auto")
    ap.add_argument("--budget", type=float, default=300.0, help="wall-clock seconds")
    ap.add_argument("--iters", type=int, default=100000)
    ap.add_argument("--n-envs", type=int, default=1024)
    ap.add_argument("--drones", type=int, default=16); ap.add_argument("--enemies", type=int, default=12)
    ap.add_argument("--obstacles", type=int, default=24)
    ap.add_argument("--ticks", type=int, default=750, help="physics ticks per episode (T)")
    ap.add_argument("--ppo-group", type=int, default=4, help="P: rollout copies (drone phase)")
    ap.add_argument("--enemy-group", type=int, default=8)
    ap.add_argument("--ppo-lr", type=float, default=1e-4)
    ap.add_argument("--ppo-minibatch", type=int, default=262144)
    ap.add_argument("--ppo-epochs", type=int, default=2)
    ap.add_argument("--attn-dim", type=int, default=32); ap.add_argument("--attn-hidden", type=int, default=64)
    ap.add_argument("--gamma", type=float, default=0.98); ap.add_argument("--ent", type=float, default=0.0)
    ap.add_argument("--sapo-target-entropy", type=float, default=-2.0,
                    help="SAPO auto-alpha target policy entropy (SAC dual): alpha rises when H drops below this")
    ap.add_argument("--sapo-alpha-lr", type=float, default=3e-3, help="SAPO temperature (log_alpha) learning rate")
    ap.add_argument("--sapo-alpha0", type=float, default=0.1, help="SAPO initial entropy temperature alpha")
    ap.add_argument("--shac-horizon", type=int, default=6, help="SHAC/SAPO BPTT window length in decisions")
    # SHAC hyperparameters (defaults from the SHAC paper; ours were mistuned — LR 20x too low, no TD-lambda/EMA):
    ap.add_argument("--shac-lr", type=float, default=2e-3, help="SHAC actor LR (analytic grads are clean -> big steps; PPO enemy keeps --ppo-lr)")
    ap.add_argument("--shac-lambda", type=float, default=0.95, help="TD(lambda) for the SHAC critic value targets")
    ap.add_argument("--shac-tau", type=float, default=0.005, help="EMA rate of the SHAC value TARGET network")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--compile", action="store_true")
    ap.add_argument("--policy-bf16", action="store_true")
    ap.add_argument("--enemy-every", type=int, default=4)
    ap.add_argument("--enemy-pool", type=int, default=6)
    ap.add_argument("--freeze-enemy", action="store_true")
    ap.add_argument("--aa-warmup", type=int, default=15, help="iters to ramp AA lethality 0->1")
    ap.add_argument("--no-aa", action="store_true", help="eject enemy anti-air fire (enemies only maneuver); re-inject by omitting this flag")
    ap.add_argument("--kill-curriculum", type=float, nargs=2, default=None, metavar=("START_MULT", "ANNEAL_ITERS"),
                    help="bootstrap kills: kamikaze radius starts START_MULT x the real radius and anneals to 1x over ANNEAL_ITERS iters")
    # WorldConfig overrides (for tiny-env debugging: shrink the world so a trivial task iterates fast)
    ap.add_argument("--arena-half", type=float, default=None)
    ap.add_argument("--combat-half", type=float, default=None,
                    help="central combat-zone half-extent; spawns+edge+homing key off this (big arena, central fight)")
    ap.add_argument("--ceiling", type=float, default=None)
    ap.add_argument("--engage-range", type=float, default=None)
    ap.add_argument("--terrain-amp", type=float, default=None)
    ap.add_argument("--std0", type=float, default=None, help="initial exploration std for both policies")
    ap.add_argument("--eval-every", type=int, default=20); ap.add_argument("--eval-seeds", type=int, default=16)
    ap.add_argument("--keep-best", action="store_true")
    ap.add_argument("--out-dir", default="runs")
    ap.add_argument("--render", default=None)
    ap.add_argument("--init-drone", default=None); ap.add_argument("--init-enemy", default=None)
    args = ap.parse_args()

    dev = pick_device(args.device)
    mm_dtype = torch.bfloat16 if args.policy_bf16 and dev == "cuda" else None
    cfg = WorldConfig()
    for k in ("arena_half", "combat_half", "ceiling", "engage_range", "terrain_amp", "std0"):   # tiny-env / debug overrides
        v = getattr(args, k, None)
        if v is not None and k != "std0":
            setattr(cfg, k, v)
    K_dec = args.ticks // cfg.act_every
    D, E, O, T = args.drones, args.enemies, args.obstacles, args.ticks
    if dev == "cuda":
        torch.set_float32_matmul_precision("high")             # TF32 for the fp32 GEMMs (GRU/critic); modern API (2.9+)

    env = EnvDrone(S.build(cfg, args.n_envs, D, E, O, T, base_seed=0), device=dev, cfg=cfg)
    ev_env = EnvDrone(S.build_eval(cfg, args.eval_seeds, D, E, O, T), device=dev, cfg=cfg)
    if args.no_aa:                                              # gentle eject (set BEFORE compile -> baked in)
        env.aa_enabled = False; ev_env.aa_enabled = False
    if args.compile:
        env._core = torch.compile(env._core)                    # AFTER reward weights (they are attrs, set in __init__)
        # Compile the field build too -- NOT for speed (static = 1 build/episode) but for MEMORY: eager materializes
        # the [N,G,G,O,3] occupancy transient (~6GB at N=32k) and OOMs; inductor fuses dvec->sdf->amin into registers
        # so it's never allocated -> lets N go high enough to fill VRAM.
        env._build_navfield = torch.compile(env._build_navfield)

    torch.manual_seed(args.seed)
    H = args.attn_hidden                                        # GRU latent width (= attn encoder width)
    std0 = args.std0 if args.std0 is not None else 0.5
    hover_bias = 0.0   # action is now a VELOCITY-command residual (not thrust) -> default action = ZERO = pure route-follow
    if args.init_drone:                                        # drone = RECURRENT (policy_recur)
        dparams, dls, _ = RE.load_safetensors(args.init_drone, device=dev)
        dparams = {k: v.clone().requires_grad_(True) for k, v in dparams.items()}
        dls = dls.clone().requires_grad_(True)
    else:
        dparams, dls = RE.init_recur(EnvDrone.DRONE_SELF_F, EnvDrone.DRONE_TOK_F, args.attn_dim, H,
                                     EnvDrone.DRONE_ACT, device=dev, seed=args.seed, std0=std0, hover_bias=hover_bias,
                                     self_mag=env.self_mag_mask, self_scale=env.self_lot_scale,
                                     tok_mag=env.tok_mag_mask, tok_scale=env.tok_lot_scale, Fe=6)   # LOT + group-assignment enemy_feat dim
    if args.init_enemy:                                        # enemy = feedforward attention
        p, els, _ = AT.load_safetensors(args.init_enemy, device=dev)
        eparams = [(W.clone().requires_grad_(True), b.clone().requires_grad_(True)) for W, b in p]
        els = els.clone().requires_grad_(True)
    else:
        eparams, els = AT.init_attn(EnvDrone.ENEMY_SELF_F, EnvDrone.ENEMY_TOK_F, args.attn_dim, H,
                                    EnvDrone.ENEMY_ACT, device=dev, seed=args.seed + 1, std0=std0)
    env.ctrl_gains = RE.ctrl_gains(dparams); ev_env.ctrl_gains = RE.ctrl_gains(dparams)   # base-controller gains = learnable leaves (train + save via the policy)
    fused_ok = (dev == "cuda")                                 # single-kernel Adam: faster step + lower peak VRAM
    # SHAC drives the drone with analytic gradients (clean, low-variance) -> a MUCH higher LR than PPO's
    # score-function estimate. The enemy always trains via PPO, so it keeps --ppo-lr regardless.
    drone_lr = args.shac_lr                                # SAPO uses the clean analytic-gradient LR (the enemy keeps --ppo-lr)
    dopt = torch.optim.Adam(RE.opt_params(dparams, dls), lr=drone_lr, fused=fused_ok)   # drone (recurrent) optimizer
    eopt = torch.optim.Adam(AT.opt_params(eparams, els), lr=args.ppo_lr, fused=fused_ok)   # enemy (attention) optimizer
    # SAPO temperature: a single trainable log_alpha (auto-tuned toward --sapo-target-entropy each step). Its own
    # tiny optimizer so the dual ascent is decoupled from the actor/critic step. Unused in ppo/shac modes.
    log_alpha = torch.tensor(math.log(args.sapo_alpha0), device=dev, requires_grad=True)
    aopt = torch.optim.Adam([log_alpha], lr=args.sapo_alpha_lr)
    # EMA value TARGET network for SHAC: a slowly-tracking detached copy of the drone params, used ONLY to
    # estimate the terminal value bootstrap + the TD(lambda) critic targets. Persists across sapo_step calls so
    # the target moves smoothly (SHAC tau~0.005). Unused in PPO mode.
    dtarget = {kk: v.detach().clone() for kk, v in dparams.items()}

    pool = [snap_e(eparams, els)]                              # league of past (feedforward) enemies
    pool_rng = random.Random(1234 + args.seed)

    os.makedirs(args.out_dir, exist_ok=True)
    for sub in ("models", "videos", "logs", "config"):          # organised outputs (SETUP loop, not the sim hot path)
        os.makedirs(os.path.join(args.out_dir, sub), exist_ok=True)
    log = open(os.path.join(args.out_dir, "logs", "log.csv"), "w")
    log.write("iter,sec,side,pl,vl,ret,valid,eval_clear,full,exch\n")
    best_clear, best_snap = -1.0, None

    print(f"device={dev} n_envs={args.n_envs} D={D} E={E} O={O} T={T} K_dec={K_dec} "
          f"P={args.ppo_group} mb={args.ppo_minibatch} budget={args.budget}s "
          f"{'FROZEN-ENEMY' if args.freeze_enemy else f'coevo(every={args.enemy_every},pool={args.enemy_pool})'}")
    t0 = time.time()
    for it in range(1, args.iters + 1):
        if not args.no_aa:
            env.set_aa_scale(min(1.0, it / max(1, args.aa_warmup)))  # AA lethality curriculum (skipped when ejected)
        if args.kill_curriculum is not None:                        # anneal kamikaze radius START_MULT -> 1x
            m0, anneal = args.kill_curriculum
            frac = min(1.0, it / max(1.0, anneal))
            mult = m0 + (1.0 - m0) * frac
            env.set_kill_radius(cfg.drone_kill_radius * mult)
        train_enemy = (not args.freeze_enemy) and (it % args.enemy_every == 0)
        if train_enemy:                                         # enemy trains (drone is the frozen recurrent opponent)
            pl, vl, ret, valid = PPO.ppo_step(env, "enemy", dparams, dls, eparams, els, eopt,
                                              args.enemy_group, K_dec, gamma=args.gamma,
                                              minibatch=args.ppo_minibatch, epochs=args.ppo_epochs,
                                              ent=args.ent, mm_dtype=mm_dtype)
            pool.append(snap_e(eparams, els)); pool[:] = pool[-args.enemy_pool:]
            side = "enemy"
        else:                                                  # drone trains vs a sampled league enemy
            opp = pool[pool_rng.randrange(len(pool))] if len(pool) > 1 else (eparams, els)
            # DRONE update = SAPO (2026-SOTA max-entropy SHAC: auto-alpha + soft critic; trains from scratch, one phase).
            pl, vl, ret, valid = PPO.sapo_step(env, dparams, dls, opp[0], opp[1], dopt, log_alpha, aopt,
                                               args.ppo_group, args.shac_horizon, K_dec=K_dec, dtarget=dtarget,
                                               gamma=args.gamma, lam=args.shac_lambda, tau=args.shac_tau,
                                               target_entropy=args.sapo_target_entropy, mm_dtype=mm_dtype)
            side = "drone"
        el = time.time() - t0
        ev = ("", "", "")
        if it % args.eval_every == 0 or el > args.budget:
            clear, full, exch, mk = evaluate(ev_env, dparams, eparams, K_dec, H, mm_dtype)
            ev = (f"{clear:.3f}", f"{full:.3f}", f"{exch:.2f}")
            tag = ""
            if args.keep_best and clear > best_clear:
                best_clear, best_snap = clear, (snap_d(dparams, dls), snap_e(eparams, els)); tag = " *best"
            print(f"[{it:4d}] {el:5.0f}s {side:5s} pl {pl:7.4f} vl {vl:7.4f} ret {ret:7.3f} "
                  f"valid {valid:.2f} | clear {clear*100:5.1f}% full {full*100:4.1f}% exch {exch:.2f}{tag}")
        elif it % 5 == 0:
            print(f"[{it:4d}] {el:5.0f}s {side:5s} pl {pl:7.4f} vl {vl:7.4f} ret {ret:7.3f} valid {valid:.2f}")
        log.write(f"{it},{el:.1f},{side},{pl:.5f},{vl:.5f},{ret:.4f},{valid:.3f},{ev[0]},{ev[1]},{ev[2]}\n")
        if el > args.budget:
            break
    log.close()

    if args.keep_best and best_snap is not None:
        (dparams, dls), (eparams, els) = best_snap[0], best_snap[1]
        print(f"[keep-best] exporting peak-clear checkpoint ({best_clear*100:.1f}%)")
    dmeta = {"Fs": EnvDrone.DRONE_SELF_F, "Ft": EnvDrone.DRONE_TOK_F, "d": args.attn_dim, "H": H, "act": EnvDrone.DRONE_ACT}
    emeta = {"Fs": EnvDrone.ENEMY_SELF_F, "Fm": EnvDrone.ENEMY_TOK_F, "d": args.attn_dim, "H": H, "act": EnvDrone.ENEMY_ACT}
    mdl = os.path.join(args.out_dir, "models")
    RE.save_safetensors(dparams, dls, dmeta, os.path.join(mdl, "drone.safetensors"))
    AT.save_safetensors(eparams, els, emeta, os.path.join(mdl, "enemy.safetensors"))
    cfg.to_json(os.path.join(args.out_dir, "config", "world.json"))   # config/ (JSON, not tensors)
    clear, full, exch, mk = evaluate(ev_env, dparams, eparams, K_dec, H, mm_dtype)
    json.dump({"clear": clear, "full_clear": full, "exchange": exch, "mean_kills": mk},
              open(os.path.join(args.out_dir, "logs", "summary.json"), "w"), indent=2)
    print(f"[final] clear {clear*100:.1f}% full {full*100:.1f}% exchange {exch:.2f} mean_kills {mk:.1f}")
    print(f"wrote {args.out_dir}/: models/*.safetensors  config/world.json  logs/{{log.csv,summary.json}}  videos/*.mp4")

    if args.render:
        try:
            import render_drone
            rc = EnvDrone(S.build_eval(cfg, 4, D, E, O, T, base_seed=999), device=dev, cfg=cfg)
            rc.ctrl_gains = RE.ctrl_gains(dparams)             # base-controller gains for the render env
            render_drone.render(rc, dparams, dls, eparams, els, K_dec, H, args.render, mm_dtype)
            print(f"[render] wrote {args.render}")
        except Exception as e:
            print(f"[render skipped] {type(e).__name__}: {e}")


if __name__ == "__main__":
    main()
