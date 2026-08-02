"""T5: profile the rollout to (1) confirm compute-bound and (2) find the hotspot ops.

Profiles an EAGER rollout (readable aten op names -> identifies the O(P*N*M*B) hotspots) at the cuda
training config. Prints the top ops by CUDA time and a self-CUDA-time total. Live nvtop already shows
100% util / ~97% eff (compute-bound); this attributes that compute to specific ops.

  python profile_cuda.py            # eager, ticks=60 (enough to aggregate)
"""
import argparse, sys; sys.path.insert(0, ".")
import torch
from torch.profiler import profile, ProfilerActivity
import train_torch as T
import policy_torch as P


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pop", type=int, default=128)
    ap.add_argument("--perm", type=int, default=32)
    ap.add_argument("--ticks", type=int, default=60)
    args = ap.parse_args()
    assert torch.cuda.is_available()
    dev = "cuda"; T._perf_setup(dev); Pp = 2 * args.pop
    a = type("A", (), {})(); a.client = T.data.DEFAULT_CLIENT; a.dataset = "datasets/surround"; a.map = ""
    a.perm = args.perm; a.cap = 16; a.bullets = 32; a.device = dev
    env, nm, ne = T.build_env(a)
    pl = P.stack_population([P.init_mlp(T.PLAYER_SIZES, device=dev, seed=i) for i in range(Pp)])
    en = P.init_mlp(T.ENEMY_SIZES, device=dev, seed=11)
    pf = lambda o: P.apply_mlp(pl, o); ef = lambda o: P.apply_enemy(en, o)
    roll = lambda: env.rollout(Pp, args.ticks, pf, ef)

    roll(); torch.cuda.synchronize()                       # warmup
    with profile(activities=[ProfilerActivity.CPU, ProfilerActivity.CUDA], record_shapes=False) as prof:
        roll(); torch.cuda.synchronize()

    ka = prof.key_averages()
    print(f"\nPROFILE eager P={Pp} N={ne} M={env.M} B={env.B} ticks={args.ticks}")
    print(prof.key_averages().table(sort_by="self_cuda_time_total", row_limit=18))
    tot = sum(getattr(k, "self_cuda_time_total", 0) for k in ka)
    print(f"total self-CUDA time: {tot/1000:.1f} ms over {args.ticks} ticks")


if __name__ == "__main__":
    main()
