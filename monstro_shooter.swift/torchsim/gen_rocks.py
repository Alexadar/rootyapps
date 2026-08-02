"""One-time generator: scatter static circle obstacles ("rocks") into the surround map JSONs.

Adds a `"rocks": [[x, y, radius], ...]` key to every datasets/surround/{train,eval}/*.json.
Per map (seeded by map id -> reproducible): random-radius rocks covering ~AREA_FRAC of the full
arena area (2*arenaHalf)^2, rejecting any rock that (a) crowds the origin player-start, (b) sits on
the +/-spawnRadius spawn-perimeter band (else monsters spawn inside a rock), (c) exits the arena, or
(d) overlaps another rock (kept separated -> convex/sparse, no maze pockets). Edits data files only.
"""
import glob, json, os
import numpy as np

AREA_FRAC = 0.03          # target rock coverage as a fraction of the full arena area
ORIGIN_CLEAR = 50.0       # keep rocks this far off the origin (player start)
SPAWN_BAND = 15.0         # keep rocks this far off the spawn-perimeter shell
ROCK_SEP = 10.0           # min gap between rocks (no clustering)
R_LO_FRAC, R_HI_FRAC = 0.05, 0.12   # rock radius range as a fraction of arenaHalf
N_CAND = 3000             # candidate pool sampled in one vectorized batch (rejection-sampled, no python loop)


def _gen(arena_half, spawn_r, seed):
    """Vectorized rejection sampler — no python placement loop. Draw a batch of candidate circles, mask by the
    independent constraints (origin clearance, spawn-perimeter band), then keep a candidate only if no EARLIER
    surviving candidate overlaps it (strictly-lower-triangular pairwise test guarantees any two kept circles are
    disjoint). Finally a cumulative-area cutoff stops at ~AREA_FRAC coverage."""
    rng = np.random.default_rng(seed)
    r = rng.uniform(R_LO_FRAC * arena_half, R_HI_FRAC * arena_half, N_CAND)
    lim = arena_half - r
    cx = rng.uniform(-1.0, 1.0, N_CAND) * lim
    cy = rng.uniform(-1.0, 1.0, N_CAND) * lim
    ok = ((np.hypot(cx, cy) >= ORIGIN_CLEAR + r) &                                   # (a) origin clearance
          (np.abs(np.maximum(np.abs(cx), np.abs(cy)) - spawn_r) >= r + SPAWN_BAND))  # (b) spawn-perimeter band
    d = np.hypot(cx[:, None] - cx[None, :], cy[:, None] - cy[None, :])               # [N,N] pairwise center dist
    ov = d < (r[:, None] + r[None, :] + ROCK_SEP)                                    # overlapping pairs
    keep = ok & ~(np.tril(ov, -1) & ok[None, :]).any(1)                             # (d) no earlier ok candidate overlaps
    area = np.pi * r * r
    target = AREA_FRAC * (2.0 * arena_half) ** 2
    keep &= np.cumsum(np.where(keep, area, 0.0)) <= target                          # cumulative-area cutoff
    sel = np.stack([cx[keep], cy[keep], r[keep]], 1).round(2)
    return sel.tolist(), float(area[keep].sum()), target


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    paths = sorted(glob.glob(os.path.join(here, "datasets", "surround", "train", "*.json")) +
                   glob.glob(os.path.join(here, "datasets", "surround", "eval", "*.json")))
    for p in paths:
        cfg = json.load(open(p))
        ah = float(cfg.get("arenaHalf", 6000.0))
        sr = float(cfg.get("spawnRadius", 260.0))
        rocks, covered, target = _gen(ah, sr, int(cfg.get("id", 0)))
        cfg["rocks"] = rocks
        json.dump(cfg, open(p, "w"), indent=2)
        pct = 100.0 * covered / ((2.0 * ah) ** 2)
        print(f"{os.path.basename(p):10}  arena={ah:.0f} spawn={sr:.0f}  rocks={len(rocks):2d}  "
              f"coverage={pct:4.1f}%  (target {100*AREA_FRAC:.0f}%)")


if __name__ == "__main__":
    main()
