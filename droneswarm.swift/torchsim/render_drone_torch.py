"""render_drone_torch — a GPU (torch) rasterizer for the droneswarm "moviegen".

Why this exists: the PIL renderer (render_drone.py) draws every terrain quad and every sprite with a
single-core C polygon fill. With a MOVING / auto-fit camera the whole ground reprojects every frame, so
cost ~ (terrain_quads + sprites) * panels * frames on ONE cpu core -> minutes. Here we push the whole
thing onto the 3090: the scene is turned into a flat list of SCREEN-SPACE TRIANGLES (terrain mesh split
into 2 tris/quad, entity squares, altitude lines, crash spots) and rasterized with a batched z-buffer.

What is vectorized vs. what stays a loop (answering "can the for-loops be torch too?"):
  * Per-PRIMITIVE loops (882 terrain quads, per-drone / per-enemy draws)  -> GONE: pure tensor ops.
  * Per-PIXEL work (coverage + depth test for ALL pixels of ALL panels)  -> one batched tensor op.
  * The FRAME loop (~hundreds of frames) and the TRIANGLE-CHUNK loop      -> kept as Python loops on
    purpose. Collapsing frames into a tensor dim would need frames*panels*pixels*tris elements (petabytes);
    the chunk loop is a deliberate VRAM-bounding device. Both are OFFLINE (not the sim hot path) -> OK.

Visual parity vs. PIL: same sky gradient, height-shaded terrain, cyan drones + altitude lines, red/orange
enemy boxes, black crash spots, per-panel HUD text (the ONLY thing still drawn on cpu with PIL, because
it is a handful of tiny text blits per frame and GPU text is not worth it). Terrain grid outlines are
dropped (shading alone reads fine) — a minor, deliberate difference for speed.
"""
import numpy as np
import torch
from PIL import Image, ImageDraw

# reuse the proven pieces from the PIL renderer: colors, the terrain-height bilinear sampler, the capture
# (mean-action rollout -> per-frame CPU snapshots), and the numpy heightfield sampler for entity ground z.
from render_drone import (SKY_TOP, SKY_BOT, DRONE_C, CRASH_C, TANK_C, SOLDIER_C, ENEMY_DEAD, TREE_C, FPS,
                          _bilerp_np, capture)

