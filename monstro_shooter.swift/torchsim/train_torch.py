"""Torch co-evolution trainer. Two models trained adversarially by alternating ES:
  player_net (survive + kill)   vs   shared enemy_net (damage + approach, one net for all monster types).

Map source: --dataset <dir> (train/ + eval/ folds), else --map, else the 10 swiper maps. Batched
N = maps × --perm. Device auto-detected (cuda -> mps -> cpu). --budget caps wall-time (stops + saves).

  python train_torch.py --dataset datasets/tiny --perm 8 --pop 12 --ticks 200 --cap 16 --eval
  python train_torch.py --dataset datasets/tiny --pop 64 --ticks 400 --budget 3600   # 3090
"""
import argparse, glob, json, os, time
import torch
from tqdm import tqdm
import data, schedule
import policy_torch as P
import es_torch as ES
from env_torch import EnvTorch

H = 32                                   # hidden width (tiny for POC)
PLAYER_SIZES = [EnvTorch.player_obs, H, H, EnvTorch.player_act]
ENEMY_SIZES = [EnvTorch.enemy_obs, H, H, EnvTorch.enemy_act]
# Held-out map the models never train on (training uses the 10 swiper maps from prod.json).
EVAL_MAP_DEFAULT = os.path.join(os.path.dirname(__file__), "eval_maps", "eval_unseen.json")


def pick_device(pref="auto"):
    """auto: cuda (3090) -> mps (Apple GPU) -> cpu. Explicit value passes through."""
    if pref and pref != "auto":
        return pref
    if torch.cuda.is_available():
        return "cuda"
    mps = getattr(torch.backends, "mps", None)
    if mps is not None and mps.is_available():
        return "mps"
    return "cpu"


def _perf_setup(dev):
    """Standard torch perf flags. On cuda: TF32 fast-path for the (tiny) MLP matmuls — only affects the
    net, parity-safe. cudnn.benchmark is a no-op for us (no convs). The sim stays fp32; bf16/fp16 are NOT
    used (d² overflows fp16 at world scale, bf16 mantissa too coarse for collision thresholds)."""
    torch.backends.cudnn.benchmark = True
    if dev == "cuda":
        torch.backends.cuda.matmul.allow_tf32 = True
        torch.backends.cudnn.allow_tf32 = True
        torch.set_float32_matmul_precision("high")


def tick_at(it, args):
    """Tick curriculum: ramp rollout length from --tick-start to --ticks over --tick-warmup iters. Short
    early episodes cost ~ticks and are enough to learn basic survive/aim; lengthen as policies mature.
    Off when --tick-start<=0. Eval always uses full ticks. (ticks is the loop count, not a tensor shape,
    so varying it does NOT trigger torch.compile recompiles.)"""
    s = args.tick_start
    if s <= 0 or it >= args.tick_warmup:
        return args.ticks
    return int(s + (args.ticks - s) * (it / max(args.tick_warmup, 1)))


def swiper_maps(client):
    prod = json.load(open(os.path.join(client, "Resources", "prod.json")))
    names = prod["mapFilenames"]
    return [os.path.join(client, "Resources", "MapConfigs", n + ".json") for n in names]


def train_paths(args):
    """--dataset <dir> -> <dir>/train/*.json ; else --map ; else the 10 swiper maps."""
    if args.dataset:
        return sorted(glob.glob(os.path.join(args.dataset, "train", "*.json")))
    return [args.map] if args.map else swiper_maps(args.client)


def eval_paths(args):
    """--eval-map override ; else --dataset/eval/*.json ; else the single held-out unseen map."""
    if args.eval_map:
        return [args.eval_map]
    if args.dataset:
        return sorted(glob.glob(os.path.join(args.dataset, "eval", "*.json")))
    return [EVAL_MAP_DEFAULT]


def build_env(args):
    gd = data.GameData(args.client)
    paths = train_paths(args)
    levels = [data.sim_level(data.load_map(p)) for p in paths]
    n_envs = len(levels) * args.perm
    sched = schedule.build_multi(levels, gd.monsters, base_seed=1, n_envs=n_envs, cap=args.cap)
    weapon = gd.weapons.get(1) or next(iter(gd.weapons.values()))
    exo = gd.exoskeletons.get(1) or next(iter(gd.exoskeletons.values()))
    env = EnvTorch(sched, weapon, exo, device=args.device, bullets=args.bullets)
    return env, len(levels), n_envs


