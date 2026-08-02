# Game rules — three-way comparison

> **STATUS: both torchsim AND MetalGame now implement the full canonical ruleset** (every row,
> including the combat extras: ammo/reload, bullet spread, multi-pellet, penetration, exo speed,
> immediate-contact pulse, defense min-floor). **Parity verified**: same WorldConfig + schedule +
> Core ML models → worst per-tick position Δ = **0.0072 world units** across 9 games, kills + hp
> identical. The sprite game (real animated monster/player/bullet art) runs on Metal.


Canonical = **OLD SpriteKit** + 3 user deviations (marked ★): #1 fixed 1/30 sim + render lerp,
#14 monster HP pool, #28 monster control = ML net. **The "Proposed Metal" column = the canonical spec,
applied to BOTH torchsim AND MetalGame** (two-env gameplay parity). All physics constants live in one
shared `WorldConfig` so the two engines can't drift.

Legend: ✅ matches OLD · ❌ diverges from OLD · — not implemented

| # | Rule | OLD SpriteKit (KEEP / truth) | torchsim NOW | MetalGame NOW (demo) | Proposed Metal |
|---|---|---|---|---|---|
| 1 | Tick / dt | variable real-time (~1/60, ProMotion 1/120) | fixed **1/30** ❌ | **1/60** ❌ | **fixed 1/30 sim + render lerp 60/120** ★ |
| 2 | Player speed | 300 (× exo speed) | 300 ✅ (no exo mult ❌) | 300 ✅ | 300 × exo |
| 3 | Diagonal move | ×**0.75** when both axes>0.1 | none ❌ | none ❌ | ×0.75 |
| 4 | Exo speed mult | yes (default 1.0) | no ❌ | no ❌ | yes |
| 5 | Map size | 12000×12000 (half 6000) | 6000 default ✅ (invented per-map `arenaHalf` ❌) | **half 1100** ❌ | 12000 |
| 6 | Player clamp | ±(map/2 − 30) | ±(arena−30) ✅ | ±1100 ❌ | ±(6000−30) |
| 7 | Monster steering | direct **and** arc/turn-rate | direct+arc ✅ (OR networked enemy ❌) | **direct only** ❌ | direct+arc |
| 8 | Turn rate | 34 | 34 ✅ | — ❌ | 34 |
| 9 | Monster speed | from YAML (per-type) | from YAML ✅ | **130+type·30 hardcoded** ❌ | from YAML |
| 10 | Stop at contact | playerRadius+boxW/2 | 30+boxW/2 ✅ | **none** ❌ | 30+boxW/2 |
| 11 | Spawn geometry | **viewport-derived** box (vp/2/camScale+100) | fixed 830×650 ❌ | random radius 650–950 ❌ | viewport box (pin value) |
| 12 | Spawn timing | per-wave SKAction, k·spawnInterval(1.0), due at startTime | precomputed schedule, start+k·1.0 ✅ | every 0.5s random, **no waves/map** ❌ | wave schedule from map |
| 13 | Spawn type | random from wave's types | random (numpy) ✅ | random 0–4 ❌ | random from wave types |
| 14 | **Monster death** | **ONE-SHOT kill** (HP loaded, never used) | **HP pool** ✅ | **HP pool** (hp 6+t·4) ✅ | **HP pool (monster HP)** ★ |
| 15 | Bullet speed | YAML (pistol 800) | YAML ✅ | 800 hardcoded ~✅ | YAML |
| 16 | Bullet range | YAML shotRange (pistol 500) | YAML ✅ | 40-tick lifetime (~530u) ❌ | YAML range |
| 17 | Bullet damage | YAML (moot — one-shot) | YAML ✅ | 10 hardcoded ❌ | n/a (one-shot) |
| 18 | Fire cadence | time: now−lastShot ≥ shotDelay, gated on shooting+ammo | every round(shotDelay/dt) ticks, **always** ❌ | every 0.5s **always** ❌ | time-gated + ammo |
| 19 | Ammo / magazine / reload | **yes** (magazineSize, reloadTime, currentAmmo) | none ❌ | none ❌ | yes |
| 20 | Bullet spread | **yes** atan2(deviation,500) | none ❌ | none ❌ | yes |
| 21 | Multi-pellet | **yes** bulletsPerShot (shotgun 6) | 1 ❌ | 1 ❌ | yes |
| 22 | Penetration | **yes** penetrationPower (1/2/5) | 1 (dies on hit) ❌ | 1 ❌ | yes |
| 23 | Collision radius | bulletR(6)+box/2 | 6+boxW/2 ✅ | **20 hardcoded** ❌ | 6+boxW/2 |
| 24 | Contact radius | playerR(30)+monR+5 | 30+boxW/2+5 ✅ | **34 hardcoded** ❌ | 30+boxW/2+5 |
| 25 | Contact damage | monster.damage (YAML) | mon_dmg ✅ | **2+type hardcoded** ❌ | YAML damage |
| 26 | Contact cadence | **immediate pulse on new contact** + periodic 1s | periodic 1s only ❌ | every frame (dmg·dt) ❌ | immediate + 1s |
| 27 | Defense | max(dmg−def, **0.4 min every 4th**) | max(dmg−def, 0) ❌ | none ❌ | max(dmg−def, floor) |
| 28 | Monster control | **scripted** (no network) | networked enemy | scripted | **ML net (no scripting)** ★ |
| 29 | Player control | human input | networked 8-dim | Core ML **6-dim** ❌ | Core ML (match obs to whatever player model trains on) |
| 30 | Config-driven | yes (YAML + map JSON) | yes ✅ | **no (all hardcoded)** ❌ | yes |

## Biggest divergences (decision points)
- **#14 one-shot vs HP pool** — OLD = one-shot kill; BOTH torchsim and Metal use an HP pool. Load-bearing for how the player learns to shoot.
- **#28 scripted vs networked monsters** — OLD has NO enemy net; torchsim trained one. If we keep OLD, the **monster model has no home** (drop it).
- **#11 spawn box** — OLD is viewport-derived; both derived impls use a fixed box.
- **#19–22 ammo / spread / multi-pellet / penetration** — OLD has all; neither derived impl models them.
- **#1 dt** — three different answers.

**You decide the "Proposed Metal" column.** Default I filled = OLD (keep the SpriteKit rules); torchsim then has to be fixed to match wherever it shows ❌.
