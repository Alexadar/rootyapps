#!/usr/bin/env bash
# run.sh — the scout milestone, one command.
#
#   ./run.sh                 60 s scan, 10 drones, real-time video -> videos/scout.mp4
#   ./run.sh 1800            180 s scan (the 100%-coverage configuration)
#   ./run.sh 1800 fast       same, but a smooth 6x video (all frames @ 60 fps — never frame-dropped)
#
# Uses the base conda python (cuda + av are required; see scout.py header).
set -euo pipefail
cd "$(dirname "$0")"
STEPS="${1:-600}"
MODE="${2:-real}"
python - "$STEPS" "$MODE" <<'PY'
import sys
sys.path.insert(0, "."); sys.path.insert(0, "..")
import torch
from scout import *

steps = int(sys.argv[1]); mode = sys.argv[2]
dev = "cuda" if torch.cuda.is_available() else "cpu"
pts = make_grid(device=dev)
ccen, chalf = random_cubes(pts, n=10, device=dev)
cen, ijk, n_drop = reachable(*subcubes(pts, 12.0), ccen, chalf)
order = serpentine(ijk)
seg, lens = split_runs(order, 10)
start = clear_spawns(launch_line(pts, 10, device=dev), ccen, chalf)
frames = run_flock(pts, cen, seg, lens, (19, 24), start=start, cub=(ccen, chalf), max_steps=steps)
seen = frames[-1][3]; solid = frames[-1][5]; free = ~solid
print(f"GREY COVERAGE: {100 * float((seen & free).float().sum() / free.float().sum()):.1f}%  "
      f"({int((seen & free).sum())}/{int(free.sum())} scannable points, {len(frames) / 10:.0f}s)")
# real  -> 1 s of video per 1 s of sim (stride 1 @ 10 fps)
# fast  -> 6x speed WITHOUT dropping frames (stride 1 @ 60 fps) — speed comes from fps, never from skipping
fps = 60 if mode == "fast" else 10
render(pts, frames, "videos/scout.mp4", stride=1, fps=fps, device=dev)
print(f"wrote videos/scout.mp4 ({'6x' if mode == 'fast' else 'real-time'})")
PY
