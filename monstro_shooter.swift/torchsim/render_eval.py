"""Agnostic eval renderer (no Metal). Plays the held-out eval maps SYNCHRONIZED and tiles them into a
3x3 grid video (rows=maps, cols=seeds). Draws player + monsters as contours and bullets as bright dots.
CPU draw via PIL — offline, tiny scenes, runs anywhere (Mac + 3090).

Standalone:  python render_eval.py            # uses the saved models, writes datasets/surround/eval/grid.mp4
From trainer: train_torch.py --render <path>  (calls render_grid at end of training)
"""
import argparse, glob, os
import numpy as np
import torch
from PIL import Image, ImageDraw
import imageio.v2 as imageio
import data, schedule
import policy_torch as P
from env_torch import EnvTorch
from world_config import WorldConfig

PLAYER_RADIUS = WorldConfig().player_radius

PALETTE = [(235, 90, 90), (245, 165, 70), (95, 205, 130), (120, 165, 250), (215, 120, 235), (245, 225, 95)]


def _pick_device(pref="auto"):
    if pref and pref != "auto":
        return pref
    if torch.cuda.is_available():
        return "cuda"
    mps = getattr(torch.backends, "mps", None)
    return "mps" if (mps is not None and mps.is_available()) else "cpu"


def _capture_batch(env, ticks_max, real_tot, env_ticks, pf, ef, stride):
    """Capture ALL grid games in ONE batched rollout (vectorized over the N envs, no per-game loop —
    same shape as training). Snapshots the whole [N,...] batch every `stride` ticks; each game freezes
    on its own death / cleared / timeout via `end_idx` (a finished game holds its last frame, matching
    the old one-game-at-a-time renderer). Only the per-tick time loop remains.
    Returns (snaps, end_idx[N], boxW[N,M]); snaps[i] is a dict of [N,...] arrays."""
    s = env.reset(1)
    N = s["player_hp"].shape[1]
    dev = s["player_hp"].device
    boxW = env.mon_boxW.detach().cpu().numpy()                    # [N,M]
    snaps = []
    done = torch.zeros(N, device=dev)
    end_idx = torch.full((N,), -1, dtype=torch.long, device=dev)
    with torch.no_grad():
        for tk in range(1, ticks_max + 1):
            s, _, _, _ = env.step(s, tk, pf, ef)
            if tk == 1 or tk % stride == 0:
                snaps.append(dict(
                    pp=s["player_pos"][0].detach().cpu().numpy(),                          # [N,2]
                    mp=s["mon_pos"][0].detach().cpu().numpy(),                             # [N,M,2]
                    al=((s["mon_act"][0] > 0.5) & (s["mon_hp"][0] > 0)).detach().cpu().numpy(),  # [N,M]
                    bp=s["bul_pos"][0].detach().cpu().numpy(),                             # [N,B,2]
                    ba=(s["bul_alive"][0] > 0.5).detach().cpu().numpy(),                   # [N,B]
                    kills=s["kills"][0].detach().cpu().numpy(),                            # [N]
                    hp=s["player_hp"][0].clamp(min=0.0).detach().cpu().numpy()))           # [N]
            hp = s["player_hp"][0]; k = s["kills"][0]
            cross = ((hp <= 0) | (k >= real_tot) | (tk >= env_ticks)).float()
            newly = (1.0 - done) * cross
            end_idx = torch.where(newly > 0.5, torch.full_like(end_idx, len(snaps) - 1), end_idx)
            done = torch.maximum(done, cross)
            if float(done.min()) > 0.5:
                break
    end_idx = torch.where(end_idx < 0, torch.full_like(end_idx, len(snaps) - 1), end_idx)
    return snaps, end_idx.detach().cpu().numpy(), boxW


