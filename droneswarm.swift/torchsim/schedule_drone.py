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


def _fill_env(cfg, D, E, O, T, seed):
    """Build one env's scene (all arrays for row e). Returns a dict of per-env arrays."""
    rng = np.random.default_rng(seed)
    G, ext, ah = cfg.terrain_grid, cfg.arena_half, cfg.arena_half
    ch = cfg.combat_half if cfg.combat_half > 0 else ah          # central combat zone (spawns confined here)
    hf = _fbm_heightfield(rng, G, cfg.terrain_amp)

    # obstacles: trees (cylinders) + rocks (boxes) scattered, seated on terrain, away from arena centre
    obst = np.zeros((O, 7), np.float32)
    ox = rng.uniform(-0.85 * ah, 0.85 * ah, O)
    oy = rng.uniform(-0.85 * ah, 0.85 * ah, O)
    is_cyl = (rng.random(O) < 0.6).astype(np.float32)            # 60% trees, 40% rocks
    tree_r = rng.uniform(0.4, 1.2, O); tree_h = rng.uniform(3.0, 8.0, O)
    rock_h = rng.uniform(1.0, 3.0, O); rock_wx = rng.uniform(1.0, 3.0, O); rock_wy = rng.uniform(1.0, 3.0, O)
    hx = np.where(is_cyl > 0.5, tree_r, rock_wx)
    hy = np.where(is_cyl > 0.5, tree_r, rock_wy)
    hz = np.where(is_cyl > 0.5, tree_h, rock_h)
    gz = _bilerp(hf, ox, oy, ext)
    obst[:, 0] = ox; obst[:, 1] = oy; obst[:, 2] = gz + hz       # z_center sits the base on terrain
    obst[:, 3] = hx; obst[:, 4] = hy; obst[:, 5] = hz; obst[:, 6] = is_cyl

    # enemies: E units, first n_tank tanks then soldiers (fixed split), scattered, on terrain
    n_tank = E // 3                                              # ~1/3 tanks, 2/3 soldiers
    e_type = np.zeros(E, np.float32); e_type[:n_tank] = 1.0
    epx = rng.uniform(-0.7 * ch, 0.7 * ch, E)                    # enemies spawn in the central combat zone
    epy = rng.uniform(-0.7 * ch, 0.7 * ch, E)
    e_pos0 = np.stack([epx, epy], -1).astype(np.float32)
    e_head0 = rng.uniform(-np.pi, np.pi, E).astype(np.float32)

    # drone base: a launch point near an arena rim, above terrain; drones staggered over the first ~1.2 s
    bang = rng.uniform(-np.pi, np.pi)
    bx, by = 0.72 * ch * np.cos(bang), 0.72 * ch * np.sin(bang)   # launch from the COMBAT-ZONE rim (central square)
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


def build(cfg, n_envs, D, E, O, T, base_seed=0):
    """Training schedule: N independent scenes, env e seeded base_seed+e (byte-identical to a single
    build of that seed). SETUP-LOOP-OK (offline env loop)."""
    rows = [_fill_env(cfg, D, E, O, T, base_seed + e) for e in range(n_envs)]   # SETUP-LOOP-OK
    return _pack(rows, cfg, D, E, O, T)


def build_eval(cfg, seeds, D, E, O, T, base_seed=10_000, seed_stride=7919):
    """Held-out eval schedule: `seeds` scenes, env s seeded base_seed + s*seed_stride — disjoint from
    any sane training seed range and byte-identical to independent single-env builds."""
    rows = [_fill_env(cfg, D, E, O, T, base_seed + s * seed_stride) for s in range(seeds)]   # SETUP-LOOP-OK
    return _pack(rows, cfg, D, E, O, T)
