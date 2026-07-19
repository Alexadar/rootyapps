"""Offline scene generation — the droneswarm counterpart of monstro/froggo schedule.py.

EVERYTHING random is baked here, once, per env, seeded `base_seed + e` (family idiom), so an N-env
batch is byte-identical to N single-env builds — the determinism / batch==singles tests rely on it.
The sim hot path then has ZERO randomness: in-sim "random" (AA dispersion outcome) is a table lookup
into a pregenerated uniform roll, not an RNG call.

Per env this produces (returned as a dict of numpy arrays; env_drone converts to tensors):
  hf        [N,G,G]   fBm heightfield (metres)
  obst      [N,O,7]   typed static obstacles: (x, y, z_center, hx, hy, hz, is_cyl)  [trees=cyl, rocks=box]
  e_type    [N,E]     0 = soldier (social-force), 1 = tank (unicycle)
  e_pos0    [N,E,2]   initial enemy ground positions
  e_head0   [N,E]     initial enemy headings (rad)
  base_pos  [N,3]     drone launch point (the "factory")
  spawn_tick[N,D]     tick at which each drone launches (staggered)
  spawn_off [N,D,3]   small launch scatter around base
  mean_wind [N,3]     per-env mean wind vector (m/s)
  gust      [N,T,3]   Dryden turbulence series (m/s)  [oracles.wind.dryden_series_np]
  aa_roll   [N,T,E]   uniform(0,1) per tick per shooter -> deterministic AA hit resolution
  scale     [N]       = engage_range (the obs normalizer)

Offline setup: python loops over envs / octaves are fine here (NOT the sim hot path), exactly as
monstro/froggo schedule.py loops. Marked SETUP-LOOP-OK.
"""
from dataclasses import dataclass

import numpy as np

from world_config_drone import WorldConfig
from oracles.wind import dryden_series_np, dryden_length_scales


def _fbm_heightfield(rng, G, amp, octaves=4):
    """Fractional-Brownian-motion heightfield [G,G] in metres, peak-to-peak ~= amp. Sum of value-noise
    octaves: white noise on a coarse grid, bilinearly upsampled to GxG, halving amplitude per octave.
    Deterministic from rng. SETUP-LOOP-OK (octave loop, offline)."""
    h = np.zeros((G, G), np.float64)
    total_w = 0.0
    for o in range(octaves):                                     # SETUP-LOOP-OK
        cells = 2 ** (o + 1) + 1                                 # coarse grid resolution for this octave
        coarse = rng.standard_normal((cells, cells))
        # bilinear upsample coarse -> GxG
        ys = np.linspace(0, cells - 1, G)
        xs = np.linspace(0, cells - 1, G)
        y0 = np.floor(ys).astype(int).clip(0, cells - 2); ty = ys - y0
        x0 = np.floor(xs).astype(int).clip(0, cells - 2); tx = xs - x0
        c00 = coarse[np.ix_(y0, x0)]; c10 = coarse[np.ix_(y0, x0 + 1)]
        c01 = coarse[np.ix_(y0 + 1, x0)]; c11 = coarse[np.ix_(y0 + 1, x0 + 1)]
        TX = tx[None, :]; TY = ty[:, None]
        up = c00 * (1 - TX) * (1 - TY) + c10 * TX * (1 - TY) + c01 * (1 - TX) * TY + c11 * TX * TY
        w = 0.5 ** o
        h += w * up
        total_w += w
    h /= total_w
    h -= h.min()
    if h.max() > 1e-9:
        h *= amp / h.max()
    return h.astype(np.float32)


def _bilerp(hf, x, y, extent):
    """Numpy bilinear sample of hf [G,G] at world (x,y) arrays -> heights. Mirrors oracles.terrain."""
    G = hf.shape[0]
    gx = np.clip((x / extent + 1.0) * 0.5 * (G - 1), 0, G - 1)
    gy = np.clip((y / extent + 1.0) * 0.5 * (G - 1), 0, G - 1)
    ix = np.floor(gx).astype(int).clip(0, G - 2); tx = gx - ix
    iy = np.floor(gy).astype(int).clip(0, G - 2); ty = gy - iy
    h00 = hf[iy, ix]; h10 = hf[iy, ix + 1]; h01 = hf[iy + 1, ix]; h11 = hf[iy + 1, ix + 1]
    return h00 * (1 - tx) * (1 - ty) + h10 * tx * (1 - ty) + h01 * (1 - tx) * ty + h11 * tx * ty