def _play_batch(env, ticks_max, real_tot, env_ticks, pf, ef):
    """Play ALL eval games at once, vectorized over the N-env batch (exactly like training rolls N
    envs) — NO per-game loop. Each env runs to its own timeout / cleared / death; metrics are frozen
    per-env at the first crossing via masks, so this is byte-identical to playing each game alone and
    breaking. The only loop is the unavoidable per-tick time loop. Returns (survived[N], kills[N], dmg[N])."""
    s = env.reset(1)
    N = s["player_hp"].shape[1]
    dev = s["player_hp"].device
    hp_max = float(env.cfg.player_max_hp)
    done = torch.zeros(N, device=dev)
    fk = torch.zeros(N, device=dev)
    fhp = torch.full((N,), hp_max, device=dev)
    with torch.no_grad():
        for tk in range(1, ticks_max + 1):
            s, _, _ = env.step(s, tk, pf, ef)
            hp = s["player_hp"][0]; k = s["kills"][0]                       # [N]
            cross = ((hp <= 0) | (k >= real_tot) | (tk >= env_ticks)).float()
            newly = (1.0 - done) * cross
            fk = torch.where(newly > 0.5, k, fk)
            fhp = torch.where(newly > 0.5, hp.clamp(min=0.0), fhp)
            done = torch.maximum(done, cross)
            if float(done.min()) > 0.5:
                break
    return fhp > 0, fk, hp_max - fhp


def run_eval(gd, weapon, exo, args, player, enemy, dev, seeds):
    """Play every held-out (map x seed) game in ONE batched rollout (no map/seed loop).
    Returns (rows, maps); row = (name, survived, kills, M, dmg)."""
    pf = lambda obs: P.apply_mlp(player, obs)
    ef = lambda obs: P.apply_enemy(enemy, obs)
    maps = eval_paths(args)
    levels = [data.sim_level(data.load_map(m)) for m in maps]
    names = [os.path.basename(m) for m in maps]
    sched, real_tot, assign = schedule.build_eval(levels, gd.monsters, seeds, cap=1024)
    env = EnvTorch(sched, weapon, exo, device=dev, bullets=args.bullets)
    per_ticks = [args.eval_ticks or int(lv["duration"] * 30) for lv in levels]
    env_ticks = torch.tensor([per_ticks[assign[e]] for e in range(len(assign))], device=dev, dtype=torch.float32)
    rt = torch.tensor(real_tot, device=dev)
    surv, fk, dmg = _play_batch(env, int(env_ticks.max()), rt, env_ticks, pf, ef)
    rows = [(names[assign[e]], bool(surv[e]), int(fk[e]), int(real_tot[e]), float(dmg[e]))
            for e in range(len(assign))]
    return rows, maps


def eval_line(rows):
    n = len(rows)
    surv = sum(r[1] for r in rows)
    mk = sum(r[2] for r in rows) / n
    mclear = sum(r[2] / max(r[3], 1) for r in rows) / n
    mdmg = sum(r[4] for r in rows) / n
    return f"survival {surv}/{n} ({100*surv/n:.0f}%)  kills {mk:.1f}  clear {100*mclear:.0f}%  dmg {mdmg:.0f}"


