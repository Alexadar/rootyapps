"""render_drone — the fixed-camera 3D "moviegen". A single fixed perspective camera looks down on the
arena; the swarm dives on the ground enemies. Capture = batched CPU snapshots from a mean-action
rollout (env._snapshot, per-env frozen at episode end); compose = hand-written pinhole projection +
painter's depth sort, PIL drawing per panel, 2x2 env grid; encode = imageio + imageio-ffmpeg (PyAV's
shim is absent here; monstro's writer path). The renderer reads the SAME hf/obst tensors the SDF
collides against, so what you see is what the sim simulated.
"""
import numpy as np
import torch
from PIL import Image, ImageDraw

import policy_attn as AT
import policy_recur as RE
from env_drone import game_loop

PANEL_W, PANEL_H, FPS = 480, 360, 25
SKY_TOP = (28, 34, 52); SKY_BOT = (60, 72, 98)
DRONE_C = (90, 220, 255); DRONE_DEAD = (70, 80, 95)
TANK_C = (225, 80, 70); SOLDIER_C = (240, 165, 70); ENEMY_DEAD = (90, 70, 70)
TREE_C = (70, 160, 90); ROCK_C = (120, 116, 104)


def _bilerp_np(hf, x, y, extent):
    G = hf.shape[0]
    gx = np.clip((x / extent + 1) * 0.5 * (G - 1), 0, G - 1); gy = np.clip((y / extent + 1) * 0.5 * (G - 1), 0, G - 1)
    ix = np.floor(gx).astype(int).clip(0, G - 2); tx = gx - ix
    iy = np.floor(gy).astype(int).clip(0, G - 2); ty = gy - iy
    h00 = hf[iy, ix]; h10 = hf[iy, ix + 1]; h01 = hf[iy + 1, ix]; h11 = hf[iy + 1, ix + 1]
    return h00 * (1 - tx) * (1 - ty) + h10 * tx * (1 - ty) + h01 * (1 - tx) * ty + h11 * tx * ty


def make_camera(cfg, W=PANEL_W, H=PANEL_H, fov_deg=52.0):
    """Fixed pinhole camera high above an arena corner, looking DOWN at the ground centre. The steep
    downward tilt (eye well above the ceiling, look-at on the deck) keeps the far arena edge BELOW the
    horizon — otherwise ground-level action at the boundary (where fleeing enemies get cornered and
    drones strike) projects up into the sky band and reads as mid-air detonations."""
    center = np.array([0.0, 0.0, 0.0])                                          # look at the ground, not mid-air
    eye = np.array([cfg.arena_half * 1.15, -cfg.arena_half * 1.5, cfg.ceiling * 2.4 + cfg.terrain_amp * 2.0])
    up = np.array([0.0, 0.0, 1.0])
    fwd = center - eye; fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, up); right /= np.linalg.norm(right)
    up2 = np.cross(right, fwd)
    f = 0.5 * W / np.tan(np.radians(fov_deg) / 2)
    return dict(eye=eye, right=right, up=up2, fwd=fwd, f=f, W=W, H=H)


def project(cam, pts):
    """world pts [...,3] -> (screen [...,2], depth [...])."""
    rel = pts - cam["eye"]
    x = rel @ cam["right"]; y = rel @ cam["up"]; z = rel @ cam["fwd"]
    z = np.clip(z, 1e-2, None)
    sx = cam["W"] / 2 + cam["f"] * x / z
    sy = cam["H"] / 2 - cam["f"] * y / z
    return np.stack([sx, sy], -1), z


def _sky(W, H):
    img = Image.new("RGB", (W, H))
    px = img.load()
    for j in range(H):                                          # RENDER-LOOP-OK (offline drawing)
        t = j / H
        c = tuple(int(SKY_TOP[k] * (1 - t) + SKY_BOT[k] * t) for k in range(3))
        for i in range(W):
            px[i, j] = c
    return img


def render_background(cfg, hf, obst, cam):
    """Terrain mesh (height-shaded, painter-sorted) + obstacles, drawn ONCE per env (static cam+terrain)."""
    img = _sky(cam["W"], cam["H"]); dr = ImageDraw.Draw(img)
    ext = cfg.arena_half; Gr = 22
    ax = np.linspace(-ext, ext, Gr)
    gx, gy = np.meshgrid(ax, ax)
    gz = _bilerp_np(hf, gx, gy, ext)
    cells = []                                                  # (depth, poly, color)
    for i in range(Gr - 1):                                     # RENDER-LOOP-OK (offline mesh build)
        for j in range(Gr - 1):
            cx = np.array([gx[i, j], gx[i, j + 1], gx[i + 1, j + 1], gx[i + 1, j]])
            cy = np.array([gy[i, j], gy[i, j + 1], gy[i + 1, j + 1], gy[i + 1, j]])
            cz = np.array([gz[i, j], gz[i, j + 1], gz[i + 1, j + 1], gz[i + 1, j]])
            scr, dep = project(cam, np.stack([cx, cy, cz], -1))
            hnorm = float(cz.mean()) / (cfg.terrain_amp + 1e-6)
            shade = 0.45 + 0.55 * hnorm
            col = (int(60 * shade + 30), int(110 * shade + 40), int(70 * shade + 30))
            cells.append((float(dep.mean()), [tuple(p) for p in scr], col))
    for _, poly, col in sorted(cells, key=lambda c: -c[0]):     # far -> near (painter)
        dr.polygon(poly, fill=col, outline=(col[0] - 8, col[1] - 8, col[2] - 8))
    # obstacles
    om = np.abs(obst[:, 3:6]).sum(1) > 1e-6
    for o in range(obst.shape[0]):                              # RENDER-LOOP-OK
        if not om[o]:
            continue
        x, y, zc, hx, hy, hz, is_cyl = obst[o]
        base = np.array([x, y, zc - hz]); top = np.array([x, y, zc + hz])
        b = project(cam, base[None])[0][0]; t = project(cam, top[None])[0][0]
        if is_cyl > 0.5:
            dr.line([tuple(b), tuple(t)], fill=(60, 110, 70), width=4)
            dr.ellipse([t[0] - 5, t[1] - 5, t[0] + 5, t[1] + 5], fill=TREE_C)
        else:
            r = 5
            dr.rectangle([t[0] - r, t[1] - r, t[0] + r, t[1] + r], fill=ROCK_C, outline=(90, 86, 78))
    return img


