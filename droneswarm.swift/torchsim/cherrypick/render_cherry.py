"""cherrypick.render_cherry — the harvest "moviegen". Reuses common.render_core's GPU rasterizer
primitives (projection, sprites, lines, boxes, z-buffer, MP4 writer) to draw the orchard scene:
ground, the brown wood (trunk + branches), the green leaf canopy, red cherries (which vanish off the
tree when picked and pile in the bucket when delivered), the bucket, the cyan drones with altitude
lines, their ORANGE flown trajectories, the quantized route-field DOTS (RED = forbidden / GREEN =
allowed airspace), and each drone's SOLID-GREEN committed path. Single fixed 3/4 camera, so all STATIC
geometry (ground, tree, field dots) is projected ONCE and only the moving entities are rebuilt per frame.
"""
import numpy as np
import torch
from PIL import Image, ImageDraw

from common.render_core import (_project, _sprite_quads, _line_quads, _quads_to_tris, _rasterize, _c,
                                _terrain_quads, VideoWriter, _BOX_SIGNS, _BOX_FACES, _BOX_BRIGHT,
                                NAV_OK, NAV_NO, NAV_PATH, TRAIL_C)

FPS = 30
SKY_TOP = (26, 32, 48); SKY_BOT = (66, 82, 110)
GROUND_C = (72, 104, 66)        # grassy ground
WOOD_C = (120, 82, 50)          # trunk + branch brown
LEAF_DARK = (36, 104, 52)       # foliage — shaded green
LEAF_LIGHT = (104, 184, 98)     # foliage — sunlit green (per-leaf shade lerps between the two)
STEM_C = (112, 80, 52)          # cherry stem brown
CHERRY_C = (228, 40, 52)        # ripe red
BUCKET_C = (232, 150, 60)       # bucket — warm orange so it pops against the green ground
DRONE_C = (95, 222, 255)        # cyan quad


def _cam(eye, center, W, H, fov_deg=48.0):
    """One fixed pinhole camera -> tensors (eye,right,up,fwd [1,3], f [1]) for the render_core projector."""
    eye = np.asarray(eye, np.float32); center = np.asarray(center, np.float32)
    up = np.array([0., 0., 1.], np.float32)
    fwd = center - eye; fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, up); right /= np.linalg.norm(right); up2 = np.cross(right, fwd)
    f = 0.5 * W / np.tan(np.radians(fov_deg) / 2.0)
    t = lambda a: torch.tensor(a, dtype=torch.float32)[None]
    return t(eye), t(right), t(up2), t(fwd), torch.tensor([f], dtype=torch.float32)


def _sprites(world_c, world_half, rgb, cam, W, H, device, bias=0.0, size_px=None):
    """Billboard sprites at world points, sized in WORLD units (px = f*half/depth) unless size_px given.
    world_c [M,3]; world_half scalar/[M]; -> (tris,dep,col,val) layer. Empty-safe."""
    eye, right, up, fwd, f = cam
    M = world_c.shape[0]
    if M == 0:
        z = torch.zeros(1, 0, device=device)
        return (torch.zeros(1, 0, 3, 2, device=device), z, torch.zeros(1, 0, 3, device=device),
                torch.zeros(1, 0, dtype=torch.bool, device=device))
    scr, dep = _project(eye, right, up, fwd, f, W, H, world_c[None])            # [1,M,2],[1,M]
    if size_px is not None:
        size = torch.full_like(dep, float(size_px))
    else:
        wh = world_half if torch.is_tensor(world_half) else torch.full_like(dep[0], float(world_half))
        size = (f[:, None] * wh[None] / dep).clamp(0.6, 240.0)
    q, qd, qv = _sprite_quads(scr, dep - bias, size, torch.ones_like(dep, dtype=torch.bool))
    col = _c(rgb, device).expand(1, M, 3)
    return _quads_to_tris(q, qd, col, qv)


