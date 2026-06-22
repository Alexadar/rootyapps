"""Agnostic eval renderer (no Metal). Plays the held-out eval maps SYNCHRONIZED and tiles them into a
3x3 grid video (rows=maps, cols=seeds). Draws player + monsters as contours and bullets as bright dots.
CPU draw via PIL — offline, tiny scenes, runs anywhere (Mac + 3090).

Standalone:  python render_eval.py            # uses the saved models, writes datasets/tiny/eval/grid.mp4
From trainer: train_torch.py --render <path>  (calls render_grid at end of training)
"""
import argparse, glob, os
import numpy as np
import torch
from PIL import Image, ImageDraw
import imageio.v2 as imageio
import data, schedule
import policy_torch as P
from env_torch import EnvTorch, PLAYER_RADIUS

PALETTE = [(235, 90, 90), (245, 165, 70), (95, 205, 130), (120, 165, 250), (215, 120, 235), (245, 225, 95)]


def _pick_device(pref="auto"):
    if pref and pref != "auto":
        return pref
    if torch.cuda.is_available():
        return "cuda"
    mps = getattr(torch.backends, "mps", None)
    return "mps" if (mps is not None and mps.is_available()) else "cpu"


def _capture(env, ticks_max, pf, ef, stride):
    """Play one game, snapshot (player, monsters, bullets, kills, hp) every `stride` ticks."""
    s = env.reset(1); M = env.M
    boxW = env.mon_boxW[0].detach().cpu().numpy()                 # [M]
    caps = []
    with torch.no_grad():
        for tk in range(1, ticks_max + 1):
            s, _, _ = env.step(s, tk, pf, ef)
            if tk == 1 or tk % stride == 0:
                pp = s["player_pos"][0, 0].detach().cpu().numpy()
                mp = s["mon_pos"][0, 0].detach().cpu().numpy()
                al = ((s["mon_act"][0, 0] > 0.5) & (s["mon_hp"][0, 0] > 0)).detach().cpu().numpy()
                bp = s["bul_pos"][0, 0].detach().cpu().numpy()
                ba = (s["bul_alive"][0, 0] > 0.5).detach().cpu().numpy()
                caps.append((pp.copy(), mp.copy(), al.copy(), bp.copy(), ba.copy(),
                             int(s["kills"][0, 0]), max(float(s["player_hp"][0, 0]), 0.0)))
            if float(s["player_hp"][0, 0]) <= 0 or int(s["kills"][0, 0]) >= M:
                break
    return caps, boxW


def _draw(cap, boxW, ah, size, name):
    img = Image.new("RGB", (size, size), (12, 14, 22)); d = ImageDraw.Draw(img)
    sc = size / (2.0 * ah)
    def px(xy): return ((xy[0] + ah) * sc, (xy[1] + ah) * sc)
    d.rectangle([1, 1, size - 2, size - 2], outline=(55, 60, 78))
    pp, mp, al, bp, ba, kills, hp = cap
    # bullets — bright filled dots (visible)
    for i in range(len(bp)):
        if ba[i]:
            x, y = px(bp[i]); d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(250, 235, 110))
    # monsters — contour rings, colored by type (boxW proxy)
    for i in range(len(mp)):
        if al[i]:
            x, y = px(mp[i]); r = max(3.0, boxW[i] / 2.0 * sc)
            d.ellipse([x - r, y - r, x + r, y + r], outline=PALETTE[int(boxW[i] // 10) % len(PALETTE)], width=2)
    # player — white contour ring + center dot
    x, y = px(pp); r = max(4.0, PLAYER_RADIUS * sc)
    d.ellipse([x - r, y - r, x + r, y + r], outline=(240, 240, 255), width=2)
    d.ellipse([x - 1.5, y - 1.5, x + 1.5, y + 1.5], fill=(240, 240, 255))
    d.text((4, 3), name, fill=(175, 185, 210))
    d.text((4, size - 13), f"k{kills} hp{hp:.0f}", fill=(175, 185, 210))
    return np.asarray(img)


def _eval_maps(dataset):
    return sorted(glob.glob(os.path.join(dataset, "eval", "*.json")))


def render_grid(gd, weapon, exo, args, player, enemy, dev, out_path):
    """Render the 3x3 (maps x seeds) synchronized grid video to out_path."""
    pf = lambda o: P.apply_mlp(player, o)
    ef = lambda o: P.apply_enemy(enemy, o)
    dataset = getattr(args, "dataset", "") or os.path.join(os.path.dirname(__file__), "datasets", "tiny")
    seeds = max(1, getattr(args, "eval_seeds", 3))
    stride = getattr(args, "render_stride", 2)
    fps = getattr(args, "render_fps", 30)
    panel = getattr(args, "render_panel", 240)
    bullets = getattr(args, "bullets", 24)
    maps = _eval_maps(dataset)[:3]
    games = []
    for mp in maps:
        level = data.sim_level(data.load_map(mp))
        total = max(level["expected_total"], 1)
        ah = level["arena_half"]
        ticks = getattr(args, "eval_ticks", 0) or int(level["duration"] * 30)
        for sd in range(seeds):
            sched = schedule.build(level, gd.monsters, base_seed=1000 + sd * 7919, n_envs=1, cap=min(total, 1024))
            env = EnvTorch(sched, weapon, exo, device=dev, bullets=bullets)
            caps, boxW = _capture(env, ticks, pf, ef, stride)
            games.append((caps, boxW, ah, f"{os.path.basename(mp).replace('.json', '')}#{sd}"))
    rows, cols = len(maps), seeds
    maxlen = max(len(g[0]) for g in games)
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    w = imageio.get_writer(out_path, fps=fps, macro_block_size=None)
    for t in range(maxlen):
        rowimgs = []
        for r in range(rows):
            pans = []
            for c in range(cols):
                caps, boxW, ah, name = games[r * cols + c]
                pans.append(_draw(caps[min(t, len(caps) - 1)], boxW, ah, panel, name))
            rowimgs.append(np.concatenate(pans, axis=1))
        w.append_data(np.concatenate(rowimgs, axis=0))
    w.close()
    print(f"rendered {rows}x{cols} grid -> {out_path}  ({maxlen} frames @ {fps}fps)")
    return out_path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--client", default=data.DEFAULT_CLIENT)
    ap.add_argument("--dataset", default=os.path.join(os.path.dirname(__file__), "datasets", "tiny"))
    ap.add_argument("--player", default="../MonstroSim/models/player.json")
    ap.add_argument("--enemy", default="../MonstroSim/models/monster.json")
    ap.add_argument("--out", default="")                 # default: <dataset>/eval/grid.mp4
    ap.add_argument("--device", default="auto")
    ap.add_argument("--bullets", type=int, default=24)
    ap.add_argument("--eval-seeds", type=int, default=3)
    ap.add_argument("--eval-ticks", type=int, default=0)
    ap.add_argument("--render-stride", type=int, default=2)
    ap.add_argument("--render-fps", type=int, default=30)
    ap.add_argument("--render-panel", type=int, default=240)
    args = ap.parse_args()
    dev = _pick_device(args.device)
    gd = data.GameData(args.client)
    weapon = gd.weapons.get(1) or next(iter(gd.weapons.values()))
    exo = gd.exoskeletons.get(1) or next(iter(gd.exoskeletons.values()))
    player, _ = P.from_json(args.player, dev)
    enemy, _ = P.from_json(args.enemy, dev)
    out = args.out or os.path.join(args.dataset, "eval", "grid.mp4")
    render_grid(gd, weapon, exo, args, player, enemy, dev, out)


if __name__ == "__main__":
    main()