def eval_report(rows, maps, seeds, dev):
    print(f"\nEval ({len(maps)} held-out maps x {seeds} seeds = {len(rows)} games, dev={dev}):")
    print(f"  {eval_line(rows)}")
    for mpath in maps:
        name = os.path.basename(mpath)
        mr = [r for r in rows if r[0] == name]
        print(f"    {name:14s} survived {sum(r[1] for r in mr)}/{len(mr)}  "
              f"kills {sum(r[2] for r in mr)/len(mr):.1f}/{mr[0][3]}  dmg {sum(r[4] for r in mr)/len(mr):.0f}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--client", default=data.DEFAULT_CLIENT)
    ap.add_argument("--dataset", default="")             # <dir> with train/ + eval/ folds (overrides --map)
    ap.add_argument("--map", default="")                 # single map override (else 10 swiper maps)
    ap.add_argument("--perm", type=int, default=4)       # envs per map  -> N = maps * perm
    ap.add_argument("--pop", type=int, default=8)        # ES population (rollout uses 2*pop)
    ap.add_argument("--ticks", type=int, default=150)
    ap.add_argument("--iters", type=int, default=8)      # alternating player/enemy
    ap.add_argument("--tick-start", type=int, default=0)   # tick curriculum start len (0=off -> full ticks)
    ap.add_argument("--tick-warmup", type=int, default=40) # iters to ramp tick-start -> ticks
    ap.add_argument("--cap", type=int, default=64)       # monster slots
    ap.add_argument("--bullets", type=int, default=32)
    ap.add_argument("--sigma", type=float, default=0.1)
    ap.add_argument("--lr", type=float, default=0.05)
    ap.add_argument("--algo", default="es", choices=["es", "grpo", "ppo"])  # policy-gradient player (+ ES enemy)
    ap.add_argument("--grpo-lr", type=float, default=3e-3)
    ap.add_argument("--grpo-group", type=int, default=64)  # P = group size (action samples per env)
    ap.add_argument("--grpo-gamma", type=float, default=0.99)
    ap.add_argument("--grpo-std", type=float, default=0.6)  # initial action std
    ap.add_argument("--grpo-ent", type=float, default=0.0)  # entropy bonus coef
    ap.add_argument("--ppo-lr", type=float, default=3e-4)
    ap.add_argument("--ppo-epochs", type=int, default=4)
    ap.add_argument("--ppo-clip", type=float, default=0.2)
    ap.add_argument("--ppo-gae", type=float, default=0.95)
    ap.add_argument("--ppo-gamma", type=float, default=0.99)
    ap.add_argument("--ppo-minibatch", type=int, default=16384)
    ap.add_argument("--ppo-vcoef", type=float, default=0.5)
    ap.add_argument("--ppo-ent", type=float, default=0.0)
    ap.add_argument("--ppo-group", type=int, default=64)
    ap.add_argument("--ppo-std", type=float, default=0.6)
    ap.add_argument("--rw-kill", type=float, default=1.0)     # reward shaping (training-only, parity-safe)
    ap.add_argument("--rw-survive", type=float, default=0.01)
    ap.add_argument("--device", default="auto")          # auto: cuda -> mps -> cpu (explicit value respected)
    ap.add_argument("--engine", default="torch", choices=["torch", "jax"])  # jax: lax.scan rollout (~1.23x, T3)
    ap.add_argument("--compile", action="store_true")    # torch.compile the env step (CUDA-graphs on cuda)
    ap.add_argument("--compile-mode", default="default")  # "default"=Inductor fusion (robust). "reduce-overhead"
    #                                                       adds CUDA-graphs but breaks on our recurrent rollout.
    ap.add_argument("--budget", type=float, default=0.0)   # wall-time cap in seconds (0=off); stops + saves
    ap.add_argument("--eval", action="store_true")       # after training, play one UNSEEN map headless
    ap.add_argument("--eval-map", default="")            # default: dataset/eval/*.json or eval_unseen.json
    ap.add_argument("--eval-ticks", type=int, default=0)  # 0 -> landingDuration*30 (full map)
    ap.add_argument("--eval-seeds", type=int, default=3)  # seeds per eval map (held-out distribution)
    ap.add_argument("--eval-every", type=int, default=0)  # run a quick 1-seed eval every K iters (0=off)
    ap.add_argument("--render", default="")              # render a 3x3 eval grid video to this path at end
    ap.add_argument("--player-out", default="../MonstroSim/models/player.json")
    ap.add_argument("--enemy-out", default="../MonstroSim/models/monster.json")
    args = ap.parse_args()

    dev = pick_device(args.device)
    args.device = dev
    _perf_setup(dev)
    env, n_maps, n_envs = build_env(args)
    env.rw_kill, env.rw_survive = args.rw_kill, args.rw_survive   # reward shaping (set BEFORE compile bakes it)
    Ppop = 2 * args.pop
    jr = None
    if args.engine == "jax":
        # Hybrid: torch ES/eval/save, JAX lax.scan rollout for fitness (the only hot path). ~1.23x over
        # torch-fusion on cuda (T3); env_jax is parity-proven so trained models still run in the Swift game.
        assert args.tick_start <= 0, "--engine jax bakes a fixed tick count; tick curriculum is unsupported"
        import jax_engine
        jr = jax_engine.JaxRollout(env, args.ticks, Ppop, dev)
        print(f"  engine: JAX (lax.scan rollout, P={Ppop})")
    elif args.compile:
        # Inductor FUSION is the win (compile-clean _core traces once; the 5.3x on mps was fusion alone,
        # no CUDA-graphs). 'default' is robust everywhere. 'reduce-overhead' adds CUDA-graphs but its
        # static-buffer reuse clobbers our carried rollout state -> off by default. First iter = warmup.
        mode = None if (args.compile_mode == "default" or dev != "cuda") else args.compile_mode
        env._core = torch.compile(env._core, mode=mode)
        print(f"  torch.compile: ON (mode={mode or 'default'})")
    gd_eval = data.GameData(args.client)                  # loaded once; reused by periodic + final eval
    weapon_eval = gd_eval.weapons.get(1) or next(iter(gd_eval.weapons.values()))
    exo_eval = gd_eval.exoskeletons.get(1) or next(iter(gd_eval.exoskeletons.values()))
    src = os.path.basename(args.dataset.rstrip("/")) if args.dataset else ("map" if args.map else "swiper")
    print(f"Torch co-evolution [{src}]: {n_maps} maps x {args.perm} = N={n_envs} envs, M={env.M}, "
          f"B={env.B}, ticks={args.ticks}, pop={args.pop}, iters={args.iters}, dev={dev}")

    player = P.init_mlp(PLAYER_SIZES, device=dev, seed=7)
    enemy = P.init_mlp(ENEMY_SIZES, device=dev, seed=11)
    gen = torch.Generator().manual_seed(42)              # CPU generator (noise moved to device in es)

    pf = lambda params: (lambda obs: P.apply_mlp(params, obs))
    ef = lambda params: (lambda obs: P.apply_enemy(params, obs))

    grpo = ppo = None
    if args.algo == "grpo":
        import grpo_torch as G                            # policy-gradient player (the deployed agent)
        gparams, glog = G.init_player(PLAYER_SIZES, dev, seed=7, std0=args.grpo_std)
        gopt = torch.optim.Adam(G.opt_params(gparams, glog), lr=args.grpo_lr)
        player = G.mean_params(gparams)                   # eval/save/opponent use the deterministic mean
        grpo = (G, gparams, glog, gopt)
        print(f"  algo: GRPO player (group={args.grpo_group} lr={args.grpo_lr} std={args.grpo_std}) + ES enemy")
    elif args.algo == "ppo":
        import grpo_torch as G, ppo_torch as PPO          # PPO: clipped surrogate + critic + GAE
        gparams, glog = G.init_player(PLAYER_SIZES, dev, seed=7, std0=args.ppo_std)
        vparams = PPO.init_value(dev, seed=23)
        popt = torch.optim.Adam(G.opt_params(gparams, glog) + PPO.value_params_flat(vparams), lr=args.ppo_lr)
        player = G.mean_params(gparams)
        ppo = (PPO, G, gparams, glog, vparams, popt)
        print(f"  algo: PPO player (group={args.ppo_group} lr={args.ppo_lr} epochs={args.ppo_epochs} "
              f"clip={args.ppo_clip}) + ES enemy   rw_kill={args.rw_kill} rw_survive={args.rw_survive}")

    best = 0.0
    hist = {"player": [], "enemy": []}
    last = {"player": float("nan"), "enemy": float("nan")}
    t0 = time.time()
    use_budget = args.budget > 0
    # When budgeted, the bar tracks WALL-TIME (fills to --budget seconds) so the ETA is the real
    # stop time — not tqdm projecting all --iters (which the budget halts long before).
    pbar = tqdm(total=(round(args.budget) if use_budget else args.iters), desc="co-evo",
                unit=("s" if use_budget else "it"), dynamic_ncols=True)
    it = 0
    while it < args.iters:
        train_player = (it % 2 == 0)
        cur_ticks = tick_at(it, args)                          # curriculum: short rollouts early -> full
        if train_player:
            if ppo is not None:                                 # PPO player step vs the frozen ES enemy
                PPO, G, gparams, glog, vparams, popt = ppo
                _pl, _vl, ret = PPO.ppo_step(env, cur_ticks, gparams, glog, vparams, popt, enemy, args.ppo_group,
                                             gamma=args.ppo_gamma, lam=args.ppo_gae, clip=args.ppo_clip,
                                             epochs=args.ppo_epochs, minibatch=args.ppo_minibatch,
                                             vcoef=args.ppo_vcoef, ent=args.ppo_ent)
                player = G.mean_params(gparams)
                best = ret; hist["player"].append(ret); last["player"] = ret
            elif grpo is not None:                              # GRPO player step vs the frozen ES enemy
                G, gparams, glog, gopt = grpo
                _loss, ret = G.grpo_player_step(env, cur_ticks, gparams, glog, gopt, enemy,
                                                args.grpo_group, gamma=args.grpo_gamma, ent_coef=args.grpo_ent)
                player = G.mean_params(gparams)                 # refresh the deterministic mean for eval/opponent
                best = ret; hist["player"].append(ret); last["player"] = ret
            else:
                def fitness(stacked):
                    if jr is not None:
                        return jr.reward_player(stacked, enemy)
                    out = env.rollout(Ppop, cur_ticks, pf(stacked), ef(enemy))
                    return out["reward_player"].mean(1)
                player, best, mean = ES.es_step(player, fitness, args.pop, gen, dev, args.sigma, args.lr)
                hist["player"].append(mean); last["player"] = mean
        else:
            def fitness(stacked):
                if jr is not None:
                    return jr.reward_enemy(player, stacked)
                out = env.rollout(Ppop, cur_ticks, pf(player), ef(stacked))
                return out["reward_enemy"].mean(1)
            enemy, best, mean = ES.es_step(enemy, fitness, args.pop, gen, dev, args.sigma, args.lr)
            hist["enemy"].append(mean); last["enemy"] = mean

        elapsed = time.time() - t0
        if use_budget:
            pbar.n = min(round(elapsed), round(args.budget)); pbar.refresh()
        else:
            pbar.update(1)
        pbar.set_postfix(it=it, phase="player" if train_player else "enemy",
                         player=f"{last['player']:.2f}", enemy=f"{last['enemy']:.3f}", best=f"{best:.2f}")
        if args.eval_every and it > 0 and it % args.eval_every == 0:
            rows, _ = run_eval(gd_eval, weapon_eval, exo_eval, args, player, enemy, dev, seeds=1)
            tqdm.write(f"  [eval @ it{it:4d}]  {eval_line(rows)}")
        it += 1
        if use_budget and elapsed > args.budget:
            print(f"\n>>> reached {args.budget:.0f}s budget at iter {it} — stopping (models saved below).", flush=True)
            break
    pbar.close()

    def trend(xs):
        return f"{xs[0]:.3f} -> {xs[-1]:.3f}  (+{xs[-1]-xs[0]:.3f})" if len(xs) >= 2 else (f"{xs[0]:.3f}" if xs else "n/a")
    print(f"Player fitness: {trend(hist['player'])}")
    print(f"Enemy  fitness: {trend(hist['enemy'])}")

    os.makedirs(os.path.dirname(os.path.abspath(args.player_out)), exist_ok=True)
    P.to_json(player, PLAYER_SIZES, args.player_out)
    P.to_json(enemy, ENEMY_SIZES, args.enemy_out)
    print(f"saved -> {args.player_out}  +  {args.enemy_out}")

    if args.eval:
        rows, maps = run_eval(gd_eval, weapon_eval, exo_eval, args, player, enemy, dev, max(1, args.eval_seeds))
        eval_report(rows, maps, args.eval_seeds, dev)

    if args.render:
        import render_eval
        render_eval.render_grid(gd_eval, weapon_eval, exo_eval, args, player, enemy, dev, args.render)


if __name__ == "__main__":
    main()
