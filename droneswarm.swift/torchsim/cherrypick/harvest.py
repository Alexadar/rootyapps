"""cherrypick.harvest — a NON-AI, pure algorithmic swarm harvesting demo.

Confirms the session's finding on a NEW, multi-stage task: with a quantized geodesic ROUTE field + a
geometric velocity controller — and ZERO neural net — a small drone swarm can harvest cherries off a
tree, weaving around the leaves it must not touch. Each drone runs a 3-stage loop:

    SEEK  a cherry  (fly the route field to it, routing AROUND the forbidden foliage)
    PICK  it        (proximity -> the cherry attaches to the drone)
    CARRY it to the bucket, DROP it  (fly the bucket's route field, release)
    ... repeat, claiming the nearest free cherry, until every cherry is in the bucket.

The navigation is the SHARED engine: common.navfield (Godunov Eikonal geodesic + flow) builds ONE static
field per target (the tree and targets never move, so the fields are computed ONCE and reused every tick),
and common.controller.velocity_track turns the sampled flow into thrust + body-rates. common.oracles
supply the geometry (collide3 SDF occupancy) and physics (quadrotor.quad_step). No arena dependency.

The per-tick MATH (fields, controller, physics) is vectorized over the swarm; the outer tick loop and the
tiny greedy-assignment logic are OFFLINE control code (this is a demo, not the compiled training hot path),
so readable python control flow is fine here (RENDER-LOOP-OK class) — the [[no-loops-in-engine]] rule is
about the sim hot path, which this demo does not have.
"""
# --- path bootstrap: expose the shared `common` package (torchsim root) + this dir ---
import os as _bo, sys as _bs
_bs.path.insert(0, _bo.path.dirname(_bo.path.abspath(__file__)))                    # cherrypick/
_bs.path.insert(0, _bo.path.dirname(_bo.path.dirname(_bo.path.abspath(__file__))))  # torchsim/ (the `common` package)

import math
import time
import torch

from common import navfield as NAV
from common import controller as CTRL
from common.oracles import collide3 as COL
from common.oracles import quadrotor as QUAD
import scene as SCENE


class CFG:
    """All demo constants in one place. Physics matches the 5-inch FPV airframe in arena/world_config_drone
    (mass/t2w/omega/drag). Controller gains are FIXED — there is nothing to learn."""
    # physics (5-inch FPV; == arena WorldConfig)
    dt = 1.0 / 50.0; gravity = 9.81; mass = 0.65; t2w = 2.5; omega_max = 11.7
    tau_omega = 0.030; drag_quad = 0.046; drag_lin = 0.0
    t_max = t2w * mass * gravity                          # full-throttle collective thrust [N] (~15.9)
    # velocity-tracking controller gains (fixed algorithmic flight)
    v_cruise = 4.3; tau = 0.11; k_v = 3.3; k_R = 11.0    # slower cruise + TIGHTER velocity tracking -> less overshoot
                                                          #   weaving inside the multi-tier crown (fewer branch clips)
    # quantized route field — DENSE grid (64x64x48, cell ~0.44 m) so the field can thread the small, packed leaves
    extent = 14.0; zlo = -1.0; zhi = 12.5; G = 64; Gz = 48; sweeps = 200
    r_clear = 0.46                                        # body radius + margin: the field's obstacle/ground clip
                                                          #   (> crash_r so a well-tracked route never touches a solid;
                                                          #    smaller here than the coarse grid — fine cells resolve tighter gaps)
    # task thresholds
    pick_r = 1.15; drop_r = 1.3; slow_r = 3.0            # geodesic radii for PICK / DROP / terminal ease-in
                                                          #   (pick_r generous so a drone weaving inside the crown still
                                                          #    grabs fruit it can only get ~1 m from, not hover forever)
    min_alt = 0.18                                        # drones never sink below this (soft ground)
    crash_r = 0.13                                        # body radius: touching a leaf/branch within this DESTROYS the drone
                                                          #   (the field keeps r_clear=0.40 clearance, so a crash means it
                                                          #    OVERSHOT the route -> a real avoidance failure, not a false alarm)
    max_ticks = 14000; rec_stride = 18; path_steps = 16  # sim cap, frames kept every Nth tick, chosen-path trace length
    rng_seed = 0                                          # seeds the random cherry assignment (reproducible harvest)


