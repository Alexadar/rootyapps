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
DRONE_C = (90, 220, 255); DRONE_DEAD = (70, 80, 95); CRASH_C = (8, 8, 10)
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
    # frame the COMBAT ZONE (+ margin) if one is set, else the whole arena — otherwise a 3x arena renders the
    # central fight too small to see.
    frame = 2.0 * cfg.combat_half if getattr(cfg, "combat_half", 0) > 0 else cfg.arena_half
    eye = np.array([frame * 1.15, -frame * 1.5, cfg.ceiling * 2.4 + cfg.terrain_amp * 2.0])
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


_SKY_CACHE = {}                                                 # (W,H) -> prebuilt sky Image (it's constant per size)


def _sky(W, H):
    """Vertical sky gradient (SKY_TOP at the top row -> SKY_BOT at the bottom). It depends ONLY on (W,H),
    so build it ONCE per size and cache it. (This used to be a per-pixel Python double loop rebuilt on every
    single background render -> ~W*H iterations * (panels*frames) calls == the renderer's #1 hot spot; with a
    moving/auto-fit camera that reprojects the ground every frame it dominated everything. Now: one
    vectorized numpy fill, cached, and we hand back a cheap C-level .copy() for the caller to draw on.)"""
    key = (W, H)
    base = _SKY_CACHE.get(key)
    if base is None:
        t = np.linspace(0.0, 1.0, H, dtype=np.float32)[:, None]           # [H,1] top->bottom blend parameter
        top = np.array(SKY_TOP, np.float32); bot = np.array(SKY_BOT, np.float32)
        row = (top * (1.0 - t) + bot * t).astype(np.uint8)                # [H,3] one color per scan-row
        arr = np.broadcast_to(row[:, None, :], (H, W, 3)).copy()          # [H,W,3] every column = its row color
        base = Image.fromarray(arr, "RGB")
        _SKY_CACHE[key] = base
    return base.copy()                                                    # fresh canvas each call (caller draws on it)


def render_background(cfg, hf, obst, cam):
    """Terrain mesh (height-shaded, painter-sorted) + obstacles, drawn ONCE per env (static cam+terrain)."""
    img = _sky(cam["W"], cam["H"]); dr = ImageDraw.Draw(img)
    ext = cfg.arena_half; Gr = 22
    ax = np.linspace(-ext, ext, Gr)
    gx, gy = np.meshgrid(ax, ax)                                 # [Gr,Gr] world-XY grid of terrain vertices
    gz = _bilerp_np(hf, gx, gy, ext)                            # [Gr,Gr] terrain height at each vertex
    # Project ALL Gr*Gr vertices in ONE vectorized call (was 441 tiny per-quad project() calls -> pure Python
    # overhead). Then quads just index the shared projected-vertex grid by corner.
    scr_all, dep_all = project(cam, np.stack([gx, gy, gz], -1).reshape(-1, 3))
    scr_all = scr_all.reshape(Gr, Gr, 2); dep_all = dep_all.reshape(Gr, Gr)
    # Per-quad (i,j) = the cell with corners (i,j)->(i,j+1)->(i+1,j+1)->(i+1,j). Depth/shade computed vectorized.
    dep_q = 0.25 * (dep_all[:-1, :-1] + dep_all[:-1, 1:] + dep_all[1:, 1:] + dep_all[1:, :-1])   # [Gr-1,Gr-1] mean depth
    z_q = 0.25 * (gz[:-1, :-1] + gz[:-1, 1:] + gz[1:, 1:] + gz[1:, :-1])                          # mean height (for shade)
    shade = 0.45 + 0.55 * (z_q / (cfg.terrain_amp + 1e-6))                                        # higher ground = lighter
    rr = (60 * shade + 30).astype(int); gg = (110 * shade + 40).astype(int); bb = (70 * shade + 30).astype(int)
    cells = []                                                  # (depth, poly, color) per quad
    for i in range(Gr - 1):                                     # RENDER-LOOP-OK (offline mesh build; PIL polys stay per-quad)
        for j in range(Gr - 1):
            poly = [tuple(scr_all[i, j]), tuple(scr_all[i, j + 1]), tuple(scr_all[i + 1, j + 1]), tuple(scr_all[i + 1, j])]
            cells.append((float(dep_q[i, j]), poly, (int(rr[i, j]), int(gg[i, j]), int(bb[i, j]))))
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
    dcrash = snap["d_crash"][0, e]
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
    fz = _bilerp_np(hf, dp[:, 0], dp[:, 1], ext)               # each drone's foot point on the terrain
    f3 = np.concatenate([dp[:, :2], fz[:, None]], -1)
    fscr, fdep = project(cam, f3)
    for k in range(dp.shape[0]):                               # RENDER-LOOP-OK
        if dcrash[k] > 0.5:                                    # FEATURE A: terrain/obstacle crash -> black ground spot
            items.append((fdep[k], "spot", tuple(fscr[k]), CRASH_C, 5))
        if dact[k] < 0.5 or da[k] < 0.5:
            continue                                           # not launched yet, OR dead (kamikaze -> vanish)
        items.append((ddep[k], "aline", (tuple(fscr[k]), tuple(dscr[k])), DRONE_C, 1))  # FEATURE B: altitude line
        items.append((ddep[k], "drone", tuple(dscr[k]), DRONE_C, 4))
    for _, kind, p, col, sz in sorted(items, key=lambda c: -c[0]):
        if kind == "box":
            dr.rectangle([p[0] - sz, p[1] - sz, p[0] + sz, p[1] + sz], fill=col, outline=(20, 20, 25))
        elif kind == "spot":
            dr.ellipse([p[0] - sz, p[1] - sz, p[0] + sz, p[1] + sz], fill=col)   # crash mark on the ground
        elif kind == "aline":
            dr.line([p[0], p[1]], fill=col, width=1)                             # cyan altitude line (foot -> drone)
        else:
            dr.ellipse([p[0] - sz, p[1] - sz, p[0] + sz, p[1] + sz], fill=col)
            dr.point([p[0], p[1]], fill=(255, 255, 255))
    E = ep.shape[0]
    kills = int(snap["kills"][0, e]); alive_d = int((da > 0.5).sum()); alive_e = int((ea > 0.5).sum())
    dr.text((6, 4), f"kills {kills}/{E}   drones {alive_d}   enemies {alive_e}", fill=(220, 226, 240))
    return img