def _boxes(centers, halfs, rgb, cam, W, H, device):
    """Solid 6-face shaded boxes (like render_core._obstacle_tris but a chosen colour). centers/halfs [O,3]."""
    eye, right, up, fwd, f = cam
    O = centers.shape[0]
    signs = torch.tensor(_BOX_SIGNS, dtype=torch.float32, device=device)
    corners = centers[:, None, :] + signs[None] * halfs[:, None, :]             # [O,8,3]
    cs, cd = _project(eye, right, up, fwd, f, W, H, corners.reshape(1, O * 8, 3))
    cs = cs.reshape(1, O, 8, 2); cd = cd.reshape(1, O, 8)
    base = torch.tensor(rgb, dtype=torch.float32, device=device)
    fq, fd, fc = [], [], []
    for face, bright in zip(_BOX_FACES, _BOX_BRIGHT):
        fi = list(face)
        fq.append(cs[:, :, fi, :]); fd.append(cd[:, :, fi].mean(-1))
        fc.append((base * bright)[None, None].expand(1, O, 3))
    val = torch.ones(1, O, dtype=torch.bool, device=device)
    return _quads_to_tris(torch.cat(fq, 1), torch.cat(fd, 1), torch.cat(fc, 1), torch.cat([val] * 6, 1))


def _polyline(pts, rgb, width_px, cam, W, H, device, bias=0.0):
    """Connected line segments through world points. pts [K,3] (single polyline) -> layer. Empty-safe."""
    eye, right, up, fwd, f = cam
    if pts.shape[0] < 2:
        z = torch.zeros(1, 0, device=device)
        return (torch.zeros(1, 0, 3, 2, device=device), z, torch.zeros(1, 0, 3, device=device),
                torch.zeros(1, 0, dtype=torch.bool, device=device))
    scr, dep = _project(eye, right, up, fwd, f, W, H, pts[None])                # [1,K,2],[1,K]
    a = scr[:, :-1]; b = scr[:, 1:]; d = 0.5 * (dep[:, :-1] + dep[:, 1:])       # [1,K-1,..]
    q, qd, qv = _line_quads(a, b, d - bias, torch.full_like(d, float(width_px)), torch.ones_like(d, dtype=torch.bool))
    return _quads_to_tris(q, qd, _c(rgb, device).expand(1, q.shape[1], 3), qv)


def _empty(device):
    z = torch.zeros(1, 0, device=device)
    return (torch.zeros(1, 0, 3, 2, device=device), z, torch.zeros(1, 0, 3, device=device),
            torch.zeros(1, 0, dtype=torch.bool, device=device))


def _tubes(segs, rgb, cam, W, H, device):
    """Tapering billboard TUBES for branches / cherry stems. segs [S,8] = (x0,y0,z0,x1,y1,z1,r0,r1);
    r are WORLD radii -> per-end pixel half-widths f*r/depth, so a limb thins toward its tip. Empty-safe."""
    eye, right, up, fwd, f = cam
    S = segs.shape[0]
    if S == 0:
        return _empty(device)
    p0 = segs[:, :3]; p1 = segs[:, 3:6]; r0 = segs[:, 6]; r1 = segs[:, 7]
    s0, d0 = _project(eye, right, up, fwd, f, W, H, p0[None])                   # [1,S,2],[1,S]
    s1, d1 = _project(eye, right, up, fwd, f, W, H, p1[None])
    w0 = (f[:, None] * r0[None] / d0).clamp(0.6, 140.0)                         # px half-width at each end
    w1 = (f[:, None] * r1[None] / d1).clamp(0.4, 140.0)
    dirc = s1 - s0
    n = torch.stack([-dirc[..., 1], dirc[..., 0]], -1)                          # screen-perp
    n = n / n.norm(dim=-1, keepdim=True).clamp_min(1e-6)
    quad = torch.stack([s0 + n * w0[..., None], s1 + n * w1[..., None],
                        s1 - n * w1[..., None], s0 - n * w0[..., None]], 2)      # [1,S,4,2] tapering trapezoid
    dep = 0.5 * (d0 + d1)
    val = torch.ones(1, S, dtype=torch.bool, device=device)
    return _quads_to_tris(quad, dep, _c(rgb, device).expand(1, S, 3), val)


