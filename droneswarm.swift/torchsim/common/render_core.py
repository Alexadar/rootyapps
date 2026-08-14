"""common.render_core — the scenario-agnostic GPU rasterizer primitives + a robust MP4 writer.

Lifted verbatim out of arena/render_drone_torch.py so BOTH the arena combat "moviegen" AND the
cherrypick harvesting demo draw with the SAME batched z-buffer (single source of truth). The scene is
turned into a flat list of SCREEN-SPACE TRIANGLES and rasterized in one batched pass; per-primitive and
per-pixel loops are gone (only the offline frame/chunk loops remain — RENDER-LOOP-OK, not a sim hot path).

What lives here (generic): pinhole projection, quad->tri split, sprite/line quads, the bounding-box
z-buffer rasterizer (opaque + one transparent blend pass), a camera-dict->tensor packer, a flat colour
helper, static-mesh (terrain) quads, and AABB-box / trunk+crown obstacle geometry. What stays in a
scenario renderer: how a SNAPSHOT maps to entities (combat drones/enemies vs harvest drones/cherries),
the cameras' framing policy, HUD text, and the capture roll.

The MP4 writer uses PyAV (libx264) directly — it does NOT need imageio-ffmpeg (this box's base env ships
PyAV 17 but no ffmpeg binary, and imageio's v2 PyAV shim is broken here). Mirrors imageio's
get_writer/append_data/close so callers swap in with one line.
"""
import numpy as np
import torch

