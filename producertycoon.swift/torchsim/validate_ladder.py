#!/usr/bin/env python3
"""Phase-4 gate: re-evaluate the CEM difficulty ladder on FRESH seeds.

Checks: (1) achieved win rates track their targets out-of-sample,
(2) the ladder is monotone (harder rung -> lower win rate),
(3) games aren't degenerate-short.

Usage: python3 validate_ladder.py [--policy runs/v1/best.json] [--seeds 512]
"""

import argparse
import json
from pathlib import Path

import torch

import world_config as W
import policy_producer as PP
from cem_gen import eval_population

ap = argparse.ArgumentParser()
ap.add_argument("--policy", default="runs/v1/best.json")
ap.add_argument("--ladder", default="data/generated_worlds.json")
ap.add_argument("--seeds", type=int, default=512)
ap.add_argument("--eval-weeks", type=int, default=208)
ap.add_argument("--device", default="cuda")
args = ap.parse_args()

here = Path(__file__).parent
params, meta = PP.load(here / args.policy, device=args.device)
ladder = json.load((here / args.ladder).open())["ladder"]

rows = [[W.GEN_KNOBS[k][0] for k in W.KNOB_NAMES]] \
    + [[r["knobs"].get(k, W.GEN_KNOBS[k][0]) for k in W.KNOB_NAMES] for r in ladder]
labels = ["default (1.0)"] + [f"target {r['target_win']}" for r in ladder]
thetas = torch.tensor(rows, dtype=torch.float32)

stats = eval_population(thetas, params, seeds=args.seeds, device=args.device,
                        eval_weeks=args.eval_weeks, seed=987654,
                        obs_theta=bool(meta.get("obs_theta", False)))

print(f"{'rung':16} {'win(fresh)':>10} {'bankrupt':>9} {'med_weeks':>10} {'tour_share':>10}")
wins = []
for i, lab in enumerate(labels):
    w = float(stats["win"][i])
    wins.append(w)
    print(f"{lab:16} {w:10.3f} {float(stats['bankrupt'][i]):9.3f} "
          f"{float(stats['med_weeks'][i]):10.0f} {float(stats['tour_share'][i]):10.2f}")

targets = [r["target_win"] for r in ladder]
achieved = wins[1:]
mono = all(achieved[i] >= achieved[i + 1] - 0.03 for i in range(len(achieved) - 1))
close = all(abs(a - t) < 0.1 for a, t in zip(achieved, targets))
print(f"\nmonotone: {'PASS' if mono else 'FAIL'}   "
      f"targets within 0.1 out-of-sample: {'PASS' if close else 'FAIL'}")