def _foliage(pts, shades, world_half, cam, W, H, device):
    """Soft green FOLIAGE cloud: many small billboards with a per-leaf shade (dark<->light green), so the
    canopy reads as leaves, not blocks. pts [F,3], shades [F] in 0..1. Empty-safe."""
    eye, right, up, fwd, f = cam
    F = pts.shape[0]
    if F == 0:
        return _empty(device)
    scr, dep = _project(eye, right, up, fwd, f, W, H, pts[None])                # [1,F,2],[1,F]
    size = (f[:, None] * world_half / dep).clamp(0.8, 70.0)
    q, qd, qv = _sprite_quads(scr, dep, size, torch.ones_like(dep, dtype=torch.bool))
    lo = torch.tensor(LEAF_DARK, dtype=torch.float32, device=device)
    hi = torch.tensor(LEAF_LIGHT, dtype=torch.float32, device=device)
    col = lo.view(1, 1, 3) * (1 - shades.view(1, F, 1)) + hi.view(1, 1, 3) * shades.view(1, F, 1)   # [1,F,3]
    return _quads_to_tris(q, qd, col, qv)


def _cat(layers):
    """Concat a list of (tris,dep,col,val) layers along the primitive axis."""
    layers = [L for L in layers if L[0].shape[1] > 0]
    return (torch.cat([L[0] for L in layers], 1), torch.cat([L[1] for L in layers], 1),
            torch.cat([L[2] for L in layers], 1), torch.cat([L[3] for L in layers], 1))


# default camera: elevated, on the +x side past the branch, looking DOWN the branch->bucket corridor so
# the leaf-weaving is close in the foreground and the far bucket delivery stays in frame on the ground.
# LOW "from beneath" view: camera down near the ground looking UP into the crown, so the drones climbing
# to the dangling cherries are seen against the sky/canopy underside (not hidden behind the foliage).
CAM_EYE = (3.5, -13.0, 2.6); CAM_CENTER = (-0.5, 0.4, 5.8); CAM_FOV = 60.0
LEAF_SCALE = 0.95              # leaf billboard draw size (x half-extent); <1 keeps clumps distinct, not a blob