# --- obstacle + nav-overlay palette (moved from render_drone_torch; identical values -> identical look) ---
BUILD_C = (150, 142, 128)          # concrete grey building
TRUNK_C = (95, 70, 45)             # tree/branch trunk brown
TREE_C = (70, 160, 90)             # crown / foliage green (== render_drone.TREE_C)
NAV_OK = (46, 170, 78)             # dim GREEN  = allowed airspace (a state the drone may occupy)
NAV_NO = (200, 52, 44)             # RED        = forbidden (into the earth / inside an obstacle)
NAV_PATH = (90, 255, 130)          # bright SOLID GREEN = the flow PATH committed to right now
TRAIL_C = (255, 168, 40)           # ORANGE = each agent's ACTUAL flown trajectory (intent-vs-reality)
# 8 AABB corners (sign of each axis), bottom face 0-3 then top face 4-7:
_BOX_SIGNS = ((-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
              (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1))
_BOX_FACES = ((4, 5, 6, 7), (0, 1, 2, 3), (1, 2, 6, 5), (0, 3, 7, 4), (2, 3, 7, 6), (0, 1, 5, 4))  # top,bot,+x,-x,+y,-y
_BOX_BRIGHT = (1.0, 0.35, 0.74, 0.58, 0.68, 0.64)   # top brightest -> bottom darkest (cheap directional shade)


def _c(rgb, device):
    """(r,g,b) tuple -> [1,1,3] float tensor for broadcast."""
    return torch.tensor(rgb, dtype=torch.float32, device=device).reshape(1, 1, 3)


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
    """Thin screen-space quad from point a to point b (e.g. an altitude line: foot->drone). a/b [P,M,2]."""
    d = b_scr - a_scr                                                  # [P,M,2] segment direction
    n = torch.stack([-d[..., 1], d[..., 0]], -1)                       # [P,M,2] perpendicular
    n = n / n.norm(dim=-1, keepdim=True).clamp_min(1e-6) * width[..., None]   # unit-perp * half-width [P,M,2]
    quad = torch.stack([a_scr + n, b_scr + n, b_scr - n, a_scr - n], dim=2)  # [P,M,4,2]
    return quad, depth, valid


def _rasterize(tris, dep, col, valid, W, H, sky, chunk=None, alpha=None):
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

    # --- per-fragment alpha (1 = opaque). Two passes: paint OPAQUE nearest, then BLEND transparent over the scene. ---
    a_frag = (alpha.reshape(F)[tri] if alpha is not None else torch.ones(tot, device=dev))   # [tot] fragment alpha
    opaque = a_frag >= 0.999
    # PASS 1 -- opaque z-test: nearest OPAQUE depth per pixel, paint the winner.
    fd_op = torch.where(inside & opaque, d[tri], torch.full_like(d[tri], float("inf")))
    zbuf = torch.full((P * N,), float("inf"), device=dev)
    zbuf.scatter_reduce_(0, gpix, fd_op, reduce="amin", include_self=True)        # per-pixel nearest opaque depth
    win = inside & opaque & (fd_op <= zbuf[gpix] + 1e-4)                          # opaque fragments that own their pixel
    sky_flat[gpix[win]] = c[tri[win]]                                             # paint the scene
    # PASS 2 -- transparent: keep fragments IN FRONT of the opaque scene, blend the nearest one per pixel over it.
    if alpha is not None and bool((~opaque).any()):
        trans = inside & (~opaque) & (fd <= zbuf[gpix] + 1e-4)                    # in front of (or at) the scene depth
        fd_tr = torch.where(trans, fd, torch.full_like(fd, float("inf")))
        ztr = torch.full((P * N,), float("inf"), device=dev)
        ztr.scatter_reduce_(0, gpix, fd_tr, reduce="amin", include_self=True)     # nearest transparent depth per pixel
        wtr = trans & (fd_tr <= ztr[gpix] + 1e-4) & torch.isfinite(fd_tr)         # winning transparent fragment per pixel
        pix = gpix[wtr]; aw = a_frag[wtr][:, None]                                # blend: out = (1-a)*scene + a*colour
        sky_flat[pix] = (1.0 - aw) * sky_flat[pix] + aw * c[tri[wtr]]
    return sky_flat.reshape(P, H, W, 3).clamp(0, 255).to(torch.uint8)


def _terrain_quads(gx, gy, gzt, shade_col, eye, right, up, fwd, f, W, H):
    """Project a static ground grid and emit shaded quads. gx/gy/gzt [P,Gry,Grx] (RECTANGULAR ok -> a long
    narrow RIBBON strip when Grx>>Gry), shade_col [P,Gry-1,Grx-1,3]. A flat ground is just gzt = const."""
    P, Gry, Grx = gx.shape
    verts = torch.stack([gx, gy, gzt], -1).reshape(P, Gry * Grx, 3)     # [P,Gry*Grx,3] world verts
    scr, dep = _project(eye, right, up, fwd, f, W, H, verts)            # [P,Gry*Grx,2], [P,Gry*Grx]
    scr = scr.reshape(P, Gry, Grx, 2); dep = dep.reshape(P, Gry, Grx)   # back to grid
    a = scr[:, :-1, :-1]; b = scr[:, :-1, 1:]; c = scr[:, 1:, 1:]; d = scr[:, 1:, :-1]     # 4 corners [P,Gry-1,Grx-1,2]
    quad = torch.stack([a, b, c, d], dim=3).reshape(P, (Gry - 1) * (Grx - 1), 4, 2)        # [P,Q,4,2]
    da_ = dep[:, :-1, :-1]; db_ = dep[:, :-1, 1:]; dc_ = dep[:, 1:, 1:]; dd_ = dep[:, 1:, :-1]   # 4 corner depths
    qdep = (0.25 * (da_ + db_ + dc_ + dd_)).reshape(P, -1)                                 # mean depth
    qcol = shade_col.reshape(P, -1, 3)                                                     # [P,Q,3] precomputed shade
    # CULL any quad with a corner AT/BEHIND the near plane: such a quad straddles the camera and projects to
    # garbage that fills the frame. Harmless for normal renders (all ground is in front -> all corners dep>0);
    # required for a large SURROUND ground where part of the grid sits behind the eye.
    qval = ((da_ > 0.05) & (db_ > 0.05) & (dc_ > 0.05) & (dd_ > 0.05)).reshape(P, -1)
    return _quads_to_tris(quad, qdep, qcol, qval)


def _obstacle_tris(oc, oh, ocyl, omask, eye, right, up, fwd, f, W, H, device):
    """Obstacle geometry for one frame: BOXES as solid 6-FACE blocks (ocyl<0.5), CYLINDERS as a trunk
    billboard + crown sprite (ocyl>0.5). oc [P,O,3] centres, oh [P,O,3] half-extents, ocyl/omask [P,O].
    Real geometry with NO depth bias, so an agent behind a box is correctly occluded. Loop is 6 fixed faces."""
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

    base_c = torch.stack([oc[..., 0], oc[..., 1], oc[..., 2] - oh[..., 2]], -1)         # cyl bottom centre
    top_c = torch.stack([oc[..., 0], oc[..., 1], oc[..., 2] + oh[..., 2]], -1)          # cyl top centre
    bs, _bd = _project(eye, right, up, fwd, f, W, H, base_c)
    ts, td = _project(eye, right, up, fwd, f, W, H, top_c)
    trq, trd, trv = _line_quads(bs, ts, td, torch.full_like(td, 3.0), is_tree)          # trunk billboard
    trunk = _quads_to_tris(trq, trd, _c(TRUNK_C, device).expand(P, O, 3), trv)
    crq, crd, crv = _sprite_quads(ts, td, torch.full_like(td, 9.0), is_tree)            # crown sprite
    crown = _quads_to_tris(crq, crd, _c(TREE_C, device).expand(P, O, 3), crv)

    return (torch.cat([boxes[0], trunk[0], crown[0]], 1), torch.cat([boxes[1], trunk[1], crown[1]], 1),
            torch.cat([boxes[2], trunk[2], crown[2]], 1), torch.cat([boxes[3], trunk[3], crown[3]], 1))


# ----------------------------------------------------------------------------------------------------
# MP4 writer — PyAV/libx264 direct. Robust across environments (no imageio-ffmpeg dependency). Mirrors
# imageio's get_writer/append_data/close, so a caller swaps `imageio.get_writer(...)` -> `VideoWriter(...)`.
# ----------------------------------------------------------------------------------------------------
class VideoWriter:
    """Stream RGB uint8 frames to an H.264 MP4. Lazily sizes the stream to the FIRST frame (cropped to
    even width/height, which H.264 yuv420p requires). Frame arrays may be [H,W,3] uint8 (extra channels
    are dropped)."""
    def __init__(self, path, fps):
        import av                                                 # PyAV (this box: av 17, no ffmpeg binary needed)
        self._container = av.open(path, mode="w")
        self._stream = None
        self._fps = int(round(fps))
        self._av = av

    def append_data(self, frame):
        f = np.ascontiguousarray(np.asarray(frame)[..., :3]).astype(np.uint8)   # [H,W,3] RGB
        H = f.shape[0] - (f.shape[0] % 2); Wd = f.shape[1] - (f.shape[1] % 2)   # H.264 needs even dims
        f = f[:H, :Wd]
        if self._stream is None:                                   # lazily create the stream at first-frame size
            self._stream = self._container.add_stream("libx264", rate=self._fps)
            self._stream.width = Wd; self._stream.height = H; self._stream.pix_fmt = "yuv420p"
        vf = self._av.VideoFrame.from_ndarray(f, format="rgb24")
        for pkt in self._stream.encode(vf):
            self._container.mux(pkt)

    def close(self):
        if self._stream is not None:                              # flush the encoder's buffered frames
            for pkt in self._stream.encode():
                self._container.mux(pkt)
        self._container.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


def write_mp4(path, frames, fps):
    """Convenience: encode an iterable of RGB uint8 frames to an MP4 at `path`. Returns `path`."""
    w = VideoWriter(path, fps)
    for fr in frames:
        w.append_data(fr)
    w.close()
    return path
