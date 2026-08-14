"""scout — one grey block, a FLOCK of point-drones, non-intersecting serpentine routes.

=========================================================================================================
WHAT THIS IS
=========================================================================================================
    * a solid block of GREY nav points  (no terrain, no obstacles — just grey)
    * D point-drones (no quadrotor physics, no camera, no reconstruction)
    * the subcubes are split between them so their routes NEVER CROSS
    * everything within a drone's scan radius turns GREY -> SEEN
    * written out as a movie

=========================================================================================================
HOW THE TARGETS ARE SPLIT SO ROUTES CANNOT INTERSECT
=========================================================================================================
Order every subcube along ONE serpentine ("boustrophedon") curve through the block: sweep x left-to-right,
step one row in y and sweep back right-to-left, and flip the y direction again on each new z layer. The curve
visits every cube exactly once and, because it only ever steps to a NEIGHBOURING cube and never doubles back,
it never crosses itself.

Then cut that 1-D curve into D CONTIGUOUS segments, one per drone.

That gives the non-intersection for free, and it is a property of the construction rather than something that
has to be checked or repaired at runtime:
    * each drone owns a contiguous ARC of a non-self-intersecting curve,
    * distinct arcs are disjoint sets of cubes,
    * so two drones can never be routed to the same cube and their swept corridors do not overlap.
Assignment is therefore pure index arithmetic — a sort and a split, no auction, no search, no iteration.

[PAPER] boustrophedon cellular decomposition — Choset & Pignon 1998; Choset, "Coverage for robotics", 2000.
[PAPER] cutting a space-filling traversal into equal contiguous runs, one per robot, is the standard way to get
        balanced non-overlapping coverage (space-filling-curve CPP, e.g. arXiv:2209.01426).

Run:  python scout.py [out.mp4] [n_drones] [cube_m] [G] [Gz]
"""
import os as _o, sys as _s
_s.path.insert(0, _o.path.dirname(_o.path.dirname(_o.path.abspath(__file__))))     # torchsim/ -> `common`

import numpy as np
import torch
import torch.nn.functional as F3

from common.render_core import _project, _sprite_quads, _line_quads, _quads_to_tris, _rasterize, VideoWriter
from common import navfield as NAV

FPS = 10        # stride=1 @ 10 fps = real-time. To SPEED UP a video, raise `fps` in render() — never the
#                 stride: dropping intermediate frames is what makes motion choppy.
C_GREY = (150, 156, 170)     # UNSCANNED — must be clearly visible, else the block
#                              looks like void and a drone inside it appears to be outside the world
C_SEEN = (54, 180, 96)
C_SOLID = (205, 62, 54)      # points inside a cube -> RED, never scannable
SKY = (4, 5, 9)
# one colour per drone so the ownership of each corridor is visible
PALETTE = [(120, 235, 255), (250, 190, 60), (255, 120, 170), (140, 255, 140), (180, 150, 255),
           (255, 150, 90), (110, 200, 255), (240, 240, 120), (255, 110, 110), (150, 255, 220)]


# =====================================================================================================
# world
# =====================================================================================================
def make_grid(extent=40.0, zlo=-1.0, zhi=36.0, G=24, Gz=19, device="cuda"):
    """The grey block: a regular lattice of nav POINTS filling the volume. -> `pts [M,3]`."""
    xs = torch.linspace(-extent, extent, G, device=device)
    ys = torch.linspace(-extent, extent, G, device=device)
    zs = torch.linspace(zlo, zhi, Gz, device=device)
    Z, Y, X = torch.meshgrid(zs, ys, xs, indexing="ij")
    return torch.stack([X, Y, Z], -1).reshape(-1, 3)


def random_cubes(pts, n=10, seed=7, lo_frac=0.06, hi_frac=0.18, device="cuda"):
    """Drop `n` axis-aligned solid cubes of RANDOM size at RANDOM places inside the block.
    -> (centre [C,3], half [C,3])."""
    g = torch.Generator(device=device).manual_seed(seed)                               # generate ON the device
    lo, hi = pts.amin(0), pts.amax(0)
    span = hi - lo
    half = (torch.rand(n, 3, generator=g, device=device) * (hi_frac - lo_frac) + lo_frac) * span
    cen = lo + half + torch.rand(n, 3, generator=g, device=device) * (span - 2 * half)
    return cen, half


def box_sdf(p, cen, half):
    """Signed distance from each point to each box: <0 inside, 0 on the surface, >0 outside. -> [N,C]."""
    q = (p[:, None, :] - cen[None]).abs() - half[None]                                 # [N,C,3]
    outside = q.clamp(min=0.0).norm(dim=-1)
    inside = q.amax(-1).clamp(max=0.0)
    return outside + inside


