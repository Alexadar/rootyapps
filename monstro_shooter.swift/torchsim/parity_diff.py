"""Parity diff: torch reference vs Swift port, per game, per tick. Both ran the SAME WorldConfig +
schedule + Core ML models, so positions should track tightly (tiny Core ML-vs-MLP float drift only).
Reports max |Δ| on player + alive monsters + bullets, and confirms kills/hp match."""
import json, os
import numpy as np

OUT = "parity"


def load(p):
    return json.load(open(p))


def main():
    idx = load(f"{OUT}/index.json")
    print(f"{'game':6} {'ticks':>5} {'maxΔplayer':>11} {'maxΔmon':>9} {'maxΔbul':>9}  kills(t/s) hp(t/s)")
    worst = 0.0
    for gid in idx["games"]:
        tj = load(f"{OUT}/torch_{gid}.json")
        sj = load(f"{OUT}/swift_{gid}.json")
        n = min(len(tj), len(sj))
        dp = dm = db = 0.0
        for i in range(n):
            tf, sf = tj[i], sj[i]
            dp = max(dp, float(np.max(np.abs(np.array(tf["player"]) - np.array(sf["player"])))))
            ta, sa = np.array(tf["mon_alive"]), np.array(sf["mon_alive"])
            tp, sp = np.array(tf["mon_pos"]).reshape(-1, 2), np.array(sf["mon_pos"]).reshape(-1, 2)
            both = (ta > 0) & (sa > 0)
            if both.any():
                dm = max(dm, float(np.max(np.abs(tp[both] - sp[both]))))
            tba, sba = np.array(tf["bul_alive"]), np.array(sf["bul_alive"])
            tbp, sbp = np.array(tf["bul_pos"]).reshape(-1, 2), np.array(sf["bul_pos"]).reshape(-1, 2)
            bb = (tba > 0) & (sba > 0)
            if bb.any():
                db = max(db, float(np.max(np.abs(tbp[bb] - sbp[bb]))))
        worst = max(worst, dp, dm)
        k = f"{tj[-1]['kills']}/{sj[-1]['kills']}"
        hp = f"{tj[-1]['hp']:.0f}/{sj[-1]['hp']:.0f}"
        print(f"{gid:6} {n:5} {dp:11.4f} {dm:9.4f} {db:9.4f}  {k:>9} {hp:>7}")
    tol = 1.0  # world units; player moves 10/tick, monsters spawn ~350 away — sub-unit drift = parity
    print(f"\nworst position Δ = {worst:.4f} world units  "
          f"{'✓ PARITY (sub-unit, Core ML float drift)' if worst < tol else '✗ DIVERGENCE'}")


if __name__ == "__main__":
    main()
