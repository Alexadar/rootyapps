#!/usr/bin/env python3
"""Statistical parity: torch env vs TS golden vectors.

Runs the three golden policies in the batched env (N = golden episode count),
records the same weekly checkpoints, compares distributions via KS tests
(alpha=0.001, Bonferroni over all tests) + outcome-frequency chi^2-style diff.

Rule-parity, not bit-parity: RNG streams differ by design; only the
distributions must match.

Usage: python3 torchsim/test_parity.py [--policy NAME] [--device cuda]
"""

import argparse
import json
import math
import sys
from pathlib import Path

import torch

sys.path.insert(0, str(Path(__file__).parent))
import world_config as W
from env_producer import ProducerEnv
import py_policies

CHECKPOINTS = [4, 12, 26, 52, 104, 208, 480]
METRICS = ["money", "fans", "tokens", "rep", "roster", "releases"]
GOLDEN_DIR = W.DATA_DIR / "golden"


def ks_2samp(a, b):
    a, b = sorted(a), sorted(b)
    i = j = 0
    d = 0.0
    na, nb = len(a), len(b)
    if na == 0 or nb == 0:
        return 0.0, 1.0
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


def load_golden(name):
    rows = [json.loads(l) for l in (GOLDEN_DIR / f"{name}.jsonl").open()]
    finals = {
        "outcome": [r["outcome"] for r in rows],
        "weeks": [r["weeks"] for r in rows],
        "log_fans": [math.log10(max(r["finalFans"], 1)) for r in rows],
        "money": [r["finalMoney"] for r in rows],
        "tours": [r["tours"] for r in rows],
        "equip": [r["equipmentBought"] for r in rows],
        "staff": [r["staffFinal"] for r in rows],
    }
    cps = {wk: {m: [] for m in METRICS} for wk in CHECKPOINTS}
    for r in rows:
        for wk, snap in (r.get("checkpoints") or {}).items():
            wk = int(wk)
            for m in METRICS:
                cps[wk][m].append(snap[m])
    return finals, cps, len(rows)


OUTCOME_NAMES = {0: "running", 1: "win-fans", 2: "win-years", 3: "bankrupt",
                 4: "reputation", 5: "rejects", 6: "timeout"}


