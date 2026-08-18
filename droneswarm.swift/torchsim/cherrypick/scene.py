"""cherrypick.scene — the static ORCHARD: a natural-looking cherry-tree branch (a forked, tapering
limb structure), a soft leaf canopy, cherries hanging in PAIRS on Y-stems, a collection bucket, and the
drone spawns.

Two representations, deliberately separated:
  * COLLISION (what the route field must avoid) — built ONLY from the shared box/cylinder SDF primitive
    (common.oracles.collide3): the trunk (cylinder) + chains of small cubes tracing each branch + a few
    leaf clumps. This is a clean, navigable proxy ([[obstacle-shape-primitives]]).
  * RENDER decoration (what the eye sees) — smooth tapering branch TUBES, a dense green FOLIAGE cloud,
    and brown cherry STEMS. Finer than the collision proxy (as real tree twigs are finer than any
    collision hull); the renderer draws these, the field never sees them.

Frame convention: world +z up, ground at z=0; tree at the origin, bucket a few metres away, drones start
low near the bucket. Layout is deterministic (seeded).
"""
import math
import torch

_BOX = 0.0
_CYL = 1.0


def build_orchard(device="cpu", seed=0, n_cherries=8, n_drones=4):
    gen = torch.Generator().manual_seed(seed)
    obs_c, obs_h, obs_cyl = [], [], []                            # COLLISION obstacles
    segs = []                                                     # RENDER branch tubes: [x0,y0,z0,x1,y1,z1,r0,r1]

    def add_obs(c, h, cyl):
        obs_c.append([float(c[0]), float(c[1]), float(c[2])]); obs_h.append([h, h, h]); obs_cyl.append(cyl)

    def branch(p0, p1, r0, r1, collide=True):
        """A limb from p0->p1 tapering r0->r1: a render tube, and (if collide) a chain of small cubes."""
        segs.append([*p0, *p1, r0, r1])
        if collide:
            L = math.dist(p0, p1); n = max(1, int(round(L / 0.6)))
            for i in range(1, n + 1):                             # skip i=0 (shared with the parent joint)
                t = i / n; p = [p0[k] + (p1[k] - p0[k]) * t for k in range(3)]
                add_obs(p, max(0.16, r0 + (r1 - r0) * t), _BOX)   # cube half >= 0.16 so thin twigs still register

    # --- WOOD: a BIG tree — a tall trunk + 5 primary limbs radiating up-and-out, each splitting into 3 twigs
    #     (a full, wide, high crown). More branches = more for the field to weave through. ---
    for zc in (1.5, 3.1, 4.7):
        add_obs((0.0, 0.0, zc), 0.52 - 0.02 * zc, _CYL)          # trunk collision: stacked, slightly tapering cyls
    segs.append([0, 0, 0.0, 0, 0, 6.4, 0.58, 0.32])              # trunk tube (taller)
    prims = [((0.0, 0.0, 5.6), (4.6, 0.6, 8.0), 0.34, 0.18),     # 5 UPPER primary limbs fanning out radially
             ((0.0, 0.0, 5.8), (2.7, 3.6, 8.1), 0.31, 0.16),
             ((0.0, 0.0, 5.7), (-1.2, 4.2, 7.8), 0.29, 0.15),
             ((0.0, 0.0, 5.3), (2.6, -3.4, 7.6), 0.31, 0.16),
             ((0.0, 0.0, 5.1), (-2.8, -2.6, 7.2), 0.27, 0.14),
             # 3 LOWER branches UNDER the crown (varied length/height/dir) -> the drone must weave INSIDE the
             # tree, around these, to reach the fruit that hangs among them.
             ((0.0, 0.0, 4.0), (3.9, -1.6, 5.0), 0.30, 0.16),   # low, reaches +x and DIPS down
             ((0.0, 0.0, 4.4), (-3.2, 1.4, 5.6), 0.28, 0.15),   # low -x+y, longer
             ((0.0, 0.0, 3.6), (1.0, 3.4, 4.7), 0.26, 0.13)]    # low +y, short & stubby
    tips = []
    for p0, p1, r0, r1 in prims:
        branch(p0, p1, r0, r1); tips.append((p1, r1))
    twig_tips, twigs = [], []                                    # twigs = (start, end) segments, for cherry anchoring
    for (tp, tr) in tips:                                         # 3 twigs off each primary, spreading OUTWARD + up
        hor = (tp[0] ** 2 + tp[1] ** 2) ** 0.5 + 1e-6
        ox, oy = tp[0] / hor, tp[1] / hor                        # outward unit (xy); (-oy,ox) is sideways
        for k in range(3):
            u = torch.rand(1, generator=gen).item(); v = torch.rand(1, generator=gen).item()
            rad = 1.4 + 1.0 * u                                   # twig length outward
            q = (tp[0] + rad * ox + 1.2 * (v - 0.5) * (-oy),
                 tp[1] + rad * oy + 1.2 * (v - 0.5) * (ox),
                 tp[2] + 0.4 + 0.8 * u)
            branch(tp, q, tr, tr * 0.5, collide=False)           # thin twigs are RENDER-only (collision = trunk+limbs+leaves)
            twig_tips.append(q); twigs.append((tp, q))
    leaf_lo = len(obs_c)                                          # collision obstacles from here on are foliage clumps

    # --- LEAVES: collision clumps at the twig tips + limb ends; a dense FOLIAGE point-cloud around each ---
    clump_centers = twig_tips + [(tp[0] * 0.7, tp[1] * 0.7, tp[2] + 0.25) for tp, _ in tips]
    fol_c, fol_s = [], []                                        # foliage sprite centres + green-shade factor (0..1)
    for cc in clump_centers:
        add_obs((cc[0], cc[1], cc[2]), 0.5, _BOX)                # ONE collision clump (the field avoids this)
        for _ in range(34):                                      # many small leaf sprites scattered around it -> soft canopy
            off = [(torch.rand(1, generator=gen).item() - 0.5) for _ in range(3)]
            fol_c.append([cc[0] + 1.9 * off[0], cc[1] + 1.9 * off[1], cc[2] + 1.4 * off[2]])
            fol_s.append(torch.rand(1, generator=gen).item())

    obs_c = torch.tensor(obs_c, dtype=torch.float32, device=device)
    obs_h = torch.tensor(obs_h, dtype=torch.float32, device=device)
    obs_cyl = torch.tensor(obs_cyl, dtype=torch.float32, device=device)
    wood_segs = torch.tensor(segs, dtype=torch.float32, device=device)
    foliage_c = torch.tensor(fol_c, dtype=torch.float32, device=device)
    foliage_s = torch.tensor(fol_s, dtype=torch.float32, device=device)

    # --- CHERRIES in PAIRS on a Y-stem: each pair shares an ANCHOR on a branch; two cherries hang below it
    #     on stems, slightly apart. cherry_stem[m] is the anchor (drawn as the stem top while the cherry is
    #     on the tree). Anchors sit under the twig tips so the cherries hang in reachable open air below. ---
    npair = (n_cherries + 1) // 2
    perm = torch.randperm(len(twigs), generator=gen).tolist()   # visit twigs in a shuffled, repeating order -> even spread
    cherries, stems = [], []
    for p in range(npair):                                       # each pair hangs on a Y-stem, SPREAD around the whole tree
        (sx, sy, sz), (ex, ey, ez) = twigs[perm[p % len(twigs)]]
        t = 0.2 + 0.75 * torch.rand(1, generator=gen).item()     # random point ALONG the twig (not a fixed slot)
        ax = sx + (ex - sx) * t; ay = sy + (ey - sy) * t; az = sz + (ez - sz) * t - 0.25
        ang = 6.2832 * torch.rand(1, generator=gen).item()       # random pair orientation (the two cherries splay out)
        dx, dy = 0.42 * math.cos(ang), 0.42 * math.sin(ang)
        drop = 1.1 + 1.1 * torch.rand(1, generator=gen).item()   # random dangle depth
        for s in (-1, 1):
            if len(cherries) >= n_cherries:
                break
            cherries.append([ax + dx * s, ay + dy * s, az - drop - 0.3 * torch.rand(1, generator=gen).item()])
            stems.append([ax, ay, az])
    cherries = torch.tensor(cherries, dtype=torch.float32, device=device)
    cherry_stem = torch.tensor(stems, dtype=torch.float32, device=device)

    bucket = torch.tensor([-5.8, 0.0, 0.45], dtype=torch.float32, device=device)   # bin on the ground
    sp = [[-7.5, (i - (n_drones - 1) / 2.0) * 1.6, 1.0] for i in range(n_drones)]   # drones fan out near the bucket
    spawns = torch.tensor(sp, dtype=torch.float32, device=device)

    return dict(obs_c=obs_c, obs_h=obs_h, obs_cyl=obs_cyl, leaf_lo=leaf_lo,
                wood_segs=wood_segs, foliage_c=foliage_c, foliage_s=foliage_s,
                cherries=cherries, cherry_stem=cherry_stem, bucket=bucket, spawns=spawns)