def _grid(cfg, device):
    """Build the quantized cell-centre grid + pitches. Returns nav_xyz [Gz,G,G,3], cell(xy), zcell."""
    xs = torch.linspace(-cfg.extent, cfg.extent, cfg.G, device=device)     # [G] xy centres (square)
    zs = torch.linspace(cfg.zlo, cfg.zhi, cfg.Gz, device=device)           # [Gz] z centres
    zc, yc, xc = torch.meshgrid(zs, xs, xs, indexing="ij")                 # each [Gz,G,G]
    nav_xyz = torch.stack([xc, yc, zc], -1)                                # [Gz,G,G,3] world pos of each cell
    cell = float(2.0 * cfg.extent / max(1, cfg.G - 1))                     # xy pitch (m)
    zcell = float((cfg.zhi - cfg.zlo) / max(1, cfg.Gz - 1))                # z pitch (m)
    return nav_xyz, cell, zcell


def _occupancy(scn, nav_xyz, cfg):
    """Nearest-obstacle signed distance per cell + the FORBIDDEN mask (inside a solid OR below ground).
    Returns occ [Gz,G,G] and forbidden [Gz,G,G] (bool)."""
    Gz, G, _, _ = nav_xyz.shape
    d = nav_xyz[:, :, :, None, :] - scn["obs_c"][None, None, None, :, :]   # [Gz,G,G,O,3] cell -> obstacle centre
    sdf = COL.shape_sdf3(d, scn["obs_h"][None, None, None], scn["obs_cyl"][None, None, None])   # [Gz,G,G,O]
    occ = sdf.amin(-1)                                                     # [Gz,G,G] nearest-solid signed distance
    cell_z = nav_xyz[..., 2]                                              # [Gz,G,G] altitude of each cell
    forbidden = (occ < cfg.r_clear) | (cell_z < cfg.r_clear)              # inside a solid OR into the ground
    return occ, forbidden


def build_fields(scn, nav_xyz, cell, zcell, cfg):
    """Build ONE static geodesic route field per TARGET (each cherry + the bucket). Returns
    dist_all [B,Gz,G,G], flow_all [B,Gz,G,G,3], src_pos [B,3] (the allowed source-cell centres), and the
    forbidden mask. B = n_cherries + 1 (bucket is the LAST field)."""
    device = nav_xyz.device
    Gz, G = cfg.Gz, cfg.G
    occ, forbidden = _occupancy(scn, nav_xyz, cfg)
    cells = nav_xyz.reshape(Gz * G * G, 3)                                # [C,3] all cell centres
    allowed = (~forbidden).reshape(Gz * G * G)                           # [C] usable cells
    targets = torch.cat([scn["cherries"], scn["bucket"][None]], 0)       # [B,3] cherries + bucket

    # each target's SOURCE = the ALLOWED cell nearest to it (guarantees the field can start there even if
    # the exact cherry point sits just inside a leaf). Vectorized argmin over cells, forbidden -> +inf.
    d2 = ((cells[None] - targets[:, None]) ** 2).sum(-1)                  # [B,C] target -> every cell
    d2 = d2 + (~allowed)[None] * 1e12                                     # forbid non-allowed cells as sources
    src_flat = d2.argmin(-1)                                             # [B] flat source-cell index
    src_pos = cells[src_flat]                                            # [B,3] source-cell centres (reachable)

    B = targets.shape[0]
    BIG = NAV.BIG
    dist = torch.full((B, Gz * G * G), BIG, device=device)
    dist.scatter_(1, src_flat[:, None], 0.0)                            # source cell -> 0
    dist = dist.reshape(B, Gz, G, G)
    fb = forbidden[None].expand(B, Gz, G, G)                            # solids frozen in every field
    fixed = fb.clone(); fixed.reshape(B, -1).scatter_(1, src_flat[:, None], True)   # sources frozen too
    wxy = 1.0 / (cell * cell); wz = 1.0 / (zcell * zcell)
    dist = NAV.geodesic(dist, fixed, wxy, wz, cfg.sweeps, big=BIG)       # SHARED Eikonal solve
    flow = NAV.flow_from_dist(dist, cell, zcell)                        # SHARED -grad(dist), unit
    flow = torch.where(fb[..., None], torch.zeros_like(flow), flow)     # no guidance inside a solid
    dist = dist.clamp(max=BIG)
    return dist, flow, src_pos, forbidden


