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
    ap.add_argument("--device", default="auto")          # auto: cuda -> mps -> cpu (explicit value respected)
    ap.add_argument("--compile", action="store_true")    # torch.compile the env step (CUDA-graphs on cuda)
    ap.add_argument("--compile-mode", default="reduce-overhead")  # cuda; use "default" if CUDA-graphs error
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
    if args.compile:
        # CUDA-graph trees on cuda (the big win); Inductor fusion on mps/cpu. _core is compile-clean
        # (per-tick tensors passed as args), so it traces ONCE. First iter pays the compile warmup.
        # If CUDA-graphs misbehave on a given torch build, run with `--compile-mode default` (fusion only).
        mode = args.compile_mode if dev == "cuda" else None
        env._core = torch.compile(env._core, mode=mode)
        print(f"  torch.compile: ON (mode={mode or 'default'})")
    gd_eval = data.GameData(args.client)                  # loaded once; reused by periodic + final eval
    weapon_eval = gd_eval.weapons.get(1) or next(iter(gd_eval.weapons.values()))
    exo_eval = gd_eval.exoskeletons.get(1) or next(iter(gd_eval.exoskeletons.values()))
    Ppop = 2 * args.pop
    src = os.path.basename(args.dataset.rstrip("/")) if args.dataset else ("map" if args.map else "swiper")
    print(f"Torch co-evolution [{src}]: {n_maps} maps x {args.perm} = N={n_envs} envs, M={env.M}, "
          f"B={env.B}, ticks={args.ticks}, pop={args.pop}, iters={args.iters}, dev={dev}")

    player = P.init_mlp(PLAYER_SIZES, device=dev, seed=7)
    enemy = P.init_mlp(ENEMY_SIZES, device=dev, seed=11)
    gen = torch.Generator().manual_seed(42)              # CPU generator (noise moved to device in es)

    pf = lambda params: (lambda obs: P.apply_mlp(params, obs))
    ef = lambda params: (lambda obs: P.apply_enemy(params, obs))

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
            def fitness(stacked):
                out = env.rollout(Ppop, cur_ticks, pf(stacked), ef(enemy))
                return out["reward_player"].mean(1)
            player, best, mean = ES.es_step(player, fitness, args.pop, gen, dev, args.sigma, args.lr)
            hist["player"].append(mean); last["player"] = mean
        else:
            def fitness(stacked):
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