def capture(env, dparams, dls, eparams, els, K_dec, H, stride=2, mm_dtype=None):
    def dfn(sf, tk, mk, ef, em, dm, dpxy, h_in):                 # recurrent GROUP drone (mean action + target assignment)
        mu, _, h_new, a_hard = RE.apply_recur(dparams, sf, tk, mk, ef, em, dm, dpxy, h_in, mm_dtype)
        return mu, h_new, a_hard
    efn = lambda sf, tk, mk: AT.apply_attn(eparams, sf, tk, mk, mm_dtype)[0]
    snaps = []
    game_loop(env, dfn, efn, 1, K_dec, record=snaps, record_stride=stride, drone_recur=True, latent_h=H)
    return snaps


def render(env, dparams, dls, eparams, els, K_dec, H, out_path, mm_dtype=None, n_panel=4, cols=2, cam_fn=None):
    # cam_fn: optional PER-PANEL camera animator. None -> one fixed make_camera(cfg) shared by every panel for
    #   the whole clip (fast path: each env's ground is projected exactly ONCE). If given,
    #   cam_fn(i, nfr, cfg, e, snap) returns a camera dict for panel e at frame i (of nfr) and may read `snap`
    #   (live entity positions) to auto-fit / track a moving subject -> so the ground must reproject every
    #   frame, per panel (each panel can now look through its OWN camera, not a shared one).
    from common.render_core import VideoWriter                # robust PyAV/libx264 writer (imageio.get_writer is broken here)
    cfg = env.cfg
    snaps = capture(env, dparams, dls, eparams, els, K_dec, H, mm_dtype=mm_dtype)  # sim device-agnostic; snaps are CPU
    hfs = env.hf.detach().cpu().numpy()                       # heightfields [N,G,G] on host
    obs = torch.cat([env.obst_xyz, env.obst_half, env.obst_cyl[..., None]], -1).detach().cpu().numpy()  # obstacle geom
    n_panel = min(n_panel, env.N)
    cols = min(cols, n_panel) if n_panel > 1 else 1; rows = (n_panel + cols - 1) // cols
    nfr = len(snaps)                                          # total frames -> gives cam_fn its 0..1 progress
    static = cam_fn is None                                   # static camera => render each env's ground exactly once
    if static:
        cam0 = make_camera(cfg)                               # single fixed viewpoint shared by all panels+frames
        bgs = [render_background(cfg, hfs[e], obs[e], cam0) for e in range(n_panel)]  # ground/obstacles: once per env
    w = VideoWriter(out_path, FPS)
    for i, snap in enumerate(snaps):                          # RENDER-LOOP-OK (frame loop, offline)
        grid = Image.new("RGB", (cols * PANEL_W, rows * PANEL_H), (0, 0, 0))
        for e in range(n_panel):                              # RENDER-LOOP-OK (per-panel composite)
            cam_e = cam0 if static else cam_fn(i, nfr, cfg, e, snap)                  # per-panel camera when animated
            bg_e  = bgs[e] if static else render_background(cfg, hfs[e], obs[e], cam_e)  # reproject ground if cam moved
            p = draw_frame(cfg, bg_e, hfs[e], snap, e, cam_e)
            grid.paste(p, ((e % cols) * PANEL_W, (e // cols) * PANEL_H))
        w.append_data(np.asarray(grid))
    w.close()
    return out_path