def render(frames, scn, stats, cfg, out_path, W=980, Hp=600, device=None,
           cam_eye=CAM_EYE, cam_center=CAM_CENTER, cam_fov=CAM_FOV, leaf_scale=LEAF_SCALE, one_frame=None):
    """Render the harvest to an MP4. `one_frame=i` instead returns a single frame's numpy image (for
    camera probing). Camera + leaf draw size are parameters so framing can be tuned without touching code."""
    device = device or ("cuda" if torch.cuda.is_available() else "cpu")
    scn = {k: (v.to(device) if torch.is_tensor(v) else v) for k, v in scn.items()}
    nav_xyz = stats["nav_xyz"].to(device); forbidden = stats["forbidden"].to(device)
    cam = tuple(t.to(device) for t in _cam(eye=cam_eye, center=cam_center, W=W, H=Hp, fov_deg=cam_fov))

    # --- STATIC layers (camera is fixed -> project once) ---------------------------------------------
    # ground as a GRID of quads (NOT one big quad): this rasterizer uses per-primitive flat depth, so a single
    # quad would hide everything farther than its centre (e.g. the far bucket). A grid gives each cell its own depth.
    ext = cfg.extent; GR = 26
    gl = torch.linspace(-ext, ext, GR, device=device)
    ggx, ggy = torch.meshgrid(gl, gl, indexing="xy")                           # [GR,GR] flat ground grid at z=0
    gzt = torch.zeros(1, GR, GR, device=device)
    shade = torch.tensor(GROUND_C, dtype=torch.float32, device=device).view(1, 1, 1, 3).expand(1, GR - 1, GR - 1, 3).contiguous()
    ground = _terrain_quads(ggx[None], ggy[None], gzt, shade, *cam, W, Hp)
    wood = _tubes(scn["wood_segs"], WOOD_C, cam, W, Hp, device)                # trunk + tapering branch tubes (organic)
    foliage = _foliage(scn["foliage_c"], scn["foliage_s"], 0.23, cam, W, Hp, device)   # soft green canopy cloud (small leaves)
    bucket = _boxes(scn["bucket"][None], torch.tensor([[1.05, 1.05, 0.95]], device=device), BUCKET_C, cam, W, Hp, device)
    # field DOTS: RED = obstacle-forbidden cells (tree volume, not the ground plane), GREEN = allowed (subsampled)
    cell_z = nav_xyz[..., 2]
    red_pts = nav_xyz[forbidden & (cell_z >= cfg.r_clear)]                      # forbidden AND above ground => a solid
    sub = torch.zeros_like(forbidden); sub[::3, ::3, ::3] = True                # every 3rd cell in each axis
    green_pts = nav_xyz[(~forbidden) & sub]                                     # sparse airspace cloud
    red_dots = _sprites(red_pts, None, NAV_NO, cam, W, Hp, device, size_px=1.3)
    green_dots = _sprites(green_pts, None, NAV_OK, cam, W, Hp, device, size_px=0.9)
    static = _cat([ground, red_dots, green_dots, wood, foliage, bucket])
    stem_top = scn["cherry_stem"]                                              # [M,3] branch anchor per cherry (for its stem)

    sky = (torch.tensor(SKY_TOP, dtype=torch.float32, device=device) * (1 - torch.linspace(0, 1, Hp, device=device)[:, None])
           + torch.tensor(SKY_BOT, dtype=torch.float32, device=device) * torch.linspace(0, 1, Hp, device=device)[:, None])
    sky = sky[:, None, :].expand(Hp, W, 3).contiguous()
    TRAIL = 34                                                                  # trajectory history length (frames)

    def _one(fi):
        fr = frames[fi]
        dp = fr["d_pos"].to(device); alive = fr["alive"]; D = dp.shape[0]; cst = fr["cstate"]
        live_i = alive.nonzero(as_tuple=True)[0].tolist()             # RENDER-LOOP-OK: per-drone polylines (offline)
        cpos = fr["cherry_pos"].to(device)
        # cherry STEMS: a thin brown pedicel from the branch anchor down to each cherry STILL ON THE TREE
        # (paired anchors -> the two cherries of a pair hang on a shared Y like in nature). Gone once picked.
        on_tree = ((cst == 0) | (cst == 1)).to(device)
        M = cpos.shape[0]
        stem_segs = torch.cat([stem_top, cpos, torch.full((M, 1), 0.03, device=device),
                               torch.full((M, 1), 0.018, device=device)], -1)[on_tree]
        stems = _tubes(stem_segs, STEM_C, cam, W, Hp, device)
        cherries = _sprites(cpos, 0.14, CHERRY_C, cam, W, Hp, device, bias=0.4)
        drones_live = _sprites(dp[alive], 0.22, DRONE_C, cam, W, Hp, device, bias=0.6)                 # cyan if alive
        drones_dead = _sprites(dp[~alive], 0.22, (125, 125, 135), cam, W, Hp, device, bias=0.6)        # grey if crashed
        foot = torch.stack([dp[:, 0], dp[:, 1], torch.zeros_like(dp[:, 0])], -1)
        alt_layers = [_polyline(torch.stack([dp[d], foot[d]], 0), (150, 170, 190), 1.0, cam, W, Hp, device, bias=0.3)
                      for d in live_i]                                # altitude line under each live drone
        path_layers = [_polyline(fr["paths"][d].to(device), NAV_PATH, 1.6, cam, W, Hp, device, bias=0.5) for d in live_i]
        j0 = max(0, fi - TRAIL)
        traj_layers = [_polyline(torch.stack([frames[j]["d_pos"][d] for j in range(j0, fi + 1)], 0).to(device),
                                 TRAIL_C, 0.9, cam, W, Hp, device, bias=0.4) for d in range(D)]
        layers = _cat([static, stems, cherries] + alt_layers + traj_layers + path_layers + [drones_live, drones_dead])
        frame = _rasterize(layers[0], layers[1], layers[2], layers[3], W, Hp, sky, chunk=64)
        img = Image.fromarray(frame[0].cpu().numpy(), "RGB"); dr = ImageDraw.Draw(img)
        deliv = int((cst == 3).sum()); carr = int((cst == 2).sum()); lost = int((cst == 4).sum()); alived = int(alive.sum())
        hud = f"cherry-pick  (NO AI, flow-field only)   bucket {deliv}/{stats['total']}   carrying {carr}   drones {alived}/{D}"
        if lost:
            hud += f"   lost {lost}"
        dr.text((10, 8), hud + f"   t={fi/FPS:4.1f}s", fill=(232, 236, 245))
        return np.asarray(img)

    if one_frame is not None:                                                  # probe mode: one frame -> image
        return _one(one_frame)
    w = VideoWriter(out_path, FPS)
    for fi in range(len(frames)):                                              # RENDER-LOOP-OK (offline frame loop)
        w.append_data(_one(fi))
    w.close()
    return out_path
    return out_path
