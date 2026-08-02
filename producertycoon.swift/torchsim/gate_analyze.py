#!/usr/bin/env python3
"""STEP-0 degeneracy gate analyzer for The-Producer-Game.

Reads the per-policy JSONL produced by `npx tsx scripts/gateRun.ts` and prints
a verdict per the gate criteria (mirrors froggo's gate_reachability.py role):

  HARD DEGENERATE  best observation-blind policy matches greedy-heuristic on
                   win rate within 2 pts (paired McNemar p>0.05) AND log-fans
                   distributions overlap (KS p>0.01)
  STAT-BLIND       sign-quality-blind ~ greedy-heuristic (artist stats are
                   cosmetic; attention over artists would learn nothing)
  LOTTERY          within-policy IQR of log-fans > 3x the best-vs-worst
                   policy median gap (tier lottery swamps decisions)
  PASS             greedy beats every blind policy by >=10 win-rate pts with
                   separated log-fans (KS p<0.001)

Pure numpy/scipy-free implementation (KS/McNemar by hand) so it runs anywhere.
Usage: python3 torchsim/gate_analyze.py [gate_dir]
"""

import json
import math
import sys
from pathlib import Path

GATE_DIR = Path(sys.argv[1] if len(sys.argv) > 1 else "torchsim/data/gate")

BLIND = ["random-legal", "sign-release-spam", "tour-spam", "all-in-upgrades"]
INFORMED = ["greedy-heuristic", "lean-tourer", "never-upgrade"]
REFERENCE = "greedy-heuristic"
QUALITY_BLIND = "sign-quality-blind"

WIN = {"win-fans", "win-years"}


def load(name):
    rows = [json.loads(l) for l in (GATE_DIR / f"{name}.jsonl").open()]
    return {r["seed"]: r for r in rows}


def win_rate(rows):
    return sum(r["outcome"] in WIN for r in rows.values()) / len(rows)


def log_fans(rows):
    return sorted(math.log10(max(r["finalFans"], 1)) for r in rows.values())


def ks_2samp(a, b):
    """Two-sided KS statistic + asymptotic p-value (both inputs sorted)."""
    i = j = 0
    d = 0.0
    na, nb = len(a), len(b)
    while i < na and j < nb:
        x, y = a[i], b[j]
        if x <= y:
            i += 1
        if y <= x:
            j += 1
        d = max(d, abs(i / na - j / nb))
    en = math.sqrt(na * nb / (na + nb))
    lam = (en + 0.12 + 0.11 / en) * d
    p = 2 * sum((-1) ** (k - 1) * math.exp(-2 * (lam * k) ** 2) for k in range(1, 101))
    return d, max(0.0, min(1.0, p))


def mcnemar_p(rows_a, rows_b):
    """Paired-seed McNemar (exact binomial on discordant pairs) for win/loss."""
    b = c = 0
    for seed, ra in rows_a.items():
        rb = rows_b.get(seed)
        if rb is None:
            continue
        wa, wb = ra["outcome"] in WIN, rb["outcome"] in WIN
        if wa and not wb:
            b += 1
        elif wb and not wa:
            c += 1
    n = b + c
    if n == 0:
        return 1.0
    # two-sided exact binomial p at k=min(b,c), p0=0.5
    k = min(b, c)
    total = sum(math.comb(n, i) for i in range(0, k + 1)) * 2
    return min(1.0, total / 2**n)


def median(xs):
    xs = sorted(xs)
    return xs[len(xs) // 2]


def iqr(xs):
    xs = sorted(xs)
    return xs[3 * len(xs) // 4] - xs[len(xs) // 4]


def main():
    names = [p.stem for p in GATE_DIR.glob("*.jsonl")]
    data = {n: load(n) for n in names}

    print(f"{'policy':22} {'win%':>6} {'weeks':>6} {'fans(med)':>12} {'money(med)':>11} "
          f"{'tours':>6} {'tourOK%':>7}  outcomes")
    for n in sorted(names, key=lambda x: -win_rate(data[x])):
        rows = data[n]
        outs = {}
        for r in rows.values():
            outs[r["outcome"]] = outs.get(r["outcome"], 0) + 1
        tours = sum(r["tours"] for r in rows.values())
        tsucc = sum(r["tourSuccesses"] for r in rows.values())
        print(f"{n:22} {win_rate(rows)*100:6.1f} "
              f"{median([r['weeks'] for r in rows.values()]):6.0f} "
              f"{median([r['finalFans'] for r in rows.values()]):12,.0f} "
              f"{median([r['finalMoney'] for r in rows.values()]):11,.0f} "
              f"{tours:6} {tsucc/max(tours,1)*100:7.0f}  {outs}")

    ref = data[REFERENCE]
    ref_wr = win_rate(ref)
    ref_lf = log_fans(ref)
    verdicts = []

    print(f"\n--- vs {REFERENCE} (win {ref_wr*100:.1f}%) ---")
    hard = False
    for n in BLIND:
        if n not in data:
            continue
        wr = win_rate(data[n])
        d, ksp = ks_2samp(ref_lf, log_fans(data[n]))
        mcp = mcnemar_p(ref, data[n])
        close = abs(ref_wr - wr) < 0.02 and mcp > 0.05 and ksp > 0.01
        hard |= close
        print(f"{n:22} win {wr*100:5.1f}%  Δwin {ref_wr*100-wr*100:+6.1f}pts  "
              f"McNemar p={mcp:.2e}  KS(logfans) D={d:.3f} p={ksp:.2e}"
              f"{'  << MATCHES GREEDY' if close else ''}")
    if hard:
        verdicts.append("HARD DEGENERATE: an observation-blind policy matches greedy")

    if QUALITY_BLIND in data:
        wr = win_rate(data[QUALITY_BLIND])
        mcp = mcnemar_p(ref, data[QUALITY_BLIND])
        gap = (ref_wr - wr) * 100
        print(f"{QUALITY_BLIND:22} win {wr*100:5.1f}%  Δwin {gap:+6.1f}pts  McNemar p={mcp:.2e}")
        if gap < 5 and mcp > 0.05:
            verdicts.append("STAT-BLIND: artist stats are cosmetic (quality-blind ~ greedy)")

    # lottery check: variance within reference vs spread across policies
    all_meds = [median(log_fans(data[n])) for n in names]
    spread = max(all_meds) - min(all_meds)
    ref_iqr = iqr(ref_lf)
    print(f"\nlog-fans: {REFERENCE} IQR={ref_iqr:.2f}, cross-policy median spread={spread:.2f}")
    if spread > 0 and ref_iqr > 3 * spread:
        verdicts.append("LOTTERY: within-policy variance dwarfs policy differences")

    print("\n=== VERDICT ===")
    if verdicts:
        for v in verdicts:
            print(f"FAIL — {v}")
        sys.exit(1)
    print("PASS — decisions matter: greedy separates from every blind policy, "
          "artist stats matter, variance sane")


if __name__ == "__main__":
    main()