def draw_frame(cfg, bg, hf, snap, e, cam):
    """One panel: static background + moving entities (painter-sorted) + HUD, for env index e."""
    img = bg.copy(); dr = ImageDraw.Draw(img)
    ext = cfg.arena_half
    dp = snap["d_pos"][0, e]; da = snap["d_alive"][0, e]; dact = snap["d_act"][0, e]
    ep = snap["e_pos"][0, e]; ea = snap["e_alive"][0, e]; et = snap["e_type"][e]
    # collect drawables with depth
    items = []
    ez = _bilerp_np(hf, ep[:, 0], ep[:, 1], ext)
    e3 = np.concatenate([ep, ez[:, None]], -1)
    escr, edep = project(cam, e3)
    for k in range(ep.shape[0]):                               # RENDER-LOOP-OK
        col = (TANK_C if et[k] > 0.5 else SOLDIER_C) if ea[k] > 0.5 else ENEMY_DEAD
        sz = 7 if et[k] > 0.5 else 5
        items.append((edep[k], "box", tuple(escr[k]), col, sz))
    dscr, ddep = project(cam, dp)
    for k in range(dp.shape[0]):                               # RENDER-LOOP-OK
        if dact[k] < 0.5 or da[k] < 0.5:
            continue                                           # not launched yet, OR dead (kamikaze -> vanish;
        #                                                        no frozen corpse cloud at the horizon edge)
        items.append((ddep[k], "drone", tuple(dscr[k]), DRONE_C, 4))
    for _, kind, p, col, sz in sorted(items, key=lambda c: -c[0]):
        if kind == "box":
            dr.rectangle([p[0] - sz, p[1] - sz, p[0] + sz, p[1] + sz], fill=col, outline=(20, 20, 25))
        else:
            dr.ellipse([p[0] - sz, p[1] - sz, p[0] + sz, p[1] + sz], fill=col)
            dr.point([p[0], p[1]], fill=(255, 255, 255))
    E = ep.shape[0]
    kills = int(snap["kills"][0, e]); alive_d = int((da > 0.5).sum()); alive_e = int((ea > 0.5).sum())
    dr.text((6, 4), f"kills {kills}/{E}   drones {alive_d}   enemies {alive_e}", fill=(220, 226, 240))
    return img


def capture(env, dparams, dls, eparams, els, K_dec, H, stride=2, mm_dtype=None):
    def dfn(sf, tk, mk, h_in):                                   # recurrent drone (mean action)
        mu, _, h_new = RE.apply_recur(dparams, sf, tk, mk, h_in, mm_dtype)
        return mu, h_new
    efn = lambda sf, tk, mk: AT.apply_attn(eparams, sf, tk, mk, mm_dtype)[0]
    snaps = []
    game_loop(env, dfn, efn, 1, K_dec, record=snaps, record_stride=stride, drone_recur=True, latent_h=H)
    return snaps


def render(env, dparams, dls, eparams, els, K_dec, H, out_path, mm_dtype=None, n_panel=4, cols=2):
    import imageio.v2 as imageio
    cfg = env.cfg
    snaps = capture(env, dparams, dls, eparams, els, K_dec, H, mm_dtype=mm_dtype)  # sim device-agnostic; snaps are CPU
    cam = make_camera(cfg)
    hfs = env.hf.detach().cpu().numpy()
    obs = torch.cat([env.obst_xyz, env.obst_half, env.obst_cyl[..., None]], -1).detach().cpu().numpy()
    n_panel = min(n_panel, env.N)
    bgs = [render_background(cfg, hfs[e], obs[e], cam) for e in range(n_panel)]    # once per env
    cols = min(cols, n_panel) if n_panel > 1 else 1; rows = (n_panel + cols - 1) // cols
    w = imageio.get_writer(out_path, fps=FPS, macro_block_size=None)
    for snap in snaps:                                         # RENDER-LOOP-OK (frame loop, offline)
        panels = [draw_frame(cfg, bgs[e], hfs[e], snap, e, cam) for e in range(n_panel)]
        grid = Image.new("RGB", (cols * PANEL_W, rows * PANEL_H), (0, 0, 0))
        for e, p in enumerate(panels):
            grid.paste(p, ((e % cols) * PANEL_W, (e // cols) * PANEL_H))
        w.append_data(np.asarray(grid))
    w.close()
    return out_path
