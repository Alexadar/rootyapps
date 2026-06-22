"""Braxify CLI. Dev (here): JAX-CPU, tiny N/ticks/iters. Scale: run on the 3090 with jax[cuda12].
  python train.py train  --map <map.json> --envs 256 --ticks 400 --iters 40 --pop 20 --out player.json
  python train.py train  --maps-dir ../monstro_client/Resources/MapConfigs --envs 512 --pop 64   (generalist)
  python train.py train  --maps a.json,b.json,c.json --envs 512 --pop 64                          (subset)
  python train.py eval   --map <map.json> --net player.json
  python train.py parity --net ../MonstroSim/models/player.json   (forward == Swift/MLX)
"""
import argparse, glob, json, os, time
import numpy as np
import jax, jax.numpy as jnp
import data, schedule, policy, es
from env import Env


def _map_paths(args):
    """Resolve --map / --maps / --maps-dir into an ordered list of map file paths."""
    if args.maps_dir:
        paths = sorted(p for p in glob.glob(os.path.join(args.maps_dir, "*.json"))
                       if "all_maps" not in os.path.basename(p))
        if not paths:
            raise SystemExit(f"no map_*.json under {args.maps_dir}")
        return paths
    if args.maps:
        return [p.strip() for p in args.maps.split(",") if p.strip()]
    if args.map:
        return [args.map]
    raise SystemExit("pass --map, --maps a,b,c, or --maps-dir <dir>")


def build(args, base_seed):
    gd = data.GameData(args.client)
    paths = _map_paths(args)
    levels = [data.sim_level(data.load_map(p)) for p in paths]
    weapon = gd.weapons.get(1) or next(iter(gd.weapons.values()))
    exo = gd.exoskeletons.get(1) or next(iter(gd.exoskeletons.values()))
    if len(levels) == 1:
        sched = schedule.build(levels[0], gd.monsters, base_seed=base_seed, n_envs=args.envs, cap=args.cap)
        return levels[0], Env(levels[0], sched, weapon, exo)
    sched = schedule.build_multi(levels, gd.monsters, base_seed=base_seed, n_envs=args.envs, cap=args.cap)
    # synthetic level wrapper for Env (duration/name only); M comes from the combined schedule
    meta = {"name": f"multi({len(levels)} maps)",
            "duration": max(lv["duration"] for lv in levels),
            "expected_total": sched["M"]}
    per = np.bincount(sched["assign"], minlength=len(levels))
    print("Maps:", ", ".join(f"{os.path.basename(p)}×{n}" for p, n in zip(paths, per)))
    return meta, Env(meta, sched, weapon, exo)


def save_params(params, sizes, path):
    d = {"sizes": sizes, "w": [np.asarray(W).reshape(-1).tolist() for W, _ in params],
         "b": [np.asarray(b).tolist() for _, b in params]}
    json.dump(d, open(path, "w"))


SIZES = [Env.obs_size, 64, 64, Env.act_size]


def cmd_train(args):
    level, e = build(args, base_seed=1)
    params0 = policy.init_mlp(SIZES, jax.random.PRNGKey(7))
    fitness = lambda p: jnp.mean(e.rollout(policy.apply_mlp, p, args.ticks)["reward"])
    print(f"JAX ES on {level['name']}: N={e.N} M={e.M} ticks={args.ticks} pop={args.pop} iters={args.iters} dev={jax.devices()[0].platform}")
    t0 = time.time()
    trained = es.train(fitness, params0, jax.random.PRNGKey(42), iters=args.iters, pop=args.pop, sigma=0.1, lr=0.05,
                       on_iter=lambda it, best, ctr: print(f"  iter {it:3d}  center {ctr:.2f}  popBest {best:.2f}"))
    out = jax.jit(lambda p: e.rollout(policy.apply_mlp, p, args.ticks))(trained)
    print(f"final: reward {float(jnp.mean(out['reward'])):.2f}  kills {float(jnp.mean(out['kills'])):.2f}  ({time.time()-t0:.1f}s)")
    if args.out:
        save_params(trained, SIZES, args.out); print(f"saved -> {args.out}")


def cmd_eval(args):
    level, e = build(args, base_seed=9000)   # held-out seeds
    roll = jax.jit(lambda p: e.rollout(policy.apply_mlp, p, args.ticks))
    rnd = policy.init_mlp(SIZES, jax.random.PRNGKey(999))
    rr = roll(rnd)
    print(f"Held-out ({e.N} seeds x {args.ticks} ticks):")
    print(f"  random   reward {float(jnp.mean(rr['reward'])):.2f}  kills {float(jnp.mean(rr['kills'])):.2f}")
    if args.net:
        p, _ = policy.load_player_json(args.net)
        tr = roll(p)
        print(f"  trained  reward {float(jnp.mean(tr['reward'])):.2f}  kills {float(jnp.mean(tr['kills'])):.2f}")


def cmd_parity(args):
    params, sizes = policy.load_player_json(args.net)
    obs = jnp.asarray([[0.6, 0.2, 0.5, -0.5, 0.3, 0.4]], jnp.float32)
    out = np.asarray(policy.apply_mlp(params, obs))[0]
    ref = np.array([0.3278, -0.5857, -0.4518, 0.2701])     # Swift/MLX (monstrosim aneinfer)
    print("  JAX        :", " ".join(f"{v: .4f}" for v in out))
    print("  Swift/MLX  :", " ".join(f"{v: .4f}" for v in ref))
    print(f"  max|Δ| = {float(np.max(np.abs(out - ref))):.5f}  {'✓ parity' if np.max(np.abs(out-ref))<1e-3 else '✗'}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("train", "eval", "parity"):
        s = sub.add_parser(name)
        s.add_argument("--client", default=data.DEFAULT_CLIENT)
        s.add_argument("--map", default="")
        s.add_argument("--maps", default="", help="comma-separated map paths (domain randomization)")
        s.add_argument("--maps-dir", default="", help="dir of map_*.json — train across all of them")
        s.add_argument("--net", default="")
        s.add_argument("--out", default="")
        s.add_argument("--envs", type=int, default=16)
        s.add_argument("--ticks", type=int, default=120)
        s.add_argument("--iters", type=int, default=4)
        s.add_argument("--pop", type=int, default=8)
        s.add_argument("--cap", type=int, default=128)
    a = ap.parse_args()
    {"train": cmd_train, "eval": cmd_eval, "parity": cmd_parity}[a.cmd](a)