def _sample_flow(dist_all, flow_all, field_idx, pos, cfg):
    """Sample each drone's CURRENT field at its position. dist_all [B,Gz,G,G], flow_all [B,...,3],
    field_idx [D] (which field each drone follows), pos [D,3] -> geo [D], flow [D,3]."""
    dist_d = dist_all[field_idx]                                        # [D,Gz,G,G] gather per-drone field
    flow_d = flow_all[field_idx]                                        # [D,Gz,G,G,3]
    geo, flow = NAV.sample3(dist_d, flow_d, pos[:, None, :], cfg.extent, cfg.zlo, cfg.zhi)   # B=D, Q=1
    return geo[:, 0], flow[:, 0]                                        # [D], [D,3]


def _chosen_paths(dist_all, flow_all, field_idx, pos, cfg, cell):
    """Trace each drone's committed route: walk its field's flow K steps from its position. Returns
    [D,K,3] for the SOLID-GREEN path overlay in the render."""
    p = pos.clone(); out = [p]
    for _ in range(cfg.path_steps):                                    # RENDER-LOOP-OK (offline, tiny K)
        _, fl = _sample_flow(dist_all, flow_all, field_idx, p, cfg)
        p = p + fl * cell                                             # step one cell along the smooth flow
        out.append(p)
    return torch.stack(out, 1)                                         # [D,K+1,3]


def _frame(scn, d_pos, d_quat, cstate, assigned, stage, alive, dist_all, flow_all, field_idx, cfg, cell, device):
    """Snapshot one tick for the renderer. Cherry positions are placed VECTORIZED (no per-drone loop):
    a carried cherry rides under its carrier drone; a delivered/lost cherry sits in the bucket pile."""
    cherry_pos = scn["cherries"].clone()
    carrying = (stage == 1) & alive & (assigned >= 0)                  # CARRY drones hold their cherry
    if bool(carrying.any()):
        cd = carrying.nonzero(as_tuple=True)[0]
        cherry_pos[assigned[cd]] = d_pos[cd] + torch.tensor([0., 0., -0.25], device=device)   # rides under the drone
    done = (cstate == 3) | (cstate == 4)                              # delivered or lost -> pile in the bucket
    if bool(done.any()):
        di = done.nonzero(as_tuple=True)[0]; k = torch.arange(di.shape[0], device=device).float()
        cherry_pos[di] = scn["bucket"][None] + torch.stack([0.18 * torch.cos(k), 0.18 * torch.sin(k), 0.15 + 0.05 * k], -1)
    paths = _chosen_paths(dist_all, flow_all, field_idx, d_pos, cfg, cell)
    return dict(d_pos=d_pos.clone().cpu(), d_quat=d_quat.clone().cpu(), cherry_pos=cherry_pos.cpu(),
                cstate=cstate.clone().cpu(), alive=alive.clone().cpu(), paths=paths.cpu())