# ======================================================================================================
# GENERALIZED OBSTACLE FIELD — one data-driven sampler; "buildings" and "trees" are just spec rows, and
# any future kind (walls, pillars, craters, ...) is a new ObstacleClass with ZERO new code. Everything the
# sim needs is the shared 3D box/cylinder primitive (oracles/collide3), so a class only has to say which
# primitive, how many, how big (per axis), and where — the [[obstacle-shape-primitives]] rule made concrete.
# ======================================================================================================
@dataclass
class ObstacleClass:
    """One kind of obstacle. All sizes are HALF-EXTENTS in metres (radius for cyl). Per env a random
    count in [count_lo,count_hi] is drawn; each obstacle is sized independently per axis from the (lo,hi)
    ranges and rejection-placed in the region. shape: 'box' (rock/building) | 'cyl' (tree/pillar)."""
    name: str
    shape: str                                   # 'box' | 'cyl'
    count: tuple                                 # (lo, hi) inclusive random count per env
    hx: tuple                                    # (lo, hi) half-extent x   (radius for cyl)
    hy: tuple                                    # (lo, hi) half-extent y   (box only; cyl reuses hx)
    hz: tuple                                    # (lo, hi) half-height
    region: str = "combat"                       # 'combat' -> combat_half zone, else arena_half
    region_frac: float = 0.85                    # placed within +/- region_frac * zone_half
    min_sep: float = 2.0                         # min centre-to-centre spacing (rejection sampling)
    xr: tuple = None                             # optional explicit x-band (lo,hi) overriding the region (showcase)
    yr: tuple = None                             # optional explicit y-band (lo,hi) overriding the region


# The default training field: chunky buildings you route AROUND (6-10 m tall, near the ~10 m ceiling) + trees.
# Placed across the ARENA (not just the combat zone) so a swarm CROSSING the map meets cover along the way
# (with spawn-distance randomization this teaches long ribbon crossings, not just the compact central fight).
DEFAULT_OBSTACLE_FIELD = [
    ObstacleClass("building", "box", (0, 4), (1.5, 3.0), (1.5, 3.0), (3.0, 5.0), "arena", 0.80, min_sep=3.5),
    ObstacleClass("tree",     "cyl", (0, 10), (0.4, 1.2), (0.4, 1.2), (3.0, 8.0), "arena", 0.80, min_sep=1.5),
]


def sample_obstacle_field(classes, O, rng, hf, ext, combat_half, arena_half, keepout=None):
    """Fill an [O,7] obstacle array (x, y, z_center, hx, hy, hz, is_cyl) from a list of ObstacleClass specs.

    VARIABLE COUNT: rows beyond the drawn total stay ZERO -> env's obst_mask masks them (env_drone.py:96),
    the SDF already honours it. Positions are rejection-sampled clear of `keepout` (list of (x,y,radius),
    e.g. drone spawns + enemies) and of previously-placed obstacles (per-class min_sep). GENERAL: not one
    per-kind literal lives here — every number comes from the spec. SETUP-LOOP-OK (offline, <=~12 obstacles)."""
    obst = np.zeros((O, 7), np.float32)
    keep = list(keepout) if keepout is not None else []
    placed = []                                              # (centre_xy, footprint_radius) already placed
    row = 0
    for cls in classes:                                      # SETUP-LOOP-OK (a handful of classes)
        n = int(rng.integers(cls.count[0], cls.count[1] + 1))
        zone_half = (combat_half if (cls.region == "combat" and combat_half > 0) else arena_half) * cls.region_frac
        xr = cls.xr if cls.xr is not None else (-zone_half, zone_half)   # explicit band overrides region (showcase)
        yr = cls.yr if cls.yr is not None else (-zone_half, zone_half)
        for _ in range(n):                                   # SETUP-LOOP-OK (<= count.hi obstacles)
            if row >= O:
                break                                        # out of capacity -> silently drop (raise --obstacles)
            hx = float(rng.uniform(*cls.hx))
            hy = float(rng.uniform(*cls.hy)) if cls.shape == "box" else hx   # cyl: hy = radius = hx
            foot_r = max(hx, hy)                             # circumscribing footprint radius (for spacing)
            cand = None
            for _try in range(24):                           # SETUP-LOOP-OK (bounded placement retries)
                c = np.array([rng.uniform(*xr), rng.uniform(*yr)], np.float32)
                if any(np.hypot(*(c - k[0])) < (foot_r + k[1]) for k in ((np.array(kx[:2]), kx[2]) for kx in keep)):
                    continue                                 # too close to a keepout point (spawn/enemy)
                if any(np.hypot(*(c - p[0])) < (foot_r + p[1] + cls.min_sep) for p in placed):
                    continue                                 # too close to an already-placed obstacle
                cand = c; break
            if cand is None:
                continue                                     # couldn't place -> leave row zero (fewer obstacles)
            hz = float(rng.uniform(*cls.hz))
            gz = float(_bilerp(hf, np.array([cand[0]]), np.array([cand[1]]), ext)[0])
            obst[row] = [cand[0], cand[1], gz + hz, hx, hy, hz, 1.0 if cls.shape == "cyl" else 0.0]
            placed.append((cand, foot_r))
            row += 1
    return obst