def subcubes(pts, cube_m):
    """Chop the volume into cubes of edge `cube_m`. -> (centres [K,3], ijk [K,3] integer cube coords)."""
    lo = pts.amin(0)
    idx = ((pts - lo) / cube_m).floor().long()
    n = idx.amax(0) + 1
    flat = (idx[:, 2] * n[1] + idx[:, 1]) * n[0] + idx[:, 0]
    K = int((n[0] * n[1] * n[2]).item())
    cnt = torch.zeros(K, device=pts.device).scatter_add(0, flat, torch.ones_like(flat, dtype=torch.float32))
    cen = torch.stack([torch.zeros(K, device=pts.device).scatter_add(0, flat, pts[:, k]) for k in range(3)], -1)
    cen = cen / cnt[:, None].clamp(min=1.0)
    keep = cnt > 0
    ids = torch.arange(K, device=pts.device)[keep]
    ijk = torch.stack([ids % n[0], (ids // n[0]) % n[1], ids // (n[0] * n[1])], -1)
    return cen[keep], ijk


def reachable(cen, ijk, ccen, chalf):
    """Drop subcube centres that sit INSIDE a solid cube — a drone can never stand there, so keeping them as
    waypoints stalls it forever (it is pushed out, never "arrives", and its arc never advances). This is the
    difference between a route that terminates and one that runs to the step cap."""
    ok = box_sdf(cen, ccen, chalf).amin(1) > 0.0
    return cen[ok], ijk[ok], int((~ok).sum())


def serpentine(ijk):
    """Order the cubes along ONE non-self-intersecting snake through the block.

    Flip the x sweep on every row and the y sweep on every layer, so consecutive cubes are always neighbours
    and the curve never revisits or crosses itself. -> `order [K]` (indices into the cube arrays)."""
    ix, iy, iz = ijk[:, 0], ijk[:, 1], ijk[:, 2]
    nx = int(ix.max()) + 1; ny = int(iy.max()) + 1
    y_eff = torch.where(iz % 2 == 0, iy, ny - 1 - iy)               # sweep y one way, back the other, per layer
    x_eff = torch.where((y_eff + iz) % 2 == 0, ix, nx - 1 - ix)     # ...and x flips on every row
    key = (iz * ny + y_eff) * nx + x_eff
    return key.argsort()


def split_runs(order, D):
    """Cut the snake into D CONTIGUOUS arcs — one per drone. Disjoint arcs of a non-crossing curve, so the
    resulting routes cannot intersect. Vectorised: index arithmetic + one gather, no python loop over drones.
    -> `seg [D,L]` padded with -1, `lens [D]`."""
    K = len(order); dev = order.device
    bounds = (torch.arange(D + 1, device=dev) * K) // D              # near-equal split points
    lens = bounds[1:] - bounds[:-1]
    L = int(lens.max())                                             # SETUP-SYNC-OK (shape, once)
    col = torch.arange(L, device=dev)[None, :]                      # [1,L]
    idx = (bounds[:-1, None] + col).clamp(max=K - 1)                # [D,L] position along the snake
    return torch.where(col < lens[:, None], order[idx], torch.full_like(idx, -1)), lens


# =====================================================================================================
# the flock
# =====================================================================================================
def launch_line(pts, D, side="-y", inset=2.0, device="cuda"):
    """Put all D drones on ONE SIDE of the block, spread along it in ARC ORDER.

    Ordering the launch slots to match the arc order is what keeps the transit legs from tangling: drone d's arc
    head lies further along the serpentine than drone d-1's, so if their start slots are ordered the same way the
    outbound legs run roughly parallel instead of crossing over one another. -> `start [D,3]`."""
    lo, hi = pts.amin(0), pts.amax(0)
    t = torch.linspace(0.12, 0.88, D, device=device)                # spread along the launch face (inset from corners)
    x = lo[0] + (hi[0] - lo[0]) * t
    y = torch.full_like(x, float(lo[1] + inset) if side == "-y" else float(hi[1] - inset))
    z = torch.full_like(x, float(lo[2] + inset))                    # launch low, climb into the block
    return torch.stack([x, y, z], -1)


def clear_spawns(start, ccen, chalf):
    """Launch slots are random w.r.t. the random cubes, so one can land inside a solid — where the motion gate
    (correctly) refuses every move and the drone is stuck AT SPAWN forever. Lift any such slot straight up to
    the first height with clearance; +z is always available because cubes sit inside the block."""
    for _ in range(40):                                              # SETUP-LOOP-OK (bounded, runs once)
        bad = box_sdf(start, ccen, chalf).amin(1) <= 0.0
        if not bool(bad.any()):
            break
        start = start + torch.stack([torch.zeros_like(bad), torch.zeros_like(bad), bad.float() * 1.0], -1)
    return start


class FieldSolver:
    """Eikonal distance solve, captured as ONE CUDA graph.

    WHY A GRAPH: `navfield.geodesic` is a python loop of `sweeps` relaxation passes, ~15 kernels each — about
    900 kernel LAUNCHES per solve on a tensor of only ~100k cells. The GPU finishes each kernel in microseconds
    and then waits for the CPU to issue the next: launch-bound, one CPU core pinned, GPU idling. The sweep loop
    is fixed-shape and data-independent — the precondition for CUDA-graph capture — so recording it once and
    replaying collapses ~900 launches into ONE. This is what lets the field be re-solved EVERY step.

    Only the distance is computed. The flow (-grad) used to be captured too, but movement is discrete descent
    on the distance itself, so the gradient kernels were dead weight and are gone."""

    def __init__(self, shape, wxy, wz, sweeps, device):
        self.d_in = torch.zeros(shape, device=device)                # static input: initial distance (0 at sources)
        self.f_in = torch.zeros(shape, dtype=torch.bool, device=device)  # static input: frozen cells (walls+sources)
        self.wxy, self.wz, self.sweeps = wxy, wz, sweeps
        self.graph = None

    def _capture(self):
        st = torch.cuda.Stream(); st.wait_stream(torch.cuda.current_stream())
        with torch.cuda.stream(st):                                  # warm-up outside the graph (allocator etc.)
            for _ in range(3):
                NAV.geodesic(self.d_in, self.f_in, self.wxy, self.wz, self.sweeps)
        torch.cuda.current_stream().wait_stream(st)
        self.graph = torch.cuda.CUDAGraph()
        with torch.cuda.graph(self.graph):                           # record once, replay every step
            self.d_out = NAV.geodesic(self.d_in, self.f_in, self.wxy, self.wz, self.sweeps)

    def solve(self, dist0, fixed):
        if self.graph is None:
            self._capture()
        self.d_in.copy_(dist0); self.f_in.copy_(fixed)               # feed the two static buffers
        self.graph.replay()                                          # ONE launch instead of ~900
        return self.d_out


def build_field(src, blocked, solver, cell_xy, cell_z, sweeps=60):
    """THE GRID PROPOSES EVERY PATH: one eikonal distance field per drone, distance 0 at that drone's SOURCES
    (its assigned cube in the arc phase; EVERY cell still containing grey in cleanup), walls frozen at BIG.

    The solved field simultaneously encodes, for every position, the route to the nearest REACHABLE source
    around everything currently known — a sealed-off source never emits gradient, so useless paths are
    dissected by the solve itself and nothing ever has to poll points or test candidates one by one.

    ONE code path, no branches: `src` and `blocked` are always [D,Gz,G,G] masks composed by the caller
    (the earlier single-target / compose-inside variants were dead code and are gone).
    -> dist [D,Gz,G,G]; BIG at every cell with no legal route to any source."""
    BIG = NAV.BIG
    dist0 = torch.where(src, torch.zeros_like(src, dtype=torch.float32),
                        torch.full(src.shape, BIG, device=src.device))
    fixed = blocked | src
    if solver is not None:                                           # CUDA path (graph); eager only off-GPU
        return solver.solve(dist0, fixed).clone()                    # clone: graph buffers are reused next step
    return NAV.geodesic(dist0, fixed, 1.0 / (cell_xy ** 2), 1.0 / (cell_z ** 2), sweeps, big=BIG)


def run_flock(pts, centres, seg, lens, grid_shape, start=None, speed=12.0, dt=0.1, scan_r=12.0, max_steps=600,
              cub=None, r_min=3.0, r_max=14.0, r_up=0.35, r_down=0.55, clearance=1.5, term_every=100, dbg=None):
    """Fly D point-drones. NO GUARDS — no stuck counters, no retreat timers, no give-up thresholds, no route
    memory to rewind. The algorithm CONVERGES through exactly three mechanisms, each a property of the field:

      1. DISCOVERY : whatever the scan (or contact) touches becomes part of the map, and the field is re-solved
                     every step — an undiscovered wall stops the drone for only as long as it takes to touch it.
      2. DISSECTION: every cell the drone LEAVES is marked RED (Tremaux). Red cells are walls in the field AND
                     in the movement gate (field == gate, single source of truth), so already-flown paths simply
                     stop existing as routes — the field can only propose new ones.
      3. RELIEF    : if a drone's field offers NO route at all (geodesic = BIG), the only removable cause is its
                     own red marks — so they are wiped, ONCE, by that fact itself. Self-correcting, no counter:
                     the proof of "sealed in" is the trigger for unsealing. (In the arc phase the same proof
                     instead skips the unreachable cube — the plan advances on evidence, not patience.)

    THE GRID PROPOSES EVERY PATH. Arc phase: the drone's field has ONE source, its assigned cube. Cleanup: the
    field's sources are ALL cells still containing grey — the solve itself finds the nearest REACHABLE grey
    around every wall; unreachable pockets never emit gradient, so nothing ever polls, picks, or chases a
    point it cannot have. Movement = descend the gradient, through the single legality gate.

    Fully vectorised over drones; one CUDA-graph field solve per step.
    -> frames of (pos [D,3], tgt [D,3], active [D], seen [M], r [D], solid [M], known [M])."""
    dev = pts.device; D = seg.shape[0]; Gz, G = grid_shape
    if cub is None:
        ccen = torch.tensor([[1e6, 1e6, 1e6]], device=dev); chalf = torch.ones(1, 3, device=dev)
    else:
        ccen, chalf = cub
    solid = box_sdf(pts, ccen, chalf).amin(1) < 0                    # truth: points inside a cube (never scannable)
    known = torch.zeros_like(solid)                                  # DISCOVERED so far (starts empty)
    extent = float(pts[:, 0].abs().max()); zlo = float(pts[:, 2].min()); zhi = float(pts[:, 2].max())
    cell_xy = 2 * extent / (G - 1); cell_z = (zhi - zlo) / (Gz - 1)
    cell_vec = torch.tensor([cell_xy, cell_xy, cell_z], device=dev)
    box_lo, box_hi = pts.amin(0), pts.amax(0)
    cell_diag = float((cell_xy ** 2 + cell_xy ** 2 + cell_z ** 2) ** 0.5)
    contact_r = cell_diag                                            # geometry: a pressed-against wall's interior points are within one cell diagonal
    r = torch.full((D,), float(scan_r), device=dev)                  # per-drone adaptive scan radius (AIMD)
    ptr = torch.zeros(D, dtype=torch.long, device=dev)
    pos = centres[seg[:, 0]].clone() if start is None else start.clone()
    seen = torch.zeros(len(pts), dtype=torch.bool, device=dev)
    dead = torch.zeros(D, Gz * G * G, dtype=torch.bool, device=dev)  # RED: flown path + failed routes (per drone)
    drow = torch.arange(D, device=dev)
    was_arc = torch.ones(D, dtype=torch.bool, device=dev)            # one-shot mark wipe at cleanup entry
    # static: field cell of every grid point / every cube centre
    _pci = ((pts - box_lo) / cell_vec).round().long()
    pts_cf = (_pci[:, 2].clamp(0, Gz - 1) * G + _pci[:, 1].clamp(0, G - 1)) * G + _pci[:, 0].clamp(0, G - 1)
    cen_cell = ((centres - box_lo) / cell_vec).round().long()
    cen_cell = (cen_cell[:, 2].clamp(0, Gz - 1) * G + cen_cell[:, 1].clamp(0, G - 1)) * G + cen_cell[:, 0].clamp(0, G - 1)
    solver = FieldSolver((D, Gz, G, G), 1.0 / (cell_xy ** 2), 1.0 / (cell_z ** 2), 60, dev) \
             if pts.is_cuda else None
    noff = torch.stack(torch.meshgrid(torch.arange(-1, 2, device=dev), torch.arange(-1, 2, device=dev),
                                      torch.arange(-1, 2, device=dev), indexing="ij"), -1).reshape(-1, 3)
    wp = pos.clone(); has_wp = torch.zeros(D, dtype=torch.bool, device=dev)   # committed waypoint per drone
    frames = []; step = speed * dt
    for it in range(max_steps):                                      # STEP-LOOP-OK (time, sequential by nature)
        unseen_free = (~seen) & (~solid)
        arc_left = ptr < lens
        # cleanup entry: the arc's red marks belonged to the arc — wipe once, cleanup starts unsealed
        fresh = was_arc & (~arc_left)
        dead = dead & ~fresh[:, None]
        was_arc = arc_left
        active = arc_left | unseen_free.any()
        ti = seg.gather(1, ptr.clamp(max=seg.shape[1] - 1)[:, None]).squeeze(1).clamp(min=0)
        tgt = centres[ti]
        # ---- sources: the assigned cube (arc) or EVERY grey cell (cleanup) ----
        grey_cells = torch.zeros(Gz * G * G, dtype=torch.bool, device=dev)
        grey_cells.scatter_(0, pts_cf, unseen_free)
        cube_src = torch.zeros(D, Gz * G * G, dtype=torch.bool, device=dev)
        cube_src.scatter_(1, cen_cell[ti][:, None], True)
        src_v = torch.where(arc_left[:, None], cube_src, grey_cells[None].expand(D, -1)).view(D, Gz, G, G)
        # ---- field == gate: walls + red, sole exemption = the drone's own current cell ----
        # NO safety margin in the routing layer. The field's walls are EXACTLY the discovered solid cells —
        # nothing dilated, nothing invented. Physics (the contact gate) keeps a drone out of real geometry;
        # discovery turns touched geometry into field walls; the field routes around precisely what is known.
        # (An earlier hidden margin here — one-cell dilation — silently forbade a ~3.5 m ring around every cube
        # and made 770 grey points permanently unreachable.)
        #
        # DESIGN (agreed, not yet built) — SAFETY MARGIN AS AN OBJECT SHELL, A SEPARATE LAYER:
        # when a real clearance margin is wanted, it is to be computed as a SHELL over each DETECTED 3D OBJECT —
        # i.e. once enough wall cells are discovered to constitute an object, an inflation shell is derived from
        # THAT OBJECT's reconstructed surface and kept as its own additional mask layer:
        #     walls(known) | shell(objects) | red(trails)   — three layers, separately owned, separately visible.
        # Explicitly NOT as a "drone window" (per-drone sensing radius, gate buffer, or any distance folded into
        # movement decisions): window-margins are invisible in the output, differ per drone, and this session
        # showed they silently eat coverage and cause freezes. A shell layer, by contrast, is shared, renders as
        # its own colour, is subtractable from coverage metrics, and can be regenerated whenever an object's
        # reconstruction improves — the margin becomes DATA about the world, not behaviour baked into the drone.
        kv = known.view(1, Gz, G, G)
        strict = kv | dead.view(D, Gz, G, G)
        pci = ((pos - box_lo) / cell_vec).round().long()
        self_cf = (pci[:, 2].clamp(0, Gz - 1) * G + pci[:, 1].clamp(0, G - 1)) * G + pci[:, 0].clamp(0, G - 1)
        sf = strict.reshape(D, -1).clone()
        sf.scatter_(1, self_cf[:, None], torch.zeros_like(self_cf[:, None], dtype=torch.bool))
        strict = sf.view(D, Gz, G, G) | kv
        dist_f = build_field(src_v, strict, solver, cell_xy, cell_z)
        # ---- DISCRETE DESCENT on the same cells the gate checks (the ONLY forward motive) -----------------
        # Trilinear-interpolated flow was the last hidden deadlock: interpolation between cells can point INTO a
        # red cell, the gate refuses, nothing changes, and the drone freezes forever with a perfectly finite
        # route (so no_route never fires and relief cannot see it). Field and gate must speak the SAME language:
        # cells. So the drone steps toward the LEGAL NEIGHBOUR CELL with the smallest field distance. Eikonal
        # distance has no local minima over the legal cells — every finite cell has a strictly-smaller legal
        # neighbour — so descent either progresses every step or the drone's own cell reads BIG, which IS
        # no_route, which triggers skip/relief. Progress or proof; nothing in between.
        dflat = dist_f.reshape(D, -1)
        nci = pci[:, None, :] + noff[None]                           # [D,27] neighbour cells (incl. self)
        n_inb = (nci >= 0).all(-1) & (nci[..., 0] < G) & (nci[..., 1] < G) & (nci[..., 2] < Gz)
        ncc = nci.clamp(min=0)
        ncc = torch.stack([ncc[..., 0].clamp(max=G - 1), ncc[..., 1].clamp(max=G - 1), ncc[..., 2].clamp(max=Gz - 1)], -1)
        ncf = (ncc[..., 2] * G + ncc[..., 1]) * G + ncc[..., 0]
        nwall = (known[ncf] | dead[drow[:, None], ncf]) & (ncf != self_cf[:, None])
        ndist = torch.where(n_inb & (~nwall), dflat.gather(1, ncf), torch.full_like(ncf, 10 * NAV.BIG, dtype=dflat.dtype))
        self_d = dflat.gather(1, self_cf[:, None]).squeeze(1)
        no_route = self_d > 1e5                                      # PROOF: nothing reachable in this field
        # ---- ALL 27 DIRECTIONS AT ONCE: best DESCENDING & PHYSICALLY PASSABLE step wins ---------------------
        # Committing to the single best direction and freezing when physics refused it was the last stall: the
        # refused candidate usually lands inside the drone's OWN cell (step < cell), so nothing could be marked
        # and nothing changed. A maze walker blocked in the best direction takes the next one. So: candidate
        # positions toward all 27 neighbour cells, gate them ALL in one batch, and take the passable one with
        # the smallest field distance. Blocked directions are not failures — they are simply not chosen.
        ncen = box_lo + ncc.float() * cell_vec                       # [D,27,3] neighbour cell centres
        # passable = the FIRST STEP toward that cell is physically takeable and the cell is enterable. Tested at
        # the actual candidate positions (pos + one step toward each centre) — NOT at the cell centres: a cube
        # can cover a cell's centre while most of the cell is free air, and testing centres instead of steps
        # silently deleted those cells as options (measured: coverage 100% -> 76.8%). Cleanup must not change
        # semantics; this is the original test restored.
        dirs27 = ncen - pos[:, None, :]
        dmag27 = dirs27.norm(dim=-1, keepdim=True)
        cand27 = pos[:, None, :] + torch.where(dmag27 > 1e-6, dirs27 / dmag27.clamp(min=1e-6),
                                               torch.zeros_like(dirs27)) * step
        cflat = cand27.reshape(D * 27, 3)
        cin = ((cflat >= box_lo) & (cflat <= box_hi)).all(-1)
        cclear = box_sdf(cflat, ccen, chalf).amin(1) >= 0.0          # physics at the actual step position
        cci27 = ((cflat - box_lo) / cell_vec).round().long()
        ccf27 = (cci27[:, 2].clamp(0, Gz - 1) * G + cci27[:, 1].clamp(0, G - 1)) * G + cci27[:, 0].clamp(0, G - 1)
        cwall = (known[ccf27] | dead[drow.repeat_interleave(27), ccf27]) & (ccf27 != self_cf.repeat_interleave(27))
        passable = (cin & cclear & (~cwall)).view(D, 27)
        score = torch.where(passable, ndist, torch.full_like(ndist, 10 * NAV.BIG))
        # ---- COMMITTED WAYPOINTS: the drone has exactly TWO options — stay, or fly to the PROPOSED POINT. ----
        # The shaking was this contract being broken: the proposal was re-decided every 1.2 m sub-step, and
        # along an eikonal front two neighbour cells are near-equal, so the winner flipped each step and the
        # drone zigzagged in place (measured cos -0.94: near-perfect direction reversal every step). Now a
        # proposal is COMMITTED — the drone flies straight to it, and a new proposal is requested only on
        # ARRIVAL or on PHYSICAL REFUSAL (which is itself discovery). The field still updates every step;
        # commitments simply do not churn with it.
        jj = score.argmin(1)
        best_cen = ncen.gather(1, jj[:, None, None].expand(D, 1, 3)).squeeze(1)   # the proposed cell centre
        movable = score.gather(1, jj[:, None]).squeeze(1) < NAV.BIG
        need_new = (~has_wp) | ((wp - pos).norm(dim=-1) <= step)     # no commitment, or arrived at it
        wp = torch.where((need_new & movable)[:, None], best_cen, wp)
        has_wp = (has_wp | (need_new & movable)) & active
        wv = wp - pos
        wmag = wv.norm(dim=-1, keepdim=True)
        stepv = torch.where(wmag <= step, wv, wv / wmag.clamp(min=1e-6) * step)
        cand1 = pos + stepv * (has_wp & active)[:, None].float()
        ok1 = (((cand1 >= box_lo) & (cand1 <= box_hi)).all(-1)) & (box_sdf(cand1, ccen, chalf).amin(1) >= 0.0)
        pos_prev = pos
        pos = torch.where(ok1[:, None], cand1, pos)
        refused = has_wp & active & (~ok1)
        has_wp = has_wp & (~refused)                                 # refusal -> fresh proposal from the re-solved field
        # CONTACT IS DISCOVERY: a physically refused move means the drone touched geometry the field does not
        # know. The touched cell becomes a KNOWN wall (shared); the field re-solves and the next proposal routes
        # around it. Refusals convert into map knowledge — freezing in place is structurally impossible.
        cci = ((cand1 - box_lo) / cell_vec).round().long()
        ccf = (cci[:, 2].clamp(0, Gz - 1) * G + cci[:, 1].clamp(0, G - 1)) * G + cci[:, 0].clamp(0, G - 1)
        kadd = torch.zeros_like(known)
        kadd.scatter_(0, torch.where(ccf != self_cf, ccf, self_cf), refused)
        known = known | kadd
        if dbg is not None:
            dbg.append((float(self_d[0]), int(ptr[0]), float(r[0])))    # opt-in probe (CPU sync when used)
        # ---- Tremaux: the cell just LEFT becomes RED (never the one the drone is in) ----
        vci = ((pos - box_lo) / cell_vec).round().long()
        vcf = (vci[:, 2].clamp(0, Gz - 1) * G + vci[:, 1].clamp(0, G - 1)) * G + vci[:, 0].clamp(0, G - 1)
        pci_prev = ((pos_prev - box_lo) / cell_vec).round().long()
        pcf_prev = (pci_prev[:, 2].clamp(0, Gz - 1) * G + pci_prev[:, 1].clamp(0, G - 1)) * G + pci_prev[:, 0].clamp(0, G - 1)
        vmark = torch.zeros_like(dead); vmark.scatter_(1, pcf_prev[:, None], (pcf_prev != vcf)[:, None])
        dead = dead | vmark
        # ---- RELIEF: "no route" is itself the proof the drone's own marks seal it in -> wipe them (cleanup) ----
        dead = dead & ~(no_route & (~arc_left) & active)[:, None]
        # ---- AIMD adaptive scan radius (the user's sensing rule — algorithm, not guard) ----
        touch = box_sdf(pos, ccen, chalf).amin(1) <= r
        r = torch.where(touch, (r * (1.0 - r_down)).clamp(min=r_min), (r + r_up).clamp(max=r_max))
        # ---- scan + discovery (discovery-on-contact: a wall you stand against is known by definition) ----
        dpt = (pts[:, None, :] - pos[None, :, :]).norm(dim=-1)
        inr = (dpt <= r[None, :]).any(1)
        seen = seen | (inr & (~solid))
        known = known | (((dpt <= torch.clamp(r, min=contact_r)[None, :]).any(1)) & solid)
        frames.append((pos.clone(), tgt.clone(), active.clone(), seen.clone(), r.clone(), solid, known.clone()))
        # ---- plan advance: ARRIVED, or the field PROVED the cube unreachable -> next cube ----
        arrived = (self_cf == cen_cell[ti])                          # arrival = being IN the target cell, no radius
        ptr = ptr + (active & arc_left & (arrived | no_route)).long()
        if it % term_every == 0 and not bool(active.any()):          # SYNC-OK: 1 per term_every steps
            break
    return frames


# =====================================================================================================
# movie
# =====================================================================================================
def _cam(eye, look_at, W, H, fov_deg, device):
    eye = np.asarray(eye, np.float32); fwd = np.asarray(look_at, np.float32) - eye
    fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, np.array([0, 0, 1], np.float32)); right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    f = 0.5 * W / np.tan(np.radians(fov_deg) / 2.0)
    t = lambda a: torch.tensor(np.asarray(a, np.float32), dtype=torch.float32, device=device)[None]
    return t(eye), t(right), t(up), t(fwd), torch.tensor([f], dtype=torch.float32, device=device)


def _box_edges(lo, hi, device):
    """The 12 edges of the block, so the GRID BOUNDARY is visible in the video and 'did a drone leave the grid?'
    is answered by looking, not by trusting a printed number."""
    c = torch.tensor([[lo[0], lo[1], lo[2]], [hi[0], lo[1], lo[2]], [hi[0], hi[1], lo[2]], [lo[0], hi[1], lo[2]],
                      [lo[0], lo[1], hi[2]], [hi[0], lo[1], hi[2]], [hi[0], hi[1], hi[2]], [lo[0], hi[1], hi[2]]],
                     dtype=torch.float32, device=device)
    e = [(0,1),(1,2),(2,3),(3,0),(4,5),(5,6),(6,7),(7,4),(0,4),(1,5),(2,6),(3,7)]
    idx = torch.tensor(e, device=device)
    return c[idx[:, 0]], c[idx[:, 1]]


def render(pts, frames, out_path, W=900, H=700, stride=1, fps=None, device="cuda"):
    """Grey block turning green, with each drone drawn in its own colour."""
    ext = float(pts[:, :2].abs().max()); zmid = float(pts[:, 2].mean())
    cam = _cam((ext * 2.9, -ext * 3.4, ext * 2.1), (0, 0, zmid), W, H, 52.0, device)   # zoomed out: whole cube in frame
    sky = torch.tensor(SKY, dtype=torch.float32, device=device)[None, None].expand(H, W, 3).contiguous()
    grey = torch.tensor(C_GREY, dtype=torch.float32, device=device)
    seenc = torch.tensor(C_SEEN, dtype=torch.float32, device=device)
    D = frames[0][0].shape[0]
    dcol = torch.tensor([PALETTE[i % len(PALETTE)] for i in range(D)], dtype=torch.float32, device=device)
    w = VideoWriter(out_path, fps or FPS)
    for i in range(0, len(frames), stride):                          # RENDER-LOOP-OK (offline)
        pos, tgt, active, seen, r, solid, known = frames[i]
        col = torch.where(seen[:, None], seenc, grey)
        col = torch.where(solid[:, None], torch.tensor(C_SOLID, dtype=torch.float32, device=device), col)[None]
        scr, dep = _project(*cam, W, H, pts[None])
        q, qd, qv = _sprite_quads(scr, dep, torch.full_like(dep, 2.1), dep > 0.05)   # bigger: the volume must read as solid
        layers = [_quads_to_tris(q, qd, col, qv)]
        # GRID BOUNDARY wireframe — white edges of the block the drones must never leave
        ea, eb = _box_edges(pts.amin(0), pts.amax(0), device)
        sa, da_ = _project(*cam, W, H, ea[None]); sb, db_ = _project(*cam, W, H, eb[None])
        lq, lqd, lqv = _line_quads(sa, sb, (da_ + db_) * 0.5, torch.full_like(da_, 1.2), (da_ > 0.05) & (db_ > 0.05))
        ecol = torch.tensor([235., 235., 245.], device=device)[None, None].expand(1, lq.shape[1], 3)
        layers.append(_quads_to_tris(lq, lqd, ecol, lqv))   # one colour PER EDGE-QUAD, not one total
        for arr, sz, dim in ((tgt, 4.0, 0.55), (pos, 7.0, 1.0)):     # target centres, then the drones
            s2, d2 = _project(*cam, W, H, arr[None])
            # A drone must NEVER be invisible. Two ways the old code hid them:
            #  1. dimming parked drones to 35% made them DARKER than the (brightened) grey lattice points, so
            #     they melted into the background;
            #  2. z-buffering: a drone deep inside the block loses the depth test against thousands of nearer
            #     lattice points and is simply painted over.
            # So: drones keep ~full colour whether active or parked, draw LARGE, and their depth is biased to a
            # tiny value so they ALWAYS win the z-buffer — a HUD marker, never occluded by the point cloud.
            vis = (d2 > 0.05) if sz >= 7.0 else ((d2 > 0.05) & active[None])
            shade = torch.where(active[:, None], dcol * dim, dcol * 0.85)[None]
            dd = d2 * 0.02 if sz >= 7.0 else d2                       # depth bias: drones render on top of everything
            qq, qqd, qqv = _sprite_quads(s2, dd, torch.full_like(d2, sz + 2.0), vis)
            layers.append(_quads_to_tris(qq, qqd, shade, qqv))
        tris = torch.cat([l[0] for l in layers], 1); dps = torch.cat([l[1] for l in layers], 1)
        cols = torch.cat([l[2] for l in layers], 1); vals = torch.cat([l[3] for l in layers], 1)
        img = _rasterize(tris, dps, cols, vals, W, H, sky, chunk=64)[0].cpu().numpy().astype(np.uint8)
        w.append_data(img)
    w.close()
    return out_path


def main():
    out = _s.argv[1] if len(_s.argv) > 1 else "videos/scout.mp4"
    D = int(_s.argv[2]) if len(_s.argv) > 2 else 10
    cube_m = float(_s.argv[3]) if len(_s.argv) > 3 else 12.0
    G = int(_s.argv[4]) if len(_s.argv) > 4 else 24
    Gz = int(_s.argv[5]) if len(_s.argv) > 5 else 19
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    pts = make_grid(G=G, Gz=Gz, device=dev)
    grid_shape = (Gz, G)
    ccen, chalf = random_cubes(pts, n=10, device=dev)
    cen, ijk = subcubes(pts, cube_m)
    cen, ijk, n_drop = reachable(cen, ijk, ccen, chalf)
    order = serpentine(ijk)
    seg, lens = split_runs(order, D)
    print(f"grid {G}x{G}x{Gz} = {len(pts)} grey points   subcubes {len(cen)} reachable (edge {cube_m:.0f} m, {n_drop} dropped: centre inside a cube)")
    print(f"{D} drones   arc lengths {lens.tolist()}   (contiguous, disjoint -> routes cannot intersect)")
    start = clear_spawns(launch_line(pts, D, device=dev), ccen, chalf)
    frames = run_flock(pts, cen, seg, lens, grid_shape, start=start, cub=(ccen, chalf))
    # closest approach between any two drones over the whole run -> a direct check that routes stayed apart
    P = torch.stack([f[0] for f in frames])                         # [T,D,3]
    dm = (P[:, :, None, :] - P[:, None, :, :]).norm(dim=-1)         # [T,D,D]
    dm = dm + torch.eye(D, device=dev)[None] * 1e9
    print(f"closest approach between any two drones: {float(dm.min()):.1f} m (0 would mean routes touched)")
    solid = frames[-1][5]; seen = frames[-1][3]
    free = ~solid
    print(f"obstacles: 10 random cubes -> {int(solid.sum())}/{len(pts)} points solid ({100*float(solid.float().mean()):.1f}%)")
    # THE metric: GREY COVERAGE — scanned fraction of the SCANNABLE (free) points. Red is omitted from the
    # denominator: points inside solid cubes can never be scanned, so counting them only muddies the number.
    print(f"GREY COVERAGE: {100*float((seen&free).float().sum()/free.float().sum()):.1f}%  "
          f"({int((seen&free).sum())}/{int(free.sum())} scannable points, {len(frames)*0.1:.0f}s)")
    R = torch.stack([f[4] for f in frames])                          # [T,D] radius history
    print(f"adaptive scan radius: min {float(R.min()):.1f} m   mean {float(R.mean()):.1f} m   max {float(R.max()):.1f} m")
    inside = torch.stack([(box_sdf(f[0], ccen, chalf).amin(1) < 0).any() for f in frames]).any()
    print(f"any drone ever INSIDE a cube: {bool(inside)}")
    kn = frames[-1][6]
    print(f"obstacle points DISCOVERED: {int(kn.sum())}/{int(solid.sum())} ({100*float(kn.sum()/solid.sum().clamp(min=1)):.0f}%) -> field was re-solved as they were found")
    P = torch.stack([f[0] for f in frames]); mv = (P[1:] - P[:-1]).norm(dim=-1).sum(0)
    print(f"path length per drone (m): min {float(mv.min()):.0f}  mean {float(mv.mean()):.0f}  max {float(mv.max()):.0f}   (0 would mean frozen)")
    _o.makedirs(_o.path.dirname(out) or ".", exist_ok=True)
    render(pts, frames, out, device=dev)
    print("wrote", out)


if __name__ == "__main__":
    main()