def run(scn, cfg, device):
    """Run the harvest. Returns (frames, stats). frames = list of per-tick dicts for the renderer."""
    torch.manual_seed(cfg.rng_seed)                                   # seed the RANDOM cherry assignment -> reproducible run
    nav_xyz, cell, zcell = _grid(cfg, device)
    dist_all, flow_all, src_pos, forbidden = build_fields(scn, nav_xyz, cell, zcell, cfg)
    M = scn["cherries"].shape[0]; BUCKET = M                          # bucket is field index M
    D = scn["spawns"].shape[0]
    leaf_lo = scn["leaf_lo"]                                          # obstacles [leaf_lo:] are foliage (for crash labelling)

    # --- reachability guard: every cherry field must reach the drone spawn region (else it's walled in) ---
    spawn_c = scn["spawns"].mean(0).reshape(1, 1, 3).expand(M, 1, 3)  # spawn centroid, one probe per cherry field
    sg, _ = NAV.sample3(dist_all[:M], flow_all[:M], spawn_c, cfg.extent, cfg.zlo, cfg.zhi)   # [M,1] geodesic dist at spawn
    unreached = int((sg[:, 0] > NAV.BIG * 0.5).sum())
    if unreached:
        print(f"[harvest] WARNING: {unreached}/{M} cherries appear unreachable from spawn (walled by leaves)")

    # --- drone state ---
    d_pos = scn["spawns"].clone()                                    # [D,3]
    d_vel = torch.zeros(D, 3, device=device)
    d_quat = torch.zeros(D, 4, device=device); d_quat[:, 0] = 1.0     # identity (level)
    d_omega = torch.zeros(D, 3, device=device)
    d_vref = torch.zeros(D, 3, device=device)                        # controller low-pass state
    # --- task state ---
    stage = torch.zeros(D, dtype=torch.long, device=device)          # 0=SEEK, 1=CARRY
    assigned = torch.full((D,), -1, dtype=torch.long, device=device) # cherry index each drone owns (-1=none)
    cstate = torch.zeros(M, dtype=torch.long, device=device)         # 0=on-tree,1=claimed,2=carried,3=delivered,4=lost
    alive = torch.ones(D, dtype=torch.bool, device=device)           # a drone that touches a solid is DESTROYED (False)
    crash_leaf = crash_wood = 0

    def assign_random():
        """Give every free (idle, alive, SEEK) drone a RANDOM available cherry — DISTINCT across drones, and
        FULLY VECTORIZED (no python loop, no `if`). Trick: score available cherries with a random key and take
        the k-th best for the k-th free drone (a random ranking = a random distinct draw). Runs unconditionally;
        when nobody's free (or nothing's left) every write below is an empty no-op. Random (not nearest) makes the
        drones criss-cross the whole tree instead of all swarming the closest fruit."""
        nonlocal assigned, cstate
        free = (stage == 0) & (assigned < 0) & alive                # [D] drones needing a cherry
        avail = (cstate == 0)                                       # [M] cherries on the tree (unclaimed)
        pr = torch.rand(M, device=device) * avail.float() - (~avail).float()   # available -> (0,1), taken -> -1
        order = pr.argsort(descending=True)                        # cherries best-first: available in RANDOM order, then rest
        rank = torch.cumsum(free.long(), 0) - 1                     # [D] 0,1,2,... over the free drones (junk on the rest)
        cand = order[rank.clamp(min=0, max=M - 1)]                 # [D] the rank-th random available cherry per drone
        take = free & (rank >= 0) & (rank < avail.sum())          # [D] drones that actually get one (enough cherries left)
        assigned = torch.where(take, cand, assigned)               # claim it
        cstate[cand[take]] = 1                                     # mark those cherries claimed (distinct -> safe scatter)

    frames = []
    wind = torch.zeros(D, 3, device=device); ge = torch.ones(D, device=device)
    ceiling = cfg.zhi - 0.5
    done_tick = None
    for tick in range(cfg.max_ticks):                                # sequential SIM loop (offline; NOT a compiled hot path)
        # which field each drone follows (bucket when CARRY, its cherry when SEEK); dead/idle -> hover
        field_idx = torch.where(stage == 1, torch.full_like(assigned, BUCKET), assigned.clamp(min=0))
        has_task = ((stage == 1) | (assigned >= 0)) & alive          # dead or no-cherry-left -> hold position
        geo, flow3 = _sample_flow(dist_all, flow_all, field_idx, d_pos, cfg)
        ease = (geo / cfg.slow_r).clamp(0.2, 1.0)                    # terminal slow-down so it doesn't overshoot
        v_ref = torch.where(has_task[:, None], flow3 * (cfg.v_cruise * ease)[:, None], torch.zeros_like(flow3))

        # SHARED velocity-tracking controller -> thrust + body-rates, then one physics tick. DEAD drones freeze
        # where they crashed (masked out of the integration).
        thrust, omega_cmd, d_vref = CTRL.velocity_track(d_vel, d_quat, v_ref, d_vref, cfg.k_v, cfg.k_R, cfg.tau,
                                                        cfg.dt, cfg.mass, cfg.gravity, cfg.t_max, cfg.omega_max)
        np_, nv, nq, nw = QUAD.quad_step(d_pos, d_vel, d_quat, d_omega, thrust, omega_cmd, wind, ge,
                                         cfg.mass, cfg.tau_omega, cfg.drag_quad, cfg.drag_lin, cfg.gravity, cfg.dt)
        np_ = torch.cat([np_[:, :2].clamp(-cfg.extent, cfg.extent), np_[:, 2:3].clamp(cfg.min_alt, ceiling)], -1)
        al3 = alive[:, None]
        d_pos = torch.where(al3, np_, d_pos); d_vel = torch.where(al3, nv, torch.zeros_like(nv))
        d_quat = torch.where(al3, nq, d_quat); d_omega = torch.where(al3, nw, torch.zeros_like(nw))

        # COLLISION — FULLY VECTORIZED, no python branch: a body inside any solid within crash_r is DESTROYED.
        # Empty masks make every write below a no-op, so no `if newhit.any()` guard is needed; the crash tallies
        # accumulate ON-GPU as tensors (no per-tick host sync -> the int() reads happen once, in `stats`).
        sdf = COL.shape_sdf3(d_pos[:, None, :] - scn["obs_c"][None], scn["obs_h"][None], scn["obs_cyl"][None])  # [D,O]
        nidx = sdf.argmin(1); mind = sdf.gather(1, nidx[:, None])[:, 0]     # nearest solid + which obstacle it is
        newhit = alive & (mind < cfg.crash_r)                              # freshly-crashed drones this tick
        crash_leaf = crash_leaf + ((nidx >= leaf_lo) & newhit).sum()       # foliage / trunk-branch tallies (tensors)
        crash_wood = crash_wood + ((nidx < leaf_lo) & newhit).sum()
        oc = assigned[newhit]; oc = oc[oc >= 0]                            # cherries the crashers owned (empty if none)
        cstate[oc] = torch.where(cstate[oc] == 2, torch.full_like(cstate[oc], 4), torch.zeros_like(cstate[oc]))  # carried->LOST, claimed->free
        assigned = torch.where(newhit, torch.full_like(assigned, -1), assigned)
        alive = alive & ~newhit

        # STAGE TRANSITIONS — FULLY VECTORIZED: PICK when a SEEK drone reaches its cherry, DROP at the bucket.
        reach_r = torch.where(stage == 1, torch.full_like(geo, cfg.drop_r), torch.full_like(geo, cfg.pick_r))
        reached = alive & (geo < reach_r)
        pick = reached & (stage == 0) & (assigned >= 0)             # SEEK drone reached its cherry
        drop = reached & (stage == 1)                              # CARRY drone reached the bucket
        cstate[assigned[pick]] = 2                                 # picked cherries -> carried   (empty pick -> no-op)
        stage = torch.where(pick, torch.ones_like(stage), stage)   # picker -> CARRY
        cstate[assigned[drop]] = 3                                 # delivered
        stage = torch.where(drop, torch.zeros_like(stage), stage)  # dropper -> free/SEEK
        assigned = torch.where(drop, torch.full_like(assigned, -1), assigned)

        assign_random()                                            # give any newly-free drone a random cherry (vectorized, no branch)

        if tick % cfg.rec_stride == 0:                              # record a frame (subsampled)
            frames.append(_frame(scn, d_pos, d_quat, cstate, assigned, stage, alive,
                                 dist_all, flow_all, field_idx, cfg, cell, device))

        if bool(((cstate == 3) | (cstate == 4)).all()) or not bool(alive.any()):   # nothing left to deliver / no drones
            done_tick = tick; break

    delivered = int((cstate == 3).sum()); lost = int((cstate == 4).sum())
    stats = dict(delivered=delivered, lost=lost, total=M, drones=D, survivors=int(alive.sum()),
                 crash_leaf=int(crash_leaf), crash_wood=int(crash_wood),   # tensors accumulated on-GPU -> read once here
                 ticks=(done_tick if done_tick is not None else cfg.max_ticks),
                 seconds=(done_tick if done_tick is not None else cfg.max_ticks) * cfg.dt,
                 forbidden=forbidden, nav_xyz=nav_xyz, cell=cell,
                 dist_all=dist_all, flow_all=flow_all, src_pos=src_pos)
    return frames, stats


