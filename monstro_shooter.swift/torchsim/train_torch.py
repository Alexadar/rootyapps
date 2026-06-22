"""Torch co-evolution trainer — POC. Two models trained adversarially by alternating ES:
  player_net (survive + kill)   vs   shared enemy_net (damage + approach, one net for all monster types).

Trains on the 10 swiper maps (prod.json mapFilenames), batched N = maps × per-map permutations.
Tiny by default so a few iters run on the Mac CPU in < 1 min (guard aborts + defers to the 3090).

  python train_torch.py --perm 4 --pop 8 --ticks 150 --iters 8 --device cpu
  python train_torch.py --perm 32 --pop 64 --ticks 600 --iters 200 --device cuda   # 3090
"""
import argparse, json, os, time
import torch
from tqdm import tqdm
import data, schedule
import policy_torch as P
import es_torch as ES
from env_torch import EnvTorch

H = 32                                   # hidden width (tiny for POC)
PLAYER_SIZES = [EnvTorch.player_obs, H, H, EnvTorch.player_act]
ENEMY_SIZES = [EnvTorch.enemy_obs, H, H, EnvTorch.enemy_act]


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


def swiper_maps(client):
    prod = json.load(open(os.path.join(client, "Resources", "prod.json")))
    names = prod["mapFilenames"]
    return [os.path.join(client, "Resources", "MapConfigs", n + ".json") for n in names]


def build_env(args):
    gd = data.GameData(args.client)
    paths = [args.map] if args.map else swiper_maps(args.client)
    levels = [data.sim_level(data.load_map(p)) for p in paths]
    n_envs = len(levels) * args.perm
    sched = schedule.build_multi(levels, gd.monsters, base_seed=1, n_envs=n_envs, cap=args.cap)
    weapon = gd.weapons.get(1) or next(iter(gd.weapons.values()))
    exo = gd.exoskeletons.get(1) or next(iter(gd.exoskeletons.values()))
    env = EnvTorch(sched, weapon, exo, device=args.device, bullets=args.bullets)
    return env, len(levels), n_envs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--client", default=data.DEFAULT_CLIENT)
    ap.add_argument("--map", default="")                 # single map override (else 10 swiper maps)
    ap.add_argument("--perm", type=int, default=4)       # envs per map  -> N = maps * perm
    ap.add_argument("--pop", type=int, default=8)        # ES population (rollout uses 2*pop)
    ap.add_argument("--ticks", type=int, default=150)
    ap.add_argument("--iters", type=int, default=8)      # alternating player/enemy
    ap.add_argument("--cap", type=int, default=64)       # monster slots
    ap.add_argument("--bullets", type=int, default=32)
    ap.add_argument("--sigma", type=float, default=0.1)
    ap.add_argument("--lr", type=float, default=0.05)
    ap.add_argument("--device", default="auto")          # auto: cuda -> mps -> cpu
    ap.add_argument("--cpu-budget", type=float, default=60.0)   # abort guard (seconds)
    ap.add_argument("--player-out", default="../MonstroSim/models/player.json")
    ap.add_argument("--enemy-out", default="../MonstroSim/models/monster.json")
    args = ap.parse_args()

    dev = pick_device(args.device)
    args.device = dev
    env, n_maps, n_envs = build_env(args)
    Ppop = 2 * args.pop
    print(f"Torch co-evolution: {n_maps} swiper maps x {args.perm} = N={n_envs} envs, M={env.M}, "
          f"B={env.B}, ticks={args.ticks}, pop={args.pop}, iters={args.iters}, dev={dev}")

    player = P.init_mlp(PLAYER_SIZES, device=dev, seed=7)
    enemy = P.init_mlp(ENEMY_SIZES, device=dev, seed=11)
    gen = torch.Generator().manual_seed(42)              # CPU generator (noise moved to device in es)

    pf = lambda params: (lambda obs: P.apply_mlp(params, obs))
    ef = lambda params: (lambda obs: P.apply_enemy(params, obs))

    hist = {"player": [], "enemy": []}
    last = {"player": float("nan"), "enemy": float("nan")}
    t0 = time.time()
    pbar = tqdm(range(args.iters), desc="co-evo", unit="it", dynamic_ncols=True)
    for it in pbar:
        train_player = (it % 2 == 0)
        if train_player:
            def fitness(stacked):
                out = env.rollout(Ppop, args.ticks, pf(stacked), ef(enemy))
                return out["reward_player"].mean(1)
            player, best, mean = ES.es_step(player, fitness, args.pop, gen, dev, args.sigma, args.lr)
            hist["player"].append(mean); last["player"] = mean
        else:
            def fitness(stacked):
                out = env.rollout(Ppop, args.ticks, pf(player), ef(stacked))
                return out["reward_enemy"].mean(1)
            enemy, best, mean = ES.es_step(enemy, fitness, args.pop, gen, dev, args.sigma, args.lr)
            hist["enemy"].append(mean); last["enemy"] = mean

        pbar.set_postfix(phase="player" if train_player else "enemy",
                         player=f"{last['player']:.2f}", enemy=f"{last['enemy']:.3f}", best=f"{best:.2f}")

        if dev == "cpu" and (time.time() - t0) > args.cpu_budget:
            pbar.close()
            print(f">>> exceeded {args.cpu_budget:.0f}s on CPU — stopping. Run on the 3090: --device cuda "
                  f"(scale --perm/--pop/--ticks up).", flush=True)
            break
    else:
        pbar.close()

    def trend(xs):
        return f"{xs[0]:.3f} -> {xs[-1]:.3f}  (+{xs[-1]-xs[0]:.3f})" if len(xs) >= 2 else (f"{xs[0]:.3f}" if xs else "n/a")
    print(f"Player fitness: {trend(hist['player'])}")
    print(f"Enemy  fitness: {trend(hist['enemy'])}")

    os.makedirs(os.path.dirname(os.path.abspath(args.player_out)), exist_ok=True)
    P.to_json(player, PLAYER_SIZES, args.player_out)
    P.to_json(enemy, ENEMY_SIZES, args.enemy_out)
    print(f"saved -> {args.player_out}  +  {args.enemy_out}")


if __name__ == "__main__":
    main()