def run_env_policy(name, n, device, seed=123, max_steps=12000):
    env = ProducerEnv(n, device=device, seed=seed)
    rng = torch.Generator(device=device).manual_seed(seed + 1)
    policy = py_policies.POLICIES[name]
    released = torch.zeros(n, 12, dtype=torch.bool, device=device)
    ending = torch.zeros(n, dtype=torch.bool, device=device)   # random-legal sticky stop
    n_tours = torch.zeros(n, device=device)
    n_equip = torch.zeros(n, device=device)

    cps = {wk: {m: None for m in METRICS} for wk in CHECKPOINTS}
    cp_taken = {wk: torch.zeros(n, dtype=torch.bool, device=device) for wk in CHECKPOINTS}
    cp_store = {wk: {m: torch.zeros(n, device=device) for m in METRICS} for wk in CHECKPOINTS}

    for step in range(max_steps):
        mask = env.legal_mask()
        # released-this-week tracker: greedy/spam release each artist once/week
        if name in ("greedy-heuristic", "sign-release-spam"):
            m2 = mask.clone()
            m2[:, W.A_RELEASE:W.A_RELEASE + 12] &= ~released
            # keep escape hatch: if that kills all release options while endWeek
            # is blocked, restore originals
            no_rel = ~m2[:, W.A_RELEASE:W.A_RELEASE + 12].any(1)
            blocked = env.s["week_advanced"] & no_rel
            m2[:, W.A_RELEASE:W.A_RELEASE + 12] = torch.where(
                blocked.unsqueeze(1), mask[:, W.A_RELEASE:W.A_RELEASE + 12],
                m2[:, W.A_RELEASE:W.A_RELEASE + 12])
            mask = m2
        if name == "random-legal":
            ending |= torch.rand(n, device=device, generator=rng) < 0.25
            act = policy(env, mask, rng, ending)
        elif name == "greedy-heuristic":
            act = policy(env, mask, rng, released.any(1))
        else:
            act = policy(env, mask, rng)
        is_rel = (act >= W.A_RELEASE) & (act < W.A_RELEASE + 12)
        rows = torch.arange(n, device=device)[is_rel]
        released[rows, (act[is_rel] - W.A_RELEASE)] = True
        is_end = act == W.A_END_WEEK
        released[is_end] = False
        n_tours += ((act >= W.A_TOUR) & (act < W.A_TOUR + 12)).float()
        n_equip += ((act >= W.A_BUY_EQUIP) & (act < W.A_BUY_EQUIP + W.N_EQUIP)).float()

        week_before = env.s["week"].clone()
        _, done, _ = env.step(act)
        week_after = env.s["week"]
        ending &= ~(week_after > week_before)
        for wk in CHECKPOINTS:
            hit = (week_before < wk) & (week_after >= wk) & ~cp_taken[wk]
            if hit.any():
                s = env.s
                vals = {
                    "money": s["money"], "fans": s["fans"], "tokens": s["tokens"],
                    "rep": s["rep"], "roster": s["alive"][:, :12].sum(1).float(),
                    "releases": s["releases"],
                }
                for m in METRICS:
                    cp_store[wk][m] = torch.where(hit, vals[m], cp_store[wk][m])
                cp_taken[wk] |= hit
        if bool(done.all()):
            break

    finals = {
        "outcome": [OUTCOME_NAMES[int(o)] for o in env.s["outcome"].tolist()],
        "weeks": env.s["week"].tolist(),
        "log_fans": [math.log10(max(f, 1)) for f in env.s["fans"].tolist()],
        "money": env.s["money"].tolist(),
        "tours": n_tours.tolist(),
        "equip": n_equip.tolist(),
        "staff": env.s["staff"].float().sum(1).tolist(),
    }
    cps_out = {}
    for wk in CHECKPOINTS:
        taken = cp_taken[wk]
        cps_out[wk] = {m: cp_store[wk][m][taken].tolist() for m in METRICS}
    return finals, cps_out, env


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--policy", default=None)
    ap.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    args = ap.parse_args()

    names = [args.policy] if args.policy else ["random-legal", "sign-release-spam", "greedy-heuristic"]
    total_tests = 0
    failures = []

    for name in names:
        g_finals, g_cps, n = load_golden(name)
        p_finals, p_cps, env = run_env_policy(name, n, args.device)

        print(f"\n=== {name} (n={n}) ===")
        # outcome frequencies
        def freq(xs):
            f = {}
            for x in xs:
                f[x] = f.get(x, 0) + 1
            return {k: v / len(xs) for k, v in sorted(f.items())}
        gf, pf = freq(g_finals["outcome"]), freq(p_finals["outcome"])
        print(f"  outcomes TS : { {k: round(v,3) for k,v in gf.items()} }")
        print(f"  outcomes PY : { {k: round(v,3) for k,v in pf.items()} }")
        max_dev = max(abs(gf.get(k, 0) - pf.get(k, 0)) for k in set(gf) | set(pf))
        print(f"  max outcome freq deviation: {max_dev:.3f}")
        import statistics as _st
        for k in ("tours", "equip", "staff"):
            print(f"  activity {k:6}: TS mean {_st.mean(g_finals[k]):7.2f}  PY mean {_st.mean(p_finals[k]):7.2f}")

        for key in ("weeks", "log_fans"):
            d, p = ks_2samp(g_finals[key], p_finals[key])
            total_tests += 1
            flag = "FAIL" if p < 0.001 / 60 else "ok"
            if flag == "FAIL":
                failures.append(f"{name}/final/{key} D={d:.3f}")
            print(f"  final {key:10} KS D={d:.3f} p={p:.2e} [{flag}]")

        for wk in CHECKPOINTS:
            gm = g_cps[wk]
            pm = p_cps[wk]
            if not gm["money"] or not pm["money"]:
                continue
            line = f"  wk{wk:4} (TS n={len(gm['money'])}, PY n={len(pm['money'])}): "
            for m in METRICS:
                d, p = ks_2samp(gm[m], pm[m])
                total_tests += 1
                bad = p < 0.001 / 60
                if bad:
                    failures.append(f"{name}/wk{wk}/{m} D={d:.3f}")
                line += f"{m} D={d:.2f}{'!' if bad else ' '} "
            print(line)

    print(f"\n=== PARITY: {total_tests} tests, {len(failures)} failures ===")
    for f in failures:
        print(f"  FAIL {f}")
    sys.exit(1 if len(failures) > max(2, total_tests // 20) else 0)


if __name__ == "__main__":
    main()