def _draw(cap, boxW, ah, size, name, rocks=None):
    img = Image.new("RGB", (size, size), (12, 14, 22)); d = ImageDraw.Draw(img)
    sc = size / (2.0 * ah)
    def px(xy): return ((xy[0] + ah) * sc, (xy[1] + ah) * sc)
    d.rectangle([1, 1, size - 2, size - 2], outline=(55, 60, 78))
    pp, mp, al, bp, ba, kills, hp = cap
    al = al.astype(bool); ba = ba.astype(bool)
    # NOTE: PIL has no batch-ellipse, so drawing is inherently per-shape — but we pre-FILTER to only the real/alive
    # entities (numpy mask) so each loop iterates the minimum and carries no per-item branch. These per-shape loops
    # (and the per-tick capture + per-frame compose loops) are the necessary ones; there's no vectorized PIL path.
    if rocks is not None:                                          # rocks — filled, beneath everything
        for rx, ry, rr in rocks[rocks[:, 2] > 0]:
            x, y = px((rx, ry)); r = rr * sc
            d.ellipse([x - r, y - r, x + r, y + r], fill=(70, 66, 60), outline=(110, 104, 92))
    for bx, by in bp[ba]:                                          # bullets — bright filled dots
        x, y = px((bx, by)); d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(250, 235, 110))
    for (mx, my), bw in zip(mp[al], boxW[al]):                     # monsters — contour rings, colored by type
        x, y = px((mx, my)); r = max(3.0, bw / 2.0 * sc)
        d.ellipse([x - r, y - r, x + r, y + r], outline=PALETTE[int(bw // 10) % len(PALETTE)], width=2)
    # player — white contour ring + center dot
    x, y = px(pp); r = max(4.0, PLAYER_RADIUS * sc)
    d.ellipse([x - r, y - r, x + r, y + r], outline=(240, 240, 255), width=2)
    d.ellipse([x - 1.5, y - 1.5, x + 1.5, y + 1.5], fill=(240, 240, 255))
    d.text((4, 3), name, fill=(175, 185, 210))
    d.text((4, size - 13), f"k{kills} hp{hp:.0f}", fill=(175, 185, 210))
    return np.asarray(img)


def _eval_maps(dataset):
    return sorted(glob.glob(os.path.join(dataset, "eval", "*.json")))


def render_grid(gd, weapons, exo, args, player, enemy, dev, out_path, arch="mlp"):
    """Render a synchronized grid where each ROW is a WEAPON (the SAME weapon-conditioned policy) and each
    COL is an eval map — so you can see at a glance how one policy generalizes across weapons. `weapons` may
    be a list of weapon dicts (cycled) or a single dict. arch='attn' -> attention bundle obs."""
    if not isinstance(weapons, (list, tuple)):
        weapons = [weapons]
    if arch == "attn":
        import policy_attn as AT
        pf = lambda bundle: AT.apply_attn(player, bundle[0], bundle[1], bundle[2])[0]
    else:
        pf = lambda o: P.apply_mlp(player, o)
    ef = (lambda o: P.apply_enemy(enemy, o)) if enemy is not None else None   # None -> scripted steering
    dataset = getattr(args, "dataset", "") or os.path.join(os.path.dirname(__file__), "datasets", "surround")
    stride = getattr(args, "render_stride", 2)
    fps = getattr(args, "render_fps", 30)
    panelpx = getattr(args, "render_panel", 240)
    bullets = getattr(args, "bullets", 24)
    maps = _eval_maps(dataset)[:3]
    levels = [data.sim_level(data.load_map(m)) for m in maps]
    names = [os.path.basename(m).replace(".json", "") for m in maps]
    # cols = the eval maps (1 seed each -> clean weapons x maps grid)
    sched, real_tot, assign = schedule.build_eval(levels, gd.monsters, 1, cap=1024)
    env = EnvTorch(sched, weapons[0], exo, device=dev, bullets=bullets)
    if arch == "attn":
        env.player_obs_fn = env.player_set_obs
    per_ticks = [getattr(args, "eval_ticks", 0) or int(lv["duration"] * 30) for lv in levels]
    env_ticks = torch.tensor([per_ticks[assign[e]] for e in range(len(assign))], device=dev, dtype=torch.float32)
    rt = torch.tensor(real_tot, device=dev)
    ah = sched["arena_half"]                                       # [N]
    rocks_np = env.rocks.detach().cpu().numpy()                     # [N,K,3] static -> drawn as filled circles
    ngames = len(assign)
    # capture one synchronized rollout PER WEAPON (each = a grid row)
    wrows = []
    for wp in weapons:
        env.set_weapon(wp)
        snaps, end_idx, boxW = _capture_batch(env, int(env_ticks.max()), rt, env_ticks, pf, ef, stride)
        wrows.append((str(wp.get("name", wp.get("id", "?"))), snaps, end_idx, boxW))
    maxlen = max(len(s) for _, s, _, _ in wrows)
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    try:                                                          # imageio-ffmpeg required (fail fast, models unaffected)
        import imageio_ffmpeg  # noqa: F401
    except Exception:
        raise RuntimeError("render needs imageio-ffmpeg (`pip install imageio-ffmpeg`, or run in the "
                           "conda env that has it, e.g. `fantastic`). Models are unaffected.")
    w = imageio.get_writer(out_path, fps=fps, macro_block_size=None)
    for t in range(maxlen):                                       # frame compose
        rowimgs = []
        for wname, snaps, end_idx, boxW in wrows:                 # one row per weapon
            pans = []
            for e in range(ngames):                               # one col per map
                sn = snaps[min(t, len(snaps) - 1, int(end_idx[e]))]
                cap = (sn["pp"][e], sn["mp"][e], sn["al"][e], sn["bp"][e], sn["ba"][e],
                       int(sn["kills"][e]), float(sn["hp"][e]))
                pans.append(_draw(cap, boxW[e], float(ah[e]), panelpx, f"{wname}/{names[assign[e]]}", rocks_np[e]))
            rowimgs.append(np.concatenate(pans, axis=1))
        w.append_data(np.concatenate(rowimgs, axis=0))
    w.close()
    print(f"rendered {len(wrows)}x{ngames} grid (weapons x maps) -> {out_path}  ({maxlen} frames @ {fps}fps)")
    return out_path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--client", default=data.DEFAULT_CLIENT)
    ap.add_argument("--dataset", default=os.path.join(os.path.dirname(__file__), "datasets", "surround"))
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