# --- obstacle rendering palette + box topology (buildings drawn as solid 6-face blocks) ---
BUILD_C = (150, 142, 128)          # concrete grey building
TRUNK_C = (95, 70, 45)             # tree trunk brown
# 8 AABB corners (sign of each axis), bottom face 0-3 then top face 4-7:
_BOX_SIGNS = ((-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
              (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1))
_BOX_FACES = ((4, 5, 6, 7), (0, 1, 2, 3), (1, 2, 6, 5), (0, 3, 7, 4), (2, 3, 7, 6), (0, 1, 5, 4))  # top,bot,+x,-x,+y,-y
_BOX_BRIGHT = (1.0, 0.35, 0.74, 0.58, 0.68, 0.64)   # top brightest -> bottom darkest (cheap directional shade)


# ----------------------------------------------------------------------------------------------------
# Camera: a per-panel auto-fit "cinematic" camera. Each frame it frames the bbox of that env's ALIVE
# drones+enemies head-on -> auto-tracks AND auto-zooms (wide when swarm & enemies are ~60 m apart at
# launch, tight at the strike when they converge). EMA-smoothed per env to kill jitter. Pure numpy
# (negligible cost) -> returns plain camera dicts that we later stack into GPU tensors.
# ----------------------------------------------------------------------------------------------------
def autofit_cameras(snaps, hfs, cfg, W, H, pitch_deg=20.0, fov_deg=46.0, margin=1.30,
                    ema=0.16, dmin=15.0, dmax=82.0):
    """Return cams[nfr][P] = dict(eye,right,up,fwd,f) built by fitting each panel's live entities."""
    P = hfs.shape[0]
    ext = cfg.arena_half
    tan_h = np.tan(np.radians(fov_deg) / 2.0)          # horizontal half-FOV tangent (focal = 0.5*W/tan_h)
    tan_v = tan_h * (H / W)                             # vertical half-FOV tangent (aspect-corrected)
    cth, sth = np.cos(np.radians(pitch_deg)), np.sin(np.radians(pitch_deg))  # head-on view down-tilt
    st = {}                                            # per-env EMA state: e -> (center[3], dist)
    out = []
    for snap in snaps:                                 # RENDER-LOOP-OK (offline; per-frame camera solve)
        cams = []
        for e in range(P):                             # RENDER-LOOP-OK (P=9 tiny; per-panel bbox solve)
            dp = snap["d_pos"][0, e]; da = snap["d_alive"][0, e] > 0.5; dact = snap["d_act"][0, e] > 0.5
            ep = snap["e_pos"][0, e]; ea = snap["e_alive"][0, e] > 0.5
            pts = []
            m = da & dact                              # drones that are up and flying
            if m.any():
                pts.append(dp[m])
            elif da.any():
                pts.append(dp[da])                     # pre-launch: frame the spawn cluster
            if ea.any():                               # live enemies sit on the ground
                epa = ep[ea]; ez = _bilerp_np(hfs[e], epa[:, 0], epa[:, 1], ext)
                pts.append(np.concatenate([epa, ez[:, None]], -1))
            if pts:
                Pw = np.concatenate(pts, 0); lo = Pw.min(0); hi = Pw.max(0)
                c = 0.5 * (lo + hi)                    # bbox center = look-at
                xspan = hi[0] - lo[0]; zspan = hi[2] - lo[2]
                dist = margin * max(0.5 * xspan / tan_h, 0.5 * zspan / tan_v, 6.0)  # distance that fits BOTH axes
                dist = float(np.clip(dist, dmin, dmax))
            elif e in st:
                c, dist = st[e]                        # nobody left -> hold last pose
            else:
                c, dist = np.array([0., 0., 4.]), dmax
            if e in st:                                # temporal EMA smoothing
                c0, d0 = st[e]; c = c0 + ema * (c - c0); dist = d0 + ema * (dist - d0)
            st[e] = (c, dist)
            center = np.array([c[0], c[1], c[2]])
            eye = center + dist * np.array([0.0, -cth, sth])          # behind (-y) and above the subject
            up = np.array([0., 0., 1.]); fwd = center - eye; fwd /= np.linalg.norm(fwd)
            right = np.cross(fwd, up); right /= np.linalg.norm(right); up2 = np.cross(right, fwd)
            cams.append(dict(eye=eye, right=right, up=up2, fwd=fwd, f=0.5 * W / tan_h))
        out.append(cams)
    return out


def chase_cameras(snaps, hfs, cfg, W, H, fov_deg=55.0, ema=0.14, look_ahead=0.45,
                  back_base=13.0, back_k=0.50, back_lo=16.0, back_hi=50.0,
                  height_base=13.0, height_k=0.34, height_lo=16.0, height_hi=44.0):
    """Third-person CHASE camera per panel: sit BEHIND the swarm (opposite its travel direction) and ABOVE
    it, looking forward down the swarm->enemy axis toward the target. Two properties fix the "camera hides
    behind hills" problem of the head-on cam: (1) the eye is placed at terrain_height(eye_xy)+height, so it
    is ALWAYS above the local ground (never buried in a hill); (2) it looks DOWN-forward at a steep-ish
    angle, so any ridge between camera and swarm sits below the sightline. Pull-back distance scales with
    the swarm<->enemy separation -> wide chase early (60 m gap), tight chase at the strike. EMA-smoothed."""
    P = hfs.shape[0]
    ext = cfg.arena_half
    f = 0.5 * W / np.tan(np.radians(fov_deg) / 2.0)
    st = {}                                              # per-env EMA state: e -> dict(sc, ec, fxy)

    def terr(e, x, y):                                   # terrain height at a single world (x,y)
        return float(_bilerp_np(hfs[e], np.array([x]), np.array([y]), ext)[0])

    out = []
    for snap in snaps:                                   # RENDER-LOOP-OK (offline; per-frame camera solve)
        cams = []
        for e in range(P):                               # RENDER-LOOP-OK (P tiny; per-panel chase solve)
            dp = snap["d_pos"][0, e]; da = snap["d_alive"][0, e] > 0.5; dact = snap["d_act"][0, e] > 0.5
            ep = snap["e_pos"][0, e]; ea = snap["e_alive"][0, e] > 0.5
            prev = st.get(e)
            m = da & dact                                # swarm centroid: prefer flying drones
            if m.any():
                sc = dp[m].mean(0)
            elif da.any():
                sc = dp[da].mean(0)
            elif prev is not None:
                sc = prev["sc"]
            else:
                sc = np.array([-30., 0., 5.])            # cold fallback (left cell)
            if ea.any():                                 # enemy centroid on the ground
                epa = ep[ea]; ez = _bilerp_np(hfs[e], epa[:, 0], epa[:, 1], ext)
                ec = np.array([epa[:, 0].mean(), epa[:, 1].mean(), ez.mean()])
            elif prev is not None:
                ec = prev["ec"]
            else:
                ec = sc + np.array([20., 0., 0.])
            if prev is not None:                         # EMA-smooth the two centroids (kills jitter)
                sc = prev["sc"] + ema * (sc - prev["sc"]); ec = prev["ec"] + ema * (ec - prev["ec"])
            d_xy = ec[:2] - sc[:2]; sep = float(np.hypot(*d_xy))            # forward = swarm -> enemy (xy)
            fxy = d_xy / sep if sep > 1e-3 else (prev["fxy"] if prev is not None else np.array([1., 0.]))
            if prev is not None:                         # EMA-smooth the heading, then renormalize
                fxy = prev["fxy"] + ema * (fxy - prev["fxy"]); fxy = fxy / (np.linalg.norm(fxy) + 1e-9)
            st[e] = dict(sc=sc, ec=ec, fxy=fxy)

            back = float(np.clip(back_base + back_k * sep, back_lo, back_hi))     # pull back more when far apart
            height = float(np.clip(height_base + height_k * sep, height_lo, height_hi))
            eye_xy = sc[:2] - fxy * back                                          # behind the swarm
            eye_z = max(terr(e, eye_xy[0], eye_xy[1]), sc[2]) + height            # ABOVE local terrain AND swarm
            eye = np.array([eye_xy[0], eye_xy[1], eye_z])
            look_xy = sc[:2] + fxy * (sep * look_ahead)                           # aim ahead, between swarm & enemies
            look_at = np.array([look_xy[0], look_xy[1], terr(e, look_xy[0], look_xy[1]) + 2.0])
            up = np.array([0., 0., 1.]); fwd = look_at - eye; fwd /= np.linalg.norm(fwd)
            right = np.cross(fwd, up); right /= np.linalg.norm(right); up2 = np.cross(right, fwd)
            cams.append(dict(eye=eye, right=right, up=up2, fwd=fwd, f=f))
        out.append(cams)
    return out


def _cam_tensors(cams_frame, device):
    """Stack a frame's P camera dicts into batched tensors: eye/right/up/fwd [P,3], f [P]."""
    eye = torch.tensor(np.stack([c["eye"] for c in cams_frame]), dtype=torch.float32, device=device)
    right = torch.tensor(np.stack([c["right"] for c in cams_frame]), dtype=torch.float32, device=device)
    up = torch.tensor(np.stack([c["up"] for c in cams_frame]), dtype=torch.float32, device=device)
    fwd = torch.tensor(np.stack([c["fwd"] for c in cams_frame]), dtype=torch.float32, device=device)
    f = torch.tensor(np.array([c["f"] for c in cams_frame]), dtype=torch.float32, device=device)
    return eye, right, up, fwd, f


def _project(eye, right, up, fwd, f, W, H, pts):
    """Batched pinhole projection. eye/right/up/fwd [P,3], f [P], pts [P,M,3] -> screen [P,M,2], depth [P,M].
    Identical math to render_drone.project (sx = W/2 + f*x/z, sy = H/2 - f*y/z), just batched over panels."""
    rel = pts - eye[:, None, :]                        # [P,M,3] vector from eye to each world point
    x = (rel * right[:, None, :]).sum(-1)              # camera-space right coordinate  [P,M]
    y = (rel * up[:, None, :]).sum(-1)                 # camera-space up coordinate
    z = (rel * fwd[:, None, :]).sum(-1).clamp_min(1e-2)  # depth along view axis (clamp: no divide-by-0/behind)
    sx = 0.5 * W + f[:, None] * x / z                  # to screen pixels (x -> columns)
    sy = 0.5 * H - f[:, None] * y / z                  # (y up -> rows down, hence minus)
    return torch.stack([sx, sy], -1), z


def _quads_to_tris(quad_scr, quad_dep, quad_col, quad_val):
    """Split screen-space quads into 2 triangles each (fan 0-1-2, 0-2-3), carrying depth/color/validity.
    quad_scr [P,Q,4,2], quad_dep [P,Q], quad_col [P,Q,3], quad_val [P,Q]  ->  tris [P,2Q,3,2] + [P,2Q]*..."""
    t0 = quad_scr[:, :, [0, 1, 2], :]                  # first  triangle of each quad  [P,Q,3,2]
    t1 = quad_scr[:, :, [0, 2, 3], :]                  # second triangle
    tris = torch.cat([t0, t1], dim=1)                  # [P,2Q,3,2]
    dep = torch.cat([quad_dep, quad_dep], dim=1)       # both tris inherit the quad's flat depth
    col = torch.cat([quad_col, quad_col], dim=1)
    val = torch.cat([quad_val, quad_val], dim=1)
    return tris, dep, col, val


def _sprite_quads(center_scr, center_dep, size, valid):
    """Axis-aligned SCREEN-space square around each projected center (like PIL's dr.rectangle sprites).
    center_scr [P,M,2], center_dep [P,M], size [P,M] (px half-extent), valid [P,M] -> quad tensors [P,M,4,2]."""
    off = torch.tensor([[-1., -1.], [1., -1.], [1., 1.], [-1., 1.]], device=center_scr.device)  # [4,2] corner signs
    quad = center_scr[:, :, None, :] + off[None, None] * size[:, :, None, None]  # [P,M,4,2]
    return quad, center_dep, valid


def _line_quads(a_scr, b_scr, depth, width, valid):
    """Thin screen-space quad from point a to point b (drone altitude line: foot->drone). a/b [P,M,2]."""
    d = b_scr - a_scr                                                  # [P,M,2] segment direction
    n = torch.stack([-d[..., 1], d[..., 0]], -1)                       # [P,M,2] perpendicular
    n = n / n.norm(dim=-1, keepdim=True).clamp_min(1e-6) * width[..., None]   # unit-perp * half-width [P,M,2]
    quad = torch.stack([a_scr + n, b_scr + n, b_scr - n, a_scr - n], dim=2)  # [P,M,4,2]
    return quad, depth, valid


# ----------------------------------------------------------------------------------------------------
# The rasterizer: batched z-buffer over ALL panels at once. For each pixel we keep the NEAREST covering
# triangle (order-independent -> parallel-friendly, no painter sort). Coverage = 3 edge half-plane tests
# (accepts both windings). Triangles are processed in CHUNKS to bound VRAM (the only remaining loop, and
# it's a memory knob, not per-primitive iteration).
# ----------------------------------------------------------------------------------------------------
def _rasterize(tris, dep, col, valid, W, H, sky, chunk=None):
    """Bounding-box fragment rasterizer (batched z-buffer). tris [P,T,3,2] screen verts, dep [P,T],
    col [P,T,3] (0..255), valid [P,T] bool, sky [H,W,3]. Returns [P,H,W,3] uint8, nearest depth wins.

    Instead of testing every triangle against ALL N pixels (brute force = O(T*N), the slow version), each
    triangle only emits FRAGMENTS inside its own clipped screen bounding box -> total work ~ sum of bbox
    areas ~ O(covered pixels), independent of T. This is the whole speed-up (hundreds of x on a full-screen
    terrain). It stays loop-free: fragments for all triangles of all panels live in ONE flat array, addressed
    by prefix-sum offsets (repeat_interleave), and a single scatter_reduce does the depth test."""
    P, T = dep.shape
    dev = tris.device
    N = W * H
    F = P * T
    v = tris.reshape(F, 3, 2)                           # [F,3,2] all triangles flattened over panels
    d = torch.where(valid, dep, torch.full_like(dep, float("inf"))).reshape(F)   # invalid -> depth +inf
    c = col.reshape(F, 3).float()                       # [F,3]
    pan = torch.arange(P, device=dev).repeat_interleave(T)                        # [F] which panel each tri is in

    # integer screen bounding box per triangle, clipped to the panel; cull invalid/off-screen -> zero area.
    xmin = v[..., 0].amin(1); xmax = v[..., 0].amax(1)
    ymin = v[..., 1].amin(1); ymax = v[..., 1].amax(1)
    onscr = torch.isfinite(d) & (xmax >= 0) & (xmin <= W - 1) & (ymax >= 0) & (ymin <= H - 1)
    bx0 = xmin.floor().clamp(0, W - 1).long(); bx1 = xmax.ceil().clamp(0, W - 1).long()
    by0 = ymin.floor().clamp(0, H - 1).long(); by1 = ymax.ceil().clamp(0, H - 1).long()
    bw = torch.where(onscr, (bx1 - bx0 + 1).clamp(min=0), torch.zeros_like(bx0))  # bbox width  (0 if culled)
    bh = torch.where(onscr, (by1 - by0 + 1).clamp(min=0), torch.zeros_like(by0))  # bbox height (0 if culled)
    area = bw * bh                                      # [F] fragment count contributed by each triangle

    sky_flat = sky.reshape(1, N, 3).expand(P, N, 3).reshape(P * N, 3).clone().float()   # framebuffer = sky
    tot = int(area.sum().item())
    if tot == 0:
        return sky_flat.reshape(P, H, W, 3).clamp(0, 255).to(torch.uint8)

    # --- expand every triangle into its bbox fragments (all triangles at once, no per-tri loop) ---
    tri = torch.repeat_interleave(torch.arange(F, device=dev), area)              # [tot] source triangle per fragment
    offe = torch.cumsum(area, 0) - area                                           # [F] exclusive start offset
    within = torch.arange(tot, device=dev) - offe[tri]                            # [tot] index within this tri's bbox
    wtri = bw[tri]                                                                # [tot] bbox width of the tri
    dx = within % wtri; dy = within // wtri                                       # local pixel offset in bbox
    px = (bx0[tri] + dx).float(); py = (by0[tri] + dy).float()                    # absolute pixel center [tot]

    # --- coverage: 3 edge half-plane tests (accept both windings; projection can flip winding) ---
    v0 = v[tri, 0]; v1 = v[tri, 1]; v2 = v[tri, 2]                                # [tot,2] the tri's verts
    def edge(a, b):
        return (b[:, 0] - a[:, 0]) * (py - a[:, 1]) - (b[:, 1] - a[:, 1]) * (px - a[:, 0])   # signed area [tot]
    w0 = edge(v0, v1); w1 = edge(v1, v2); w2 = edge(v2, v0)
    inside = ((w0 >= 0) & (w1 >= 0) & (w2 >= 0)) | ((w0 <= 0) & (w1 <= 0) & (w2 <= 0))       # [tot] bool

    gpix = pan[tri] * N + (by0[tri] + dy) * W + (bx0[tri] + dx)                   # [tot] global pixel (panel-offset)
    fd = torch.where(inside, d[tri], torch.full_like(d[tri], float("inf")))       # [tot] fragment depth (inf if outside)

    # --- z-test: nearest depth per pixel via scatter-min, then paint the winning fragment's color ---
    zbuf = torch.full((P * N,), float("inf"), device=dev)
    zbuf.scatter_reduce_(0, gpix, fd, reduce="amin", include_self=True)           # per-pixel min depth
    win = inside & (fd <= zbuf[gpix] + 1e-4)                                      # fragments that own their pixel
    sky_flat[gpix[win]] = c[tri[win]]                                             # paint winners (ties: arbitrary)
    return sky_flat.reshape(P, H, W, 3).clamp(0, 255).to(torch.uint8)


# ----------------------------------------------------------------------------------------------------
# Scene assembly: turn a captured snapshot (+ static terrain) into the [P,T,...] triangle soup, per frame.
# ----------------------------------------------------------------------------------------------------
def _terrain_quads(gx, gy, gzt, shade_col, eye, right, up, fwd, f, W, H):
    """Project the static terrain grid and emit shaded quads. gx/gy/gzt [P,Gry,Grx] (RECTANGULAR ok -> a long
    narrow RIBBON strip when Grx>>Gry), shade_col [P,Gry-1,Grx-1,3]."""
    P, Gry, Grx = gx.shape
    verts = torch.stack([gx, gy, gzt], -1).reshape(P, Gry * Grx, 3)     # [P,Gry*Grx,3] world verts
    scr, dep = _project(eye, right, up, fwd, f, W, H, verts)            # [P,Gry*Grx,2], [P,Gry*Grx]
    scr = scr.reshape(P, Gry, Grx, 2); dep = dep.reshape(P, Gry, Grx)   # back to grid
    a = scr[:, :-1, :-1]; b = scr[:, :-1, 1:]; c = scr[:, 1:, 1:]; d = scr[:, 1:, :-1]     # 4 corners [P,Gry-1,Grx-1,2]
    quad = torch.stack([a, b, c, d], dim=3).reshape(P, (Gry - 1) * (Grx - 1), 4, 2)        # [P,Q,4,2]
    qdep = (0.25 * (dep[:, :-1, :-1] + dep[:, :-1, 1:] + dep[:, 1:, 1:] + dep[:, 1:, :-1])).reshape(P, -1)  # mean depth
    qcol = shade_col.reshape(P, -1, 3)                                                     # [P,Q,3] precomputed shade
    qval = torch.ones(P, quad.shape[1], dtype=torch.bool, device=quad.device)
    return _quads_to_tris(quad, qdep, qcol, qval)


def _entity_tris(snap, hfs_t, ext, eye, right, up, fwd, f, W, H, device):
    """Build entity triangles for one frame: enemy boxes, drone dots, altitude lines, crash spots."""
    P = hfs_t.shape[0]
    dp = torch.tensor(snap["d_pos"][0], dtype=torch.float32, device=device)     # [P,D,3] drone world pos
    da = torch.tensor(snap["d_alive"][0], dtype=torch.float32, device=device) > 0.5
    dact = torch.tensor(snap["d_act"][0], dtype=torch.float32, device=device) > 0.5
    dcr = torch.tensor(snap["d_crash"][0], dtype=torch.float32, device=device) > 0.5
    ep2 = torch.tensor(snap["e_pos"][0], dtype=torch.float32, device=device)    # [P,E,2] enemy ground pos
    ea = torch.tensor(snap["e_alive"][0], dtype=torch.float32, device=device) > 0.5
    et = torch.tensor(snap["e_type"], dtype=torch.float32, device=device) > 0.5  # [P,E] tank flag

    # --- drones: project the drone body AND its foot (same x,y, on the terrain) for the altitude line ---
    dscr, ddep = _project(eye, right, up, fwd, f, W, H, dp)                     # body [P,D,2],[P,D]
    fz = _bilerp_t(hfs_t, dp[..., 0], dp[..., 1], ext)                          # foot height under each drone
    foot = torch.stack([dp[..., 0], dp[..., 1], fz], -1)
    fscr, fdep = _project(eye, right, up, fwd, f, W, H, foot)                   # foot [P,D,2],[P,D]
    live = da & dact                                                            # drawn only if up & alive

    # --- enemies: project on the ground; alive -> type color, dead -> gray (always drawn, like PIL) ---
    ez = _bilerp_t(hfs_t, ep2[..., 0], ep2[..., 1], ext)
    e3 = torch.stack([ep2[..., 0], ep2[..., 1], ez], -1)
    escr, edep = _project(eye, right, up, fwd, f, W, H, e3)                     # [P,E,2],[P,E]

    tris_list, dep_list, col_list, val_list = [], [], [], []

    def add_quads(quad, qdep, qcol, qval):
        t, d, c, v = _quads_to_tris(quad, qdep, qcol, qval)
        tris_list.append(t); dep_list.append(d); col_list.append(c); val_list.append(v)

    # DEPTH BIAS: entities sit ON (enemies, crash decals) or above (drones) the terrain, so their flat
    # sprite depth ties with the terrain quad they cover -> the z-test can let the ground WIN and hide them
    # (classic decal z-fight). Pull entity depth a bit toward the camera so they reliably beat their own
    # ground cell, while a genuinely-nearer hill (> the bias) still occludes them correctly. Crash marks are
    # pure ground decals -> a stronger bias so an "earth-hit" is never swallowed by the terrain.
    BIAS = 0.8; BIAS_CRASH = 2.5

    # enemy boxes (size 7 tanks / 5 soldiers)
    esz = torch.where(et, torch.full_like(edep, 7.0), torch.full_like(edep, 5.0))
    ecol = torch.where(ea[..., None], torch.where(et[..., None], _c(TANK_C, device), _c(SOLDIER_C, device)),
                       _c(ENEMY_DEAD, device))                                   # [P,E,3]
    q, qd, qv = _sprite_quads(escr, edep - BIAS, esz, torch.ones_like(ea))
    add_quads(q, qd, ecol, qv)

    # crash spots (black ground marks under crashed drones) — bigger + strong decal bias so they're visible
    q, qd, qv = _sprite_quads(fscr, fdep - BIAS_CRASH, torch.full_like(fdep, 8.0), dcr)
    add_quads(q, qd, _c(CRASH_C, device).expand(P, dp.shape[1], 3), qv)

    # altitude lines (foot -> drone, cyan, thin)
    q, qd, qv = _line_quads(fscr, dscr, ddep - BIAS, torch.full_like(ddep, 1.2), live)
    add_quads(q, qd, _c(DRONE_C, device).expand(P, dp.shape[1], 3), qv)

    # drone dots (cyan squares)
    q, qd, qv = _sprite_quads(dscr, ddep - BIAS, torch.full_like(ddep, 4.0), live)
    add_quads(q, qd, _c(DRONE_C, device).expand(P, dp.shape[1], 3), qv)

    tris = torch.cat(tris_list, dim=1); dep = torch.cat(dep_list, dim=1)
    col = torch.cat(col_list, dim=1); val = torch.cat(val_list, dim=1)
    return tris, dep, col, val


def _c(rgb, device):
    """(r,g,b) tuple -> [1,1,3] float tensor for broadcast."""
    return torch.tensor(rgb, dtype=torch.float32, device=device).reshape(1, 1, 3)


def _bilerp_t(hf, x, y, ext):
    """Torch bilinear terrain sampler (batched over panels). hf [P,G,G], x/y [P,M] -> [P,M] heights."""
    P, G, _ = hf.shape
    gx = ((x / ext + 1) * 0.5 * (G - 1)).clamp(0, G - 1)
    gy = ((y / ext + 1) * 0.5 * (G - 1)).clamp(0, G - 1)
    ix = gx.floor().long().clamp(0, G - 2); tx = gx - ix
    iy = gy.floor().long().clamp(0, G - 2); ty = gy - iy
    bidx = torch.arange(P, device=hf.device)[:, None]                          # [P,1] per-panel index
    h00 = hf[bidx, iy, ix]; h10 = hf[bidx, iy, ix + 1]
    h01 = hf[bidx, iy + 1, ix]; h11 = hf[bidx, iy + 1, ix + 1]
    return h00 * (1 - tx) * (1 - ty) + h10 * tx * (1 - ty) + h01 * (1 - tx) * ty + h11 * tx * ty


def _obstacle_tris(oc, oh, ocyl, omask, eye, right, up, fwd, f, W, H, device):
    """Obstacle geometry for one frame: buildings as solid 6-FACE boxes, trees as a trunk billboard + crown
    sprite. oc [P,O,3] centres, oh [P,O,3] half-extents, ocyl/omask [P,O]. Real geometry with NO depth bias,
    so a drone/enemy behind a building is correctly occluded by the z-buffer. Loop is 6 fixed faces only."""
    P, O, _ = oc.shape
    is_box = ((ocyl < 0.5) & (omask > 0.5))                       # [P,O] draw box faces
    is_tree = ((ocyl > 0.5) & (omask > 0.5))                      # [P,O] draw trunk + crown
    signs = torch.tensor(_BOX_SIGNS, dtype=torch.float32, device=device)                # [8,3] AABB corners
    corners = oc[:, :, None, :] + signs[None, None] * oh[:, :, None, :]                  # [P,O,8,3]
    cs, cd = _project(eye, right, up, fwd, f, W, H, corners.reshape(P, O * 8, 3))
    cs = cs.reshape(P, O, 8, 2); cd = cd.reshape(P, O, 8)
    base = torch.tensor(BUILD_C, dtype=torch.float32, device=device)                    # [3]
    fq, fd, fc, fv = [], [], [], []
    for face, bright in zip(_BOX_FACES, _BOX_BRIGHT):            # 6 faces (RENDER-LOOP-OK, fixed & tiny)
        fi = list(face)
        fq.append(cs[:, :, fi, :])                              # [P,O,4,2] face quad
        fd.append(cd[:, :, fi].mean(-1))                        # [P,O] face depth (flat)
        fc.append((base * bright)[None, None].expand(P, O, 3))  # directionally-shaded face color
        fv.append(is_box)
    boxes = _quads_to_tris(torch.cat(fq, 1), torch.cat(fd, 1), torch.cat(fc, 1), torch.cat(fv, 1))

    base_c = torch.stack([oc[..., 0], oc[..., 1], oc[..., 2] - oh[..., 2]], -1)         # tree bottom centre
    top_c = torch.stack([oc[..., 0], oc[..., 1], oc[..., 2] + oh[..., 2]], -1)          # tree top centre
    bs, _bd = _project(eye, right, up, fwd, f, W, H, base_c)
    ts, td = _project(eye, right, up, fwd, f, W, H, top_c)
    trq, trd, trv = _line_quads(bs, ts, td, torch.full_like(td, 3.0), is_tree)          # trunk billboard
    trunk = _quads_to_tris(trq, trd, _c(TRUNK_C, device).expand(P, O, 3), trv)
    crq, crd, crv = _sprite_quads(ts, td, torch.full_like(td, 9.0), is_tree)            # crown sprite
    crown = _quads_to_tris(crq, crd, _c(TREE_C, device).expand(P, O, 3), crv)

    return (torch.cat([boxes[0], trunk[0], crown[0]], 1), torch.cat([boxes[1], trunk[1], crown[1]], 1),
            torch.cat([boxes[2], trunk[2], crown[2]], 1), torch.cat([boxes[3], trunk[3], crown[3]], 1))


# ----------------------------------------------------------------------------------------------------
# Explosions: a brief expanding bright burst at each IMPACT — an enemy dying (kamikaze kill, orange/yellow)
# or a drone hitting the terrain (earth-hit, grey puff). Events are detected by scanning consecutive
# snapshots for alive/crash TRANSITIONS (offline), then each spawns a sprite that lives `life` frames,
# growing and fading with age. Drawn strongly biased toward the camera so the flash sits on top.
# ----------------------------------------------------------------------------------------------------
def _explosion_events(snaps, hfs, ext):
    """Scan snapshots for impact transitions -> (frame_idx, panel, world_pos[3], kind) arrays. kind 0=kill, 1=crash."""
    fr, pn, ps, kd = [], [], [], []
    P = hfs.shape[0]
    for i in range(1, len(snaps)):                       # RENDER-LOOP-OK (offline; transition scan)
        a, b = snaps[i - 1], snaps[i]
        died = (a["e_alive"][0][:P] > 0.5) & (b["e_alive"][0][:P] <= 0.5)         # enemy alive -> dead this frame
        ep = b["e_pos"][0][:P]
        for p, e in zip(*np.nonzero(died)):                                       # RENDER-LOOP-OK (few events)
            x, y = float(ep[p, e, 0]), float(ep[p, e, 1])
            fr.append(i); pn.append(p); ps.append([x, y, float(_bilerp_np(hfs[p], np.array([x]), np.array([y]), ext)[0])]); kd.append(0)
        crashed = (a["d_crash"][0][:P] <= 0.5) & (b["d_crash"][0][:P] > 0.5)       # drone crash ONSET this frame
        dp = b["d_pos"][0][:P]
        for p, d in zip(*np.nonzero(crashed)):                                     # RENDER-LOOP-OK (few events)
            x, y = float(dp[p, d, 0]), float(dp[p, d, 1])
            fr.append(i); pn.append(p); ps.append([x, y, float(_bilerp_np(hfs[p], np.array([x]), np.array([y]), ext)[0])]); kd.append(1)
    return (np.array(fr, np.int64), np.array(pn, np.int64),
            np.array(ps, np.float32).reshape(-1, 3), np.array(kd, np.int64))


def _explosion_tris(events, i, life, eye, right, up, fwd, f, W, H, P, device):
    """Build explosion sprites active at frame i (age in [0,life)). Returns (tris,dep,col,val) or None."""
    fr, pn, ps, kd = events
    if fr.size == 0:
        return None
    active = np.nonzero((fr <= i) & (fr > i - life))[0]                            # events currently burning
    if active.size == 0:
        return None
    counts = np.bincount(pn[active], minlength=P); Kmax = int(counts.max())        # pad to max bursts on any panel
    if Kmax == 0:
        return None
    pos = np.zeros((P, Kmax, 3), np.float32); age = np.zeros((P, Kmax), np.float32)
    kind = np.zeros((P, Kmax), np.float32); val = np.zeros((P, Kmax), bool)
    slot = np.zeros(P, np.int64)
    for j in active:                                     # RENDER-LOOP-OK (few active bursts; slot per panel)
        p = int(pn[j]); s = int(slot[p]); slot[p] = s + 1
        pos[p, s] = ps[j]; age[p, s] = i - fr[j]; kind[p, s] = kd[j]; val[p, s] = True
    pos_t = torch.tensor(pos, device=device); age_t = torch.tensor(age, device=device)
    kind_t = torch.tensor(kind, device=device); val_t = torch.tensor(val, device=device)
    scr, dep = _project(eye, right, up, fwd, f, W, H, pos_t)                       # [P,Kmax,2],[P,Kmax]
    a = age_t / max(1, life - 1)                                                   # normalized age 0..1
    size = torch.where(kind_t < 0.5, 6.0 + age_t * 5.0, 4.0 + age_t * 2.0)         # kills bloom big, crashes small
    kill = torch.stack([255 - 25 * a, 235 - 130 * a, 150 - 120 * a], -1)           # yellow-white -> orange fade
    puff = torch.stack([80 - 24 * a, 80 - 24 * a, 92 - 24 * a], -1)                # grey earth-hit puff
    col = torch.where(kind_t[..., None] < 0.5, kill, puff)
    q, qd, qv = _sprite_quads(scr, dep - 3.0, size, val_t)                         # strong bias -> flash on top
    return _quads_to_tris(q, qd, col, qv)


# ----------------------------------------------------------------------------------------------------
# Top-level: capture -> per-frame GPU rasterize -> HUD text (cpu) -> mp4.
# ----------------------------------------------------------------------------------------------------
def render_torch(env, dparams, dls, eparams, els, K_dec, H, out_path, W=1280, Hp=280, n_panel=9, cols=1,
                 device="cuda", chunk=48, mm_dtype=None, Gr=22, cam_kw=None, cam_mode="autofit",
                 max_seconds=60.0, end_hold=0.8, explo_life=6, ribbon_y=None):
    import imageio.v2 as imageio
    cfg = env.cfg
    dev = device if torch.cuda.is_available() else "cpu"
    snaps = capture(env, dparams, dls, eparams, els, K_dec, H, mm_dtype=mm_dtype)   # CPU snapshots (mean-action roll)
    hfs = env.hf.detach().cpu().numpy()[:n_panel]                                   # [P,G,G] heightfields
    P = hfs.shape[0]

    # --- END CONDITION: stop when EVERY env is terminal (one side wiped -> no enemies OR no drones left) plus
    #     a short hold so the finish isn't abrupt; hard-capped at max_seconds. A drone-side wipe (all drones
    #     kamikaze'd/crashed) counts as terminal too, so stalemates still end. ---
    max_frames = int(max_seconds * FPS)
    Dn = snaps[0]["d_act"].shape[2]                                                  # drones per env
    term = None
    for i, s in enumerate(snaps):                                                   # RENDER-LOOP-OK (offline scan)
        ae = (s["e_alive"][0][:P] > 0.5).sum(1)                                      # [P] alive enemies per env
        ad = (s["d_alive"][0][:P] > 0.5).sum(1)                                      # [P] alive (launched, live) drones
        launched = (s["d_act"][0][:P] > 0.5).sum(1)                                  # [P] drones DEPLOYED so far (monotonic)
        # decided = enemies wiped, OR every drone has deployed AND none are left (a drone-side wipe). The
        # `launched==D` guard is essential: drones launch STAGGERED, so `ad==0` early just means "not launched
        # yet", not "all dead" — without it the clip ends at frame 0.
        decided = (ae == 0) | ((launched == Dn) & (ad == 0))
        if bool(decided.all()):
            term = i; break
    end = min(term + int(end_hold * FPS), max_frames, len(snaps)) if term is not None else min(len(snaps), max_frames)
    snaps = snaps[:max(end, 1)]                                                      # trim the clip
    print(f"[render_torch] clip ends at frame {len(snaps)}/{max_frames}cap "
          f"({'all envs decided' if term is not None else 'time cap / roll end'}); "
          f"{'%.1fs' % (len(snaps) / FPS)}")

    ncrash = int((snaps[-1]["d_crash"][0][:P] > 0.5).sum())                          # sticky earth-hit flags at end
    print(f"[render_torch] earth-hits (drones that hit terrain): {ncrash} across {P} envs, "
          f"{P * snaps[-1]['d_pos'].shape[2]} drones")
    events = _explosion_events(snaps, hfs, cfg.arena_half)                           # impact bursts (kills + crashes)
    print(f"[render_torch] explosions: {events[0].size} impacts "
          f"({int((events[3] == 0).sum())} kills, {int((events[3] == 1).sum())} earth-hits)")
    cam_solver = chase_cameras if cam_mode == "chase" else autofit_cameras          # pick the camera style
    cams = cam_solver(snaps, hfs, cfg, W, Hp, **(cam_kw or {}))                      # per-frame per-panel cameras
    ext = cfg.arena_half

    # --- static per-panel terrain grid (world coords + precomputed height shading) built ONCE ---
    # RIBBON MAP: when ribbon_y is set, the terrain is a LONG NARROW STRIP (x spans the full arena, y only
    # +/- ribbon_y) with roughly square cells -> the rendered ground itself is a ribbon, not a square field.
    if ribbon_y is not None:
        Grx = Gr; Gry = max(3, 1 + round((Gr - 1) * ribbon_y / ext))               # narrow in y, long in x
        axx = np.linspace(-ext, ext, Grx); ayy = np.linspace(-ribbon_y, ribbon_y, Gry)
    else:
        Grx = Gry = Gr; axx = ayy = np.linspace(-ext, ext, Gr)                      # square (default)
    gxn, gyn = np.meshgrid(axx, ayy)                                               # [Gry,Grx] (same grid all panels)
    gx = torch.tensor(np.broadcast_to(gxn, (P, Gry, Grx)).copy(), dtype=torch.float32, device=dev)
    gy = torch.tensor(np.broadcast_to(gyn, (P, Gry, Grx)).copy(), dtype=torch.float32, device=dev)
    gzt_np = np.stack([_bilerp_np(hfs[i], gxn, gyn, ext) for i in range(P)])        # [P,Gry,Grx] terrain height (per panel)
    gzt = torch.tensor(gzt_np, dtype=torch.float32, device=dev)
    z_q = 0.25 * (gzt[:, :-1, :-1] + gzt[:, :-1, 1:] + gzt[:, 1:, 1:] + gzt[:, 1:, :-1])  # per-quad mean height
    shade = (0.45 + 0.55 * (z_q / (cfg.terrain_amp + 1e-6)))                        # height shading [P,Gr-1,Gr-1]
    shade_col = torch.stack([60 * shade + 30, 110 * shade + 40, 70 * shade + 30], -1)     # [P,Gr-1,Gr-1,3]
    hfs_t = torch.tensor(hfs, dtype=torch.float32, device=dev)
    oc_t = env.obst_xyz[:P].to(dev); oh_t = env.obst_half[:P].to(dev)        # static obstacle geometry (per panel)
    ocyl_t = env.obst_cyl[:P].to(dev); omask_t = env.obst_mask[:P].to(dev)

    # --- sky gradient (constant) ---
    t = torch.linspace(0, 1, Hp, device=dev)[:, None]
    top = torch.tensor(SKY_TOP, dtype=torch.float32, device=dev); bot = torch.tensor(SKY_BOT, dtype=torch.float32, device=dev)
    sky = (top * (1 - t) + bot * t)[:, None, :].expand(Hp, W, 3).contiguous()       # [Hp,W,3]

    rows = (P + cols - 1) // cols
    w = imageio.get_writer(out_path, fps=FPS, macro_block_size=None)
    for fi, snap in enumerate(snaps):                       # RENDER-LOOP-OK (offline frame loop; per-frame GPU raster)
        eye, right, up, fwd, f = _cam_tensors(cams[fi], dev)
        tt, td, tc, tv = _terrain_quads(gx, gy, gzt, shade_col, eye, right, up, fwd, f, W, Hp)   # terrain tris
        et, ed, ec, ev = _entity_tris(snap, hfs_t, ext, eye, right, up, fwd, f, W, Hp, dev)      # entity tris
        ob = _obstacle_tris(oc_t, oh_t, ocyl_t, omask_t, eye, right, up, fwd, f, W, Hp, dev)      # buildings + trees
        layers = [(tt, td, tc, tv), ob, (et, ed, ec, ev)]
        ex = _explosion_tris(events, fi, explo_life, eye, right, up, fwd, f, W, Hp, P, dev)      # impact bursts (if any)
        if ex is not None:
            layers.append(ex)
        tris = torch.cat([L[0] for L in layers], 1); dep = torch.cat([L[1] for L in layers], 1)
        col = torch.cat([L[2] for L in layers], 1); val = torch.cat([L[3] for L in layers], 1)
        frame = _rasterize(tris, dep, col, val, W, Hp, sky, chunk=chunk)            # [P,Hp,W,3] uint8 on GPU
        grid_np = _compose(frame.cpu().numpy(), snap, P, rows, cols, W, Hp)         # tile panels + HUD text (cpu)
        w.append_data(grid_np)
    w.close()
    return out_path


def _compose(frames, snap, P, rows, cols, W, Hp):
    """Tile the P panels into one image and blit per-panel HUD text (kills/drones/enemies) with PIL (cheap)."""
    grid = Image.new("RGB", (cols * W, rows * Hp), (0, 0, 0))
    dr = ImageDraw.Draw(grid)
    for e in range(P):                                      # RENDER-LOOP-OK (P tiny; paste + 1 text blit each)
        ox, oy = (e % cols) * W, (e // cols) * Hp
        grid.paste(Image.fromarray(frames[e], "RGB"), (ox, oy))
        E = snap["e_pos"].shape[2]
        kills = int(snap["kills"][0, e])
        ad = int((snap["d_alive"][0, e] > 0.5).sum()); ae = int((snap["e_alive"][0, e] > 0.5).sum())
        dr.text((ox + 6, oy + 4), f"kills {kills}/{E}   drones {ad}   enemies {ae}", fill=(220, 226, 240))
    return np.asarray(grid)
