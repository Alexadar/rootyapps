"""Multi-restart, keep-best wrapper (co-evo is seed-fragile: ~2/5 seeds collapse to ~24% clear next to
~90%, algorithm-independent — std, not mean, is the story). Rather than fix fragility, dodge it: train K
seeds, keep the one with the best FIXED-reference eval (--eval-vs scripted). Each child run also logs an
eval-every trace, so this doubles as the collapse diagnostic (early cold-start vs late arms-race tip).

  python train_multi.py --restarts 5 --budget 60 --algo es
Keeps the best player/enemy JSON at --player-out/--enemy-out (the deploy paths)."""
import argparse, json, os, re, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
EVAL_RE = re.compile(r"survival \d+/\d+ \((\d+)%\)\s+kills ([\d.]+)\s+clear (\d+)%")
TRACE_RE = re.compile(r"\[eval @ it\s*(\d+) vs \w+\]\s+survival \d+/\d+ \((\d+)%\)\s+kills ([\d.]+)\s+clear (\d+)%")


def run_seed(args, seed, pout, eout):
    cmd = [sys.executable, os.path.join(HERE, "train_torch.py"),
           "--dataset", args.dataset, "--perm", str(args.perm), "--pop", str(args.pop),
           "--ticks", str(args.ticks), "--cap", "16", "--bullets", str(args.bullets),
           "--iters", "40000", "--budget", str(args.budget), "--algo", args.algo,
           "--seed", str(seed), "--eval", "--eval-seeds", str(args.eval_seeds),
           "--eval-vs", args.eval_vs, "--eval-every", str(args.eval_every),
           "--player-out", pout, "--enemy-out", eout]
    if args.compile:
        cmd.append("--compile")
    if args.algo == "ppo":
        cmd += ["--ppo-group", str(args.ppo_group), "--ppo-minibatch", str(args.ppo_minibatch)]
    if args.extra:
        cmd += args.extra.split()
    # capture STDOUT (eval lines, for parsing) but let STDERR inherit -> the live tqdm progress bar shows
    out = subprocess.run(cmd, cwd=HERE, stdout=subprocess.PIPE, text=True).stdout
    # final eval = the LAST "survival ... clear ..." line that is NOT an eval-every trace line
    finals = [m for m in EVAL_RE.finditer(out) if "[eval @" not in out[max(0, m.start() - 12):m.start()]]
    fin = finals[-1] if finals else None
    trace = [(int(t), int(s), float(k), int(c)) for t, s, k, c in TRACE_RE.findall(out)]
    res = dict(seed=seed, surv=int(fin.group(1)) if fin else -1,
               kills=float(fin.group(2)) if fin else -1, clear=int(fin.group(3)) if fin else -1, trace=trace)
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--restarts", type=int, default=5)
    ap.add_argument("--dataset", default="datasets/surround")
    ap.add_argument("--algo", default="es")
    ap.add_argument("--budget", type=float, default=60)
    ap.add_argument("--perm", type=int, default=32)
    ap.add_argument("--pop", type=int, default=256)
    ap.add_argument("--ticks", type=int, default=600)
    ap.add_argument("--bullets", type=int, default=8)    # ring slots; >= weapon's max simultaneous alive bullets
    ap.add_argument("--eval-seeds", type=int, default=3)
    ap.add_argument("--eval-vs", default="scripted")
    ap.add_argument("--eval-every", type=int, default=20)
    ap.add_argument("--compile", action="store_true", default=True)
    ap.add_argument("--ppo-group", type=int, default=128)
    ap.add_argument("--ppo-minibatch", type=int, default=262144)
    ap.add_argument("--extra", default="")                 # extra flags forwarded to each child run
    ap.add_argument("--player-out", default="../MonstroSim/models/player.json")
    ap.add_argument("--enemy-out", default="../MonstroSim/models/monster.json")
    ap.add_argument("--workdir", default="/tmp/multi")
    args = ap.parse_args()
    os.makedirs(args.workdir, exist_ok=True)

    print(f"multi-restart: {args.restarts} seeds, algo={args.algo}, budget={args.budget}s, eval-vs={args.eval_vs}\n")
    results = []
    for s in range(args.restarts):
        pout = os.path.join(args.workdir, f"player_s{s}.json")
        eout = os.path.join(args.workdir, f"enemy_s{s}.json")
        print(f"--- restart {s + 1}/{args.restarts} (seed {s}) ---", flush=True)
        r = run_seed(args, s, pout, eout)
        r["pout"], r["eout"] = pout, eout
        results.append(r)
        tr = "  ".join(f"it{t}:{c}%" for t, _, _, c in r["trace"])
        print(f"  seed {s}: clear {r['clear']}%  surv {r['surv']}/9  kills {r['kills']:.1f}   trace[ {tr} ]")

    ok = [r for r in results if r["clear"] >= 0]
    best = max(ok, key=lambda r: (r["clear"], r["surv"], r["kills"])) if ok else None
    clears = sorted(r["clear"] for r in ok)
    print(f"\nclear% across {len(ok)} seeds: {clears}  (min={clears[0]} max={clears[-1]})")
    if best:
        shutil.copy(best["pout"], args.player_out)
        shutil.copy(best["eout"], args.enemy_out)
        print(f"BEST = seed {best['seed']} (clear {best['clear']}%, surv {best['surv']}/9) "
              f"-> saved to {args.player_out} + {args.enemy_out}")


if __name__ == "__main__":
    main()