def _fill_env(cfg, D, E, O, T, seed, obstacle_field=None):
    """Build one env's scene (all arrays for row e). Returns a dict of per-env arrays."""
    rng = np.random.default_rng(seed)
    G, ext, ah = cfg.terrain_grid, cfg.arena_half, cfg.arena_half
    ch = cfg.combat_half if cfg.combat_half > 0 else ah          # central combat zone (spawns confined here)
    hf = _fbm_heightfield(rng, G, cfg.terrain_amp)
    # (obstacles are generated LAST — after enemies/spawns exist — so they can be kept clear of the launch
    #  line and off the enemies; see the sample_obstacle_field call below.)

    # enemies: E units, first n_tank tanks then soldiers (fixed split), scattered, on terrain
    n_tank = E // 3                                              # ~1/3 tanks, 2/3 soldiers
    e_type = np.zeros(E, np.float32); e_type[:n_tank] = 1.0
    epx = rng.uniform(-0.7 * ch, 0.7 * ch, E)                    # enemies spawn in the central combat zone
    epy = rng.uniform(-0.7 * ch, 0.7 * ch, E)
    e_pos0 = np.stack([epx, epy], -1).astype(np.float32)
    e_head0 = rng.uniform(-np.pi, np.pi, E).astype(np.float32)

    # drone base: a launch point near an arena rim, above terrain; drones staggered over the first ~1.2 s
    bang = rng.uniform(-np.pi, np.pi)
    # SPAWN-DISTANCE domain randomization: the launch radius varies from just outside the combat zone out to
    # near the arena edge, so the swarm learns SHORT and LONG crossings (generalizes to the field->trees->
    # buildings ribbon, not just the compact central fight it used to always spawn into).
    br = rng.uniform(0.5 * ch, 0.9 * ah)
    bx, by = br * np.cos(bang), br * np.sin(bang)                 # launch point at a RANDOM distance from centre
    bz = _bilerp(hf, np.array([bx]), np.array([by]), ext)[0] + 0.5 * cfg.ceiling
    base_pos = np.array([bx, by, bz], np.float32)
    spawn_tick = np.floor(rng.uniform(0, 1.2 / cfg.dt, D)).astype(np.float32)   # launch ticks
    # launch FORMATION: spread the drones along a lateral LINE perpendicular to the base->centre heading,
    # spanning much of the arena, so the swarm DEPLOYS DISTRIBUTED (a real launcher line) rather than stacked
    # on one point. Diagnosed root cause of the dogpile: identical drones from a single point (0 m spawn
    # spread) + a SHARED deterministic policy = a perfectly symmetric blob that can never disperse, and the
    # balanced target-assignment can't break the tie because co-located drones have identical distance rows.
    # A spread launch gives each drone a different nearest enemy + different obs from tick 0, so the swarm
    # fans out and the assignment reward finally has asymmetric rows to disperse.
    inward = -np.array([bx, by], np.float32); inward /= (np.linalg.norm(inward) + 1e-6)  # base -> centre
    perp = np.array([-inward[1], inward[0]], np.float32)                                  # lateral line dir
    lat = np.linspace(-0.5 * ch, 0.5 * ch, D).astype(np.float32)                          # even lateral slots (combat zone)
    jit = rng.uniform(-0.6, 0.6, (D, 3)).astype(np.float32); jit[:, 2] *= 0.3             # small tie-break jitter
    spawn_off = np.zeros((D, 3), np.float32)
    spawn_off[:, 0] = perp[0] * lat + jit[:, 0]                                           # lateral formation + jitter
    spawn_off[:, 1] = perp[1] * lat + jit[:, 1]
    spawn_off[:, 2] = jit[:, 2]

    # obstacles: the GENERALIZED field, placed LAST so we can keep it clear of the launch line and off the
    # enemies (buildings may stand AMONG enemies as cover, just not exactly on one). Rows past the drawn
    # count stay zero -> masked by env.obst_mask. See sample_obstacle_field / DEFAULT_OBSTACLE_FIELD.
    field = obstacle_field if obstacle_field is not None else DEFAULT_OBSTACLE_FIELD
    spawn_xy = base_pos[:2][None, :] + spawn_off[:, :2]                                   # [D,2] drone spawn slots
    keepout = ([(float(base_pos[0]), float(base_pos[1]), 3.0)]                            # launch origin
               + [(float(s[0]), float(s[1]), 2.0) for s in spawn_xy]                      # each drone spawn slot
               + [(float(e[0]), float(e[1]), 1.2) for e in e_pos0])                       # enemies (avoid overlap)
    obst = sample_obstacle_field(field, O, rng, hf, ext, ch, ah, keepout=keepout)

    # wind: per-env mean + Dryden gust series
    wspeed = rng.uniform(cfg.wind_mean_lo, cfg.wind_mean_hi)
    wdir = rng.uniform(-np.pi, np.pi)
    mean_wind = np.array([wspeed * np.cos(wdir), wspeed * np.sin(wdir), 0.0], np.float32)
    # turbulence INTENSITY (sigma) scales with wind level; correlation time uses the vehicle AIRSPEED
    # as the Dryden advection velocity V (MIL-F-8785C semantics — frozen turbulence past a moving drone),
    # NOT the wind speed. A representative drone airspeed gives gusts that vary within the episode.
    sigma = cfg.dryden_sigma_frac * max(wspeed, 1.0)
    v_encounter = 0.6 * cfg.drone_speed_max                     # representative drone airspeed [m/s]
    L3 = dryden_length_scales(0.0, cfg.dryden_L_w, cfg.dryden_L_uv)
    gust = dryden_series_np(rng, T, cfg.dt, v_encounter, [sigma, sigma, sigma], L3)   # [T,3]

    # AA deterministic hit rolls
    aa_roll = rng.random((T, E)).astype(np.float32)

    return dict(hf=hf, obst=obst, e_type=e_type, e_pos0=e_pos0, e_head0=e_head0,
                base_pos=base_pos, spawn_tick=spawn_tick, spawn_off=spawn_off,
                mean_wind=mean_wind, gust=gust, aa_roll=aa_roll)