def main():
    device = "cuda" if torch.cuda.is_available() else "cpu"
    out = _bs.argv[1] if len(_bs.argv) > 1 else _bo.path.join(_bo.path.dirname(_bo.path.abspath(__file__)), "videos", "harvest.mp4")
    _bo.makedirs(_bo.path.dirname(out), exist_ok=True)
    cfg = CFG()
    scn = SCENE.build_orchard(device=device, seed=1, n_cherries=64, n_drones=3)
    print(f"[harvest] device={device}  drones={scn['spawns'].shape[0]}  cherries={scn['cherries'].shape[0]}  "
          f"grid {cfg.G}x{cfg.G}x{cfg.Gz} (cell {2*cfg.extent/(cfg.G-1):.2f} m)")
    t0 = time.time()
    frames, stats = run(scn, cfg, device)
    print(f"[harvest] delivered {stats['delivered']}/{stats['total']} cherries in {stats['seconds']:.1f}s sim "
          f"({stats['ticks']} ticks); drones survived {stats['survivors']}/{stats['drones']} "
          f"(crashes: {stats['crash_leaf']} leaf, {stats['crash_wood']} wood; lost cherries {stats['lost']}); "
          f"wall {time.time()-t0:.1f}s; {len(frames)} frames")
    import render_cherry as RC
    RC.render(frames, scn, stats, cfg, out)
    print(f"[harvest] wrote {out}")


if __name__ == "__main__":
    main()
