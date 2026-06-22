"""Render the 3x3 grid from the SWIFT port's trajectories (parity/swift_*.json) — the "same grid for
Mac" produced by the ported engine. Reuses render_eval._draw so it's pixel-identical in style to the
torch grid (and, given parity Δ<0.0012, visually identical in content). Output gitignored."""
import glob, json, os
import numpy as np
import imageio.v2 as imageio
from render_eval import _draw

OUT = "parity"


def main():
    idx = json.load(open(f"{OUT}/index.json"))
    games = []
    for gid in idx["games"]:
        sched = json.load(open(f"{OUT}/sched_{gid}.json"))
        frames = json.load(open(f"{OUT}/swift_{gid}.json"))
        boxW = np.array(sched["boxW"], np.float32)
        ah = float(sched["arena_half"])
        caps = []
        for f in frames:
            pp = np.array(f["player"], np.float32)
            mp = np.array(f["mon_pos"], np.float32).reshape(-1, 2)
            al = np.array(f["mon_alive"])
            bp = np.array(f["bul_pos"], np.float32).reshape(-1, 2)
            ba = np.array(f["bul_alive"])
            caps.append((pp, mp, al, bp, ba, f["kills"], max(f["hp"], 0.0)))
        games.append((caps, boxW, ah, f"{sched['name']}#{gid[-1]}"))
    rows, cols, panel, fps = 3, 3, 240, 30
    maxlen = max(len(g[0]) for g in games)
    out = f"{OUT}/swift_grid.mp4"
    w = imageio.get_writer(out, fps=fps, macro_block_size=None)
    stride = 2
    for t in range(0, maxlen, stride):
        rowimgs = []
        for r in range(rows):
            pans = []
            for c in range(cols):
                caps, boxW, ah, name = games[r * cols + c]
                pans.append(_draw(caps[min(t, len(caps) - 1)], boxW, ah, panel, name))
            rowimgs.append(np.concatenate(pans, axis=1))
        w.append_data(np.concatenate(rowimgs, axis=0))
    w.close()
    print(f"rendered Swift 3x3 grid -> {out}  ({maxlen // stride} frames)")


if __name__ == "__main__":
    main()