def _pack(rows, cfg, D, E, O, T):
    """Stack a list of per-env dicts into batched [N,...] arrays."""
    N = len(rows)
    out = {k: np.stack([r[k] for r in rows], 0) for k in rows[0]}
    out["scale"] = np.full(N, cfg.engage_range, np.float32)
    out["D"], out["E"], out["O"], out["T"] = D, E, O, T
    return out


def build(cfg, n_envs, D, E, O, T, base_seed=0, obstacle_field=None):
    """Training schedule: N independent scenes, env e seeded base_seed+e (byte-identical to a single
    build of that seed). `obstacle_field` overrides DEFAULT_OBSTACLE_FIELD. SETUP-LOOP-OK (offline env loop)."""
    rows = [_fill_env(cfg, D, E, O, T, base_seed + e, obstacle_field) for e in range(n_envs)]   # SETUP-LOOP-OK
    return _pack(rows, cfg, D, E, O, T)


def build_eval(cfg, seeds, D, E, O, T, base_seed=10_000, seed_stride=7919, obstacle_field=None):
    """Held-out eval schedule: `seeds` scenes, env s seeded base_seed + s*seed_stride — disjoint from
    any sane training seed range and byte-identical to independent single-env builds."""
    rows = [_fill_env(cfg, D, E, O, T, base_seed + s * seed_stride, obstacle_field) for s in range(seeds)]  # SETUP-LOOP-OK
    return _pack(rows, cfg, D, E, O, T)
