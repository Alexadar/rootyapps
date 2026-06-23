"""CUDA rollout benchmark: torch-eager vs torch.compile fusion (mode=None) at the cuda TRAINING config.

Mirrors what train.sh runs on the 3090: P=2*pop=256, N=maps*perm=128, M=16, B=32, ticks=600. The player
phase is timed (population over the player net, single frozen enemy) — that's exactly fitness() in
train_torch.main. All timings sync + warm up (compile + cudnn) and report the median of >=N runs.

  python bench_cuda.py                 # default cuda config
  python bench_cuda.py --pop 256 --ticks 600
"""
import argparse, sys, time, statistics as st; sys.path.insert(0, ".")
import torch
import train_torch as T
import policy_torch as P


def build_env(pop, perm, ticks, cap, bullets, dev):
    a = type("A", (), {})()
    a.client = T.data.DEFAULT_CLIENT; a.dataset = "datasets/tiny"; a.map = ""
    a.perm = perm; a.cap = cap; a.bullets = bullets; a.device = dev
    env, n_maps, n_envs = T.build_env(a)
    return env, n_maps, n_envs


def bench(fn, n, warmup):
    for _ in range(warmup):
        fn(); torch.cuda.synchronize()
    xs = []
    for _ in range(n):
        torch.cuda.synchronize(); t0 = time.perf_counter()
        fn(); torch.cuda.synchronize()
        xs.append(time.perf_counter() - t0)
    return st.median(xs), min(xs), max(xs)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pop", type=int, default=128)      # rollout uses P = 2*pop
    ap.add_argument("--perm", type=int, default=32)      # N = maps * perm  (tiny => 4 maps)
    ap.add_argument("--ticks", type=int, default=600)
    ap.add_argument("--cap", type=int, default=16)
    ap.add_argument("--bullets", type=int, default=32)
    ap.add_argument("--runs", type=int, default=7)
    ap.add_argument("--warmup", type=int, default=2)
    args = ap.parse_args()

    assert torch.cuda.is_available(), "bench_cuda needs a CUDA GPU"
    dev = "cuda"
    T._perf_setup(dev)                                   # TF32 fast-path, same as training
    Pp = 2 * args.pop

    env, n_maps, n_envs = build_env(args.pop, args.perm, args.ticks, args.cap, args.bullets, dev)
    # Player-training phase: population over the player net, single frozen enemy (== fitness()).
    pl = P.stack_population([P.init_mlp(T.PLAYER_SIZES, device=dev, seed=i) for i in range(Pp)])
    en = P.init_mlp(T.ENEMY_SIZES, device=dev, seed=11)
    pf = lambda o: P.apply_mlp(pl, o)
    ef = lambda o: P.apply_enemy(en, o)

    print(f"config: P={Pp} N={n_envs} ({n_maps} maps x {args.perm}) M={env.M} B={env.B} "
          f"ticks={args.ticks} dev={dev}")
    roll = lambda: env.rollout(Pp, args.ticks, pf, ef)

    # ---- eager ----
    torch.cuda.reset_peak_memory_stats()
    med_e, lo_e, hi_e = bench(roll, args.runs, args.warmup)
    vram_e = torch.cuda.max_memory_reserved() / 1e9

    # ---- fusion (torch.compile mode=None == Inductor fusion, the training default on cuda) ----
    env._core = torch.compile(env._core, mode=None)
    torch.cuda.reset_peak_memory_stats()
    med_f, lo_f, hi_f = bench(roll, args.runs, max(args.warmup, 3))   # first call compiles
    vram_f = torch.cuda.max_memory_reserved() / 1e9

    print(f"\nROLLOUT median of {args.runs} (sync'd):")
    print(f"  eager : {med_e*1000:8.1f} ms   [{lo_e*1000:.1f}-{hi_e*1000:.1f}]   VRAM {vram_e:.2f} GiB")
    print(f"  fusion: {med_f*1000:8.1f} ms   [{lo_f*1000:.1f}-{hi_f*1000:.1f}]   VRAM {vram_f:.2f} GiB")
    print(f"\n  fusion speedup: {med_e/med_f:.2f}x")


if __name__ == "__main__":
    main()
