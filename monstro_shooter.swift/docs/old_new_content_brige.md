# Monstro Shooter — campaign structure of the Flash original, and how to dissect it

**Purpose:** recover the shipped campaign of the original VK game so a storyline / chapter can be
written on top of real content rather than invented content. This doc records **what the structure
is**, **how it was derived**, and **what is still unresolved and where the answer lives**.

**Status:** structural reconstruction, derived from the ported map payloads (§1–§9) and from the
`ItemTypes` / `Monsters` / `Levels` seed rows (§10–§13). Not yet confirmed against the production
database. §7 lists the four queries that would confirm it.

**Contents:** §1–§3 sources and the dissection rule · §4–§6 the campaign · §7–§9 verification,
method, open questions · §10–§13 the equipment economy and the per-map auto-loadout table.

---

## 1. Source inventory

Everything below lives under `monstro_shooter.swift/`. `old_shooter` is a symlink to
`~/Projects/Bdgilka` (8.9 GB — the original Flash project: AS3 source, SVN trunk, DB, JPEXS).

| Artifact | Path | What it is |
|---|---|---|
| Production DB (detached) | `old_shooter/DB/msprod.mdf` | 742 MB, Feb 2016. **The authority.** Needs SQL Server to read. |
| Production DB (backup) | `old_shooter/Backups/prod` | 2.6 GB SQL Server native `.bak`, Nov 2015 |
| Dev / test DBs | `old_shooter/Backups/msDEV` (1.5 GB), `msTest` (72 MB), `Backups/Test/*/MonstroShooterTest.mdf` | older, not authoritative |
| Schema, plain text | `old_shooter/src/trunk/Database/20150626 - TestRC/Shema.sql` | 19 tables, UTF-16. Readable without SQL Server. |
| Seed rows, plain text | `…/20150626 - TestRC/Data.sql` | UTF-16. **TestRC data, not prod** — drop point ids differ (26–31 `Квадрат 1–6`). Use for column semantics only. |
| Ported maps | `monstro_client/Resources/MapConfigs/map_*.json` | 251 files = 250 DB maps + 1 synthetic (`9999`) |
| Ported drop points | `monstro_client/Resources/droppoints.json` | 17 rows, **`id`/`name`/`nameEn` only** — see §6 |
| Monster stats | `monstro_client/Resources/MapConfigs/monster_types.json` | 24 types; only 6 implemented in the client |

Reading `Shema.sql` / `Data.sql` requires a UTF-16 decode:

```python
s = open(path, 'rb').read().decode('utf-16', errors='replace')
```

---

## 2. The three tables that carry the campaign

```sql
DropPoints(Id, Name xml, Descritpion xml, LevelRequirement int,
           LocationX int, LocationY int, OrderId int, Removed bit)

Maps(Id, DefaultName xml, OwnerName, Description xml, DropPointId, OwnerId,
     EnergyCost, HardMoneyCost, LandingDuration, MonstersCounts xml,
     MonstersTypes xml, GameResource, Country, LastRenameDate, RenameCost,
     RenameCostMult, MaximumVictims xml, Removed bit, OrderNumber int)

GameRounds(Id, RoundState, StartRoundTime, EndRoundTime, RoundDuration, PlayerId,
           MapId, InitialInventoryState xml, InitialEnergyValue, InitialHardMoneyValue,
           Survived bit, MonstersKilled xml, MonstersEnrolled xml, IsRoundCheated bit,
           EarnedMoney, EarnedExperience)
```

- **`DropPoints` is the chapter.** `LocationX/Y` place it on the world map, `LevelRequirement`
  gates it, `OrderId` sequences it, `Removed` retires it.
- **`Maps` is the mission.** `OrderNumber` sequences it *within* its drop point.
- **`GameRounds` is the empirical truth** — one row per round actually played. It is
  round-summary telemetry: there are **no per-tick trajectories anywhere in the schema**, so this
  data can rank difficulty and prove which maps shipped, but cannot train a control policy.

---

## 3. The dissection rule

### What does *not* work

- **`Maps.Removed`** — `false` for all 250 ported maps. Either the extraction pre-filtered, or no
  map was ever soft-deleted. Useless as a discriminator.
- **`Maps.OwnerId` / `OwnerName` / `Country`** — `null` for all 250. The player-owned-map feature
  (`RenameCost`, `RenameCostMult`, `LastRenameDate` exist for it) was never populated in the dump.
- **Localization presence** — 185 of 251 maps carry an `en-us` row, but in the live English client
  *every* map displayed the string `First map!`. The `en-us` row proves a localization pass ran, not
  that the map shipped. Do not use bilinguality as a filter.

### What works

**Retirement happened at the drop-point level, not the map level.** In the TestRC seed, exactly one
drop point carries `Removed = 1` — id 3, `Тест`, described *"Тест период времени * прирост монстров *
длительность карты"*. In the ported data, drop point 3 is precisely the one holding 13
single-monster-type balance rigs.

So the production filter is:

```
production ⇔ DropPoints.Removed = 0
             (and the drop point's map ladder is complete & its roster chains)
```

`DropPoints.Removed` / `OrderId` / `LevelRequirement` were **dropped during the port** —
`droppoints.json` kept only `id`, `name`, `nameEn`. They exist only in `msprod.mdf`.

### Structural proxy used here (until the DB is read)

A drop point counts as production when all four hold:

1. **Roster chains.** Its monster-type set overlaps the previous chapter's by ~2 ids and extends it.
   The whole live campaign forms one unbroken chain 1→18.
2. **Ladder is complete.** `OrderNumber` runs 100…2000 in even steps with no gaps
   (or 100/500/1000/1500/2000 for the 5-map endgame missions).
3. **Volume and duration escalate** monotonically across the chapter and against the previous one.
4. **Names are mission names, not editor notes.** Scratch names like
   `№ 3 23(35) второй пистолет берем` or `к 5 3 волны 7,15,17 (т55)` mark unfinished authoring.

---

## 4. The production campaign — 11 drop points, 177 maps

Order is by roster escalation (each chapter hands off ~2 monster ids to the next), **not** by drop
point id. Mobs/run = sum of `monsterSpawnWaves[].count`.

| # | DP | Chapter (RU / EN) | Maps | Dur | Mobs/run | Monster ids | Tileset |
|---|---|---|---|---|---|---|---|
| 1 | 18 | Секретный объект / Secret Facility | 19 | 30–50s | 25–93 | 1,2,3 | map_1 |
| 2 | 8 | Вторая зона / Second Zone | 20 | 50–80s | 45–170 | 1–5 | map_2 |
| 3 | 9 | Третья зона / Third Zone | 20 | 80–90s | 131–500 | 2,4–9 | map_2/3 |
| 4 | 10 | Четвёртая зона / Fourth Zone | 20 | 90–100s | 125–732 | 4,6,8–11 | map_4 |
| 5 | 11 | Пятая зона / Fifth Zone | 20 | 100s | 330–1478 | 5,8–14 | map_5 |
| 6 | 12 | Шестая зона / Sixth Zone | 20 | 100–110s | 288–1519 | 6,9–16 | map_6 |
| 7 | 13 | Седьмая зона / Seventh Zone | 20 | 100–120s | 288–1358 | 13,15–18 | map_7 (+map_8 ×1) |
| 8 | 14 | Спецоперация Alpha | 5 | 120s | 901–949 | 15–18 | map_2 |
| 9 | 15 | Спецоперация Beta | 5 | 120s | 1050–1315 | 16,17,18 | map_2 |
| 10 | 17 | Элитная миссия / Elite Mission | 5 | 130s | 1417–1557 | 16,17,18 | map_2 |
| ∥ | 7 | Десант / Landing | 23 | 40–110s | 150–1750 | 1–5 | map_2 |

Map ids in play order (`OrderNumber`, then `Id`):

- **DP18 Secret Facility** — `17, 18, 19, 20, 14, 1058, 1059, 1056, 1060, 1061, 1062, 1063, 1055, 1064, 1065, 1066, 1067, 1068, 1057`
- **DP8 Second Zone** — `1069, 1155, 1156, 1157, 1070, 1158, 1159, 1160, 1118, 1071, 1119, 1161, 1162, 1163, 1072, 1164, 1120, 1121, 1165, 1073`
- **DP9 Third Zone** — `1074, 1122, 1123, 1075, 1076, 1124, 1166, 1167, 1168, 1077, 1169, 1174, 1173, 1171, 1078, 1172, 1170, 1125, 1126, 1079`
- **DP10 Fourth Zone** — `1080, 1175, 1176, 1177, 1081, 1127, 1128, 1129, 1130, 1082, 1178, 1179, 1180, 1181, 1083, 1182, 1183, 1184, 1185, 1084`
- **DP11 Fifth Zone** — `1085, 1186, 1086, 1187, 1088, 1188, 1190, 1189, 1131, 1090, 1191, 1192, 1193, 1132, 1091, 1195, 1196, 1133, 1194, 1089`
- **DP12 Sixth Zone** — `1092, 1201, 1205, 1204, 1093, 1199, 1198, 1200, 1197, 1094, 1134, 1135, 1136, 1137, 1095, 1206, 1203, 1207, 1202, 1096`
- **DP13 Seventh Zone** — `1208, 1213, 1212, 1209, 1097, 1214, 1216, 1218, 1217, 1098, 1140, 1210, 1211, 1215, 1099, 1138, 1139, 1220, 1219, 1100`
- **DP14 SpecOp Alpha** — `1101, 1102, 1103, 1104, 1105`
- **DP15 SpecOp Beta** — `1107, 1108, 1109, 1110, 1111`
- **DP17 Elite Mission** — `1112, 1113, 1114, 1115, 1116`
- **DP7 Десант** — `1029…1050, 1053` (contiguous, 23 maps)

### Two structural facts a storyline must respect

**DP7 «Десант» is a parallel ladder, not chapter 2.** All 23 maps have `OrderNumber = 0` (the client
falls back to id order), internal names are systematic (`К1 Десант 001…023`), three are tagged
`"Блиц"` and the finale `"Месиво"`. Volume runs 150 → 1750 mobs — higher than Elite Mission — but on
the *starter* roster (types 1–5). It reads as an event / meat-grinder track hung off the early
monster set, playable alongside the campaign rather than inside it.

**Zones are 20-map ladders; DP14/15/17 are 5-map ladders** spaced at `OrderNumber`
100/500/1000/1500/2000 — endgame missions on a 20-slot grid, not zones. The spacing is the tell.

---

## 5. Excluded — 74 maps

| DP | Group | Maps | Why |
|---|---|---|---|
| 3 | Тренировочная база | 13 (`1141–1153`) | Single-monster-type isolation rigs, one type each (4,5,6,8,9,10,11,12,13,14,15,17,18), all identical: 102 mobs / 100s / map_7. Names are literally `жук 2 id 4`, `птиц 2 id 5`. **This is the drop point that is `Removed = 1` in the TestRC seed.** |
| 4 | Испытательный полигон | 17 (`16, 21–37`) | Every map `OrderNumber = 0`; `Тест жук` runs 600s against 1 monster. QA ladder. |
| 25 | Боевая зона Omega | 9 (`1221–1229, 1235`) | Gapped ladder (100–600, then 1300, 1400, 1900); names are editor notes. |
| 26 | Передовая | 15 (`1240–1254`) | Only user of monster ids 22, 23, 24 — then reverts to 1,2,3 mid-ladder. Roster chains to nothing. |
| 27 | Штурмовая операция | 9 (`1255–1263`) | Gapped (100, 200, 800–1300, 1600). |
| 28 | Последний рубеж | 10 (`1264–1273`) | Complete 100–1000 ladder, highest ids in the DB, roster 4–9 — restarts the difficulty curve instead of continuing DP13. |
| 1 | — | 1 (`9999`) | `Test - 1 Bug`. Synthetic, added by the Swift port; not in the DB. |

**DP 25/26/27/28 deserve a second look before being written off.** They hold the highest map ids in
the database and share one signature: near-complete ladders, no localization, scratch names, and
rosters that do not chain onto the live campaign. Read as *a second content pass that was in flight
when the game stopped*. Useful as story material (what the designers were building next); not canon.
This is the single call in this document most likely to change once `GameRounds` is read.

---

## 6. Naming — treat with suspicion

`droppoints.json` is the only source for the chapter names above, and it was written during the
Swift port, not extracted verbatim.

- **Corroborated:** `Десант` (map payloads say `К1 Десант 001`); `Вторая…Седьмая зона` (consistent
  designer series, matches the id ordering).
- **Uncorroborated:** `Секретный объект`, `Боевая зона Omega`, `Передовая`, `Последний рубеж` appear
  nowhere else in the tree.
- **Certainly generated:** every `nameEn`. The DB stores `Name` as `Localizable` XML and the seed
  rows carry `ru-ru` only. In the live English client every map was displayed as `First map!`; the
  Russian internal names were the real ones.

Do not build proper nouns into a storyline from this file until §7 query 1 returns.

---

## 7. What the production DB would settle

No SQL Server tooling on this machine (no docker / sqlcmd / pymssql). Podman is available
(arm64, applehv) — `mssql/server` is amd64-only, so it needs `--platform linux/amd64` under Rosetta.
Attaching the detached `msprod.mdf` (742 MB) is cheaper than restoring `Backups/prod` (2.6 GB); mind
the podman VM disk size.

Four queries, in priority order:

1. **Authoritative chapters + world map + gates + true names**
   ```sql
   SELECT Id, LevelRequirement, LocationX, LocationY, OrderId, Removed,
          CAST(Name AS nvarchar(max)), CAST(Descritpion AS nvarchar(max))
   FROM DropPoints ORDER BY OrderId;
   ```
   Replaces every inference in §3–§4 with fact, and yields the world-map geometry — a route with
   coordinates, which is the actual spine of a chapter.

2. **Which maps players really played** (settles §5's DP 25/26/27/28 question)
   ```sql
   SELECT MapId, COUNT(*) rounds, AVG(CAST(Survived AS float)) win_rate,
          MIN(StartRoundTime) first_played, MAX(StartRoundTime) last_played
   FROM GameRounds WHERE ISNULL(IsRoundCheated,0)=0
   GROUP BY MapId ORDER BY rounds DESC;
   ```
   Zero rounds ⇒ never shipped. This is the empirical production set to diff against §4.

3. **All 24 monster types** — resolves the 18 the port lists as "Unknown" in
   `monstro_client/Resources/maps.md`
   ```sql
   SELECT Id, CAST(Name AS nvarchar(max)), CAST(Data AS nvarchar(max)) FROM Monsters;
   ```

4. **Equipment the port never wired in** (33 JSONs exist, none reachable in game)
   ```sql
   SELECT Id, ItemClass, LevelRequirement, RankRequirement,
          CAST(Name AS nvarchar(max)), CAST(Data AS nvarchar(max)) FROM ItemTypes;
   ```

Also worth pulling once the server is up: `Maps.MaximumVictims` / `MonstersCounts` /
`MonstersTypes` raw XML (to verify the port's wave decoding), and `Quests` (102 rows in TestRC — the
original's own mission-flavour text, the closest thing to existing narrative).

---

## 8. Reproducing the classification

All of §4 and §5 is derivable offline from the ported JSONs. From
`monstro_client/Resources/`:

```python
import json, glob, collections
ms = [json.load(open(f)) for f in glob.glob('MapConfigs/map_*.json')]
dp = {d['id']: d['nameEn'] for d in json.load(open('droppoints.json'))}

by = collections.defaultdict(list)
for m in ms:
    by[m['dropPointId']].append(m)

for d in sorted(by):
    lst   = sorted(by[d], key=lambda m: (m['orderNumber'], m['id']))
    types = sorted({t for m in lst for w in m['monsterTypes'] for t in w['monsterTypeIds']})
    mobs  = [sum(w['count'] for w in m['monsterSpawnWaves']) for m in lst]
    durs  = [m['landingDuration'] for m in lst]
    gaps  = [m['orderNumber'] for m in lst]
    print(d, dp.get(d), len(lst), f'{min(durs)}-{max(durs)}s',
          f'{min(mobs)}-{max(mobs)} mobs', types, gaps)
```

Read the three signals in this order: **roster chain → ladder gaps → volume curve.** Name quality is
the tie-breaker, never the primary test.

---

## 9. Open questions

1. Is DP18 `Секретный объект` really chapter 1, or a tutorial preceding DP7? Its maps hold the oldest
   ids in the DB (`14, 17–20`) at 25–93 mobs / 30–50s — tutorial scale. Query 1 (`LevelRequirement`)
   answers it.
2. Did DP 25/26/27/28 ever go live? Query 2 answers it.
3. Was DP7 `Десант` gated, or open alongside the campaign? Query 1 (`LevelRequirement` + `OrderId`).
4. What are monster ids 19, 20, 21? Present in `Monsters` (24 rows) but used by **no** map. Cut
   content — query 3 reveals what they were.
5. Do the drop points form a geographic route (`LocationX/Y`)? If they do, the chapter's structure is
   already drawn and does not need inventing.

---

## 10. The equipment economy

Source: `ItemTypes` rows in `…/20150626 - TestRC/Data.sql` (61 parsed), `Monsters` (22 rows),
`Levels` (15 rows). All three are plain text — no SQL Server needed.

> **Caveat carried through §10–§13: these are TestRC values, not production.** Prod prices may have
> been retuned. The *structure* (two parallel lines, price parity, the ladder order) is unlikely to
> have changed; the *numbers* need query 4 in §7 to confirm.

> **Do not use `monstro_client/Resources/Equipment/*.json` for this.** Those 33 files were written
> during the Swift port, not extracted: `pistol.json` says damage 10 / range 800 / free, while the
> real `Пистолет Стартовый` is damage 2 / range 200 / 23 credits. `light_armor.json` also changes
> the semantics of `speed` — see §10.3.

### 10.1 Two parallel lines

`ItemClass 1 = Exoskeleton`, `ItemClass 2 = Weapon` (note the order — it is not the obvious one).
Market items (`MarketAvailability = 1`) split into two lines that run side by side:

- **Soft line** — bought with credits (`BuyPriceSoft`), gated by `LevelRequirement`. Free-to-play.
- **Elite line** — bought with crystals (`BuyPriceHard`), gated by `RankRequirement`, `LevelRequirement = 0`.
  Each elite item carries a `DiscountPriceSoft` that is *the soft price of the tier it parallels*.

### 10.2 The pairing law — price parity

**An armor and a weapon of the same tier cost the same.** In soft credits, exactly:

| soft-equivalent | Armor | Weapon |
|---|---|---|
| 23 | Броня Стартовая | Пистолет Стартовый |
| 121 / 130 | Броня Рекрута · Броня Рекрута Элита (rk1) | Пистолет Рекрута (62) · Элитный Пистолет (rk1) |
| 750 / 760 | Броня Солдата · Элитная Броня Солдата (rk2, 800) | Узи (650) · Элитный Узи (rk1, 750) |
| **2500** | Броня Ветерана · Элитная Броня Ветерана (rk3) | Автомат · Элитный Автомат (rk2) |
| **10000** | Броня Офицера · Элитная Броня Офицера (rk4) | Дробовик · Элитный Дробовик (rk2) |
| **30000** | Броня Генерала · Элитная Броня Генерала (rk5, 36000) | Пулемет · Элитный пулемет (rk4) |
| 70000 | Броня Героя Колонизации (rk5) | — (weapon line tops out one tier lower) |

The four bolded rows are exact matches, and the ranks align (rk1↔rk1, rk2↔rk2, …). **This is the
pairing signal.** `OrderId` corroborates it for the first three tiers (armor and weapon both run
100, 200, 300, …) but drifts after ord 400 because the armor line has 12 items and the weapon line 13.
Price parity does not drift — use it.

### 10.3 Armor ladder (12 market items)

Sorted by `Defence`. `Speed` is the hero's **absolute per-frame speed** (`SimpleHero.as`:
`speed = exoskeletonVO.speed`), *not* a multiplier — the top suit is 2.29× the starter's, and it is
both the tankiest and the fastest. There is no speed/armor trade-off anywhere in this ladder.

| rank | ord | id | line | gate | price | soft-eq | Def | Speed | name |
|---|---|---|---|---|---|---|---|---|---|
| A0 | 100 | 114 | soft | lvl 0 | 23 c | 23 | 0 | 0.7 | Броня Стартовая |
| A1 | 200 | 115 | soft | lvl 2 | 121 c | 121 | 0 | 0.8 | Броня Рекрута |
| A2 | 300 | 113 | elite | rank 1 | 10 hard | 121 | 1 | 0.9 | Броня Рекрута Элита |
| A3 | 400 | 116 | soft | lvl 4 | 760 c | 750 | 2 | 1.0 | Броня Солдата |
| A4 | 700 | 1086 | elite | rank 2 | 50 hard | 800 | 5 | 1.2 | Элитная Броня Солдата |
| A5 | 500 | 117 | soft | lvl 7 | 2500 c | 2500 | 5.3 | 1.1 | Броня Ветерана |
| A6 | 600 | 112 | elite | rank 3 | 70 hard | 2500 | 7.5 | 1.3 | Элитная Броня Ветерана |
| A7 | 700 | 1085 | soft | lvl 9 | 10000 c | 10000 | 8.2 | 1.2 | Броня Офицера |
| A8 | 800 | 1088 | elite | rank 4 | 100 hard | 10000 | 11 | 1.4 | Элитная Броня Офицера |
| A9 | 900 | 1087 | soft | lvl 10 | 30000 c | 30000 | 12 | 1.3 | Броня Генерала |
| A10 | 1000 | 1089 | elite | rank 5 | 160 hard | 36000 | 14 | 1.5 | Элитная Броня Генерала |
| A11 | 1100 | 1090 | elite | rank 5 | 300 hard | 70000 | 15 | 1.6 | Броня Героя Колонизации |

Defence subtracts flat from incoming damage: `actual = max(dmg − defence, minDamage)`, with
`minDamage = 0.4` every 4th hit (`BaseHero.as`, see `old-shooter-gameplay.md`).

### 10.4 Weapon ladder (13 market items)

Sorted by `OrderId` (the shop's own order). `burst` = damage × pellets / shotDelay.
`sust` = damage × pellets × cage / (cage × shotDelay + rechargeDelay) — the honest number, since it
pays for reloads.

| rank | ord | id | line | gate | price | soft-eq | dmg×pellets | delay | cage | range | burst | **sust** | name |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| W0 | 100 | 85 | soft | lvl 0 | 23 c | 23 | 2×1 | 350 | 6 | 200 | 6 | **3** | Пистолет Стартовый |
| W1 | 200 | 86 | soft | lvl 2 | 62 c | 62 | 4×1 | 300 | 12 | 330 | 13 | **8** | Пистолет Рекрута |
| W2 | 300 | 87 | elite | rank 1 | 30 hard | 130 | 10×1 | 350 | 12 | 400 | 29 | **21** | Элитный Пистолет |
| W3 | 400 | 96 | soft | lvl 3 | 650 c | 650 | 4×1 | 100 | 24 | 210 | 40 | **21** | Узи |
| W4 | 500 | 1091 | elite | rank 1 | 40 hard | 750 | 8×1 | 100 | 24 | 350 | 80 | **42** | Элитный Узи |
| W5 | 600 | 99 | soft | lvl 6 | 2500 c | 2500 | 15×1 | 130 | 32 | 400 | 115 | **69** | Автомат |
| W6 | 700 | 1092 | elite | rank 2 | 50 hard | 2500 | 18×1 | 130 | 36 | 400 | 138 | **92** | Элитный Автомат |
| W7 | 800 | 106 | soft | lvl 7 | 10000 c | 10000 | 10×**7** | 300 | 9 | 250 | 233 | **129** | Дробовик |
| W8 | 900 | 1093 | elite | rank 2 | 60 hard | 10000 | 14×**9** | 300 | 12 | 450 | 420 | **261** | Элитный Дробовик |
| W9 | 1000 | 105 | soft | lvl 10 | 20000 c | 20000 | 20×1 | 350 | 5 | **700** | 57 | **24** | Снайперская Винтовка |
| W10 | 1100 | 1094 | elite | rank 3 | 80 hard | 20000 | 30×1 | 350 | 5 | **700** | 86 | **35** | Снайперская Винтовка Элиты |
| W11 | 1200 | 101 | soft | lvl 10 | 30000 c | 30000 | 15×1 | 130 | 48 | 500 | 115 | **78** | Пулемет |
| W12 | 1300 | 1095 | elite | rank 4 | 100 hard | 30000 | 20×1 | 130 | 54 | 500 | 154 | **117** | Элитный пулемет |

**Finding — the shop's price ladder is not monotone in power.** `Элитный Дробовик` (W8, ord 900)
sustains **261 dps**; the two tiers the shop prices *above* it, the snipers, sustain 24–35, and the
top-priced `Элитный пулемет` sustains 117. The shotguns are the strongest killing tools in the game
by a factor of 2, and they cost less than half of what the machinegun tier costs. The snipers are
paying for **range 700** (2.8× the shotgun's 250) — they are a different weapon class sold inside a
linear price ladder. Any auto-picker that treats "most expensive = best" will hand the player a
downgrade at ord 1000.

### 10.5 Level thresholds and monster rewards

`Levels.Experience` (cumulative XP to reach a level):

| lvl | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| XP | 0 | 122 | 901 | 1601 | 2561 | 4097 | 7201 | 16701 | 22401 | 35841 | 57335 | 100001 | 160001 | 256001 | 409601 |

`Monsters.Data` XML, per type (`Health`, `Damage`, `Speed`, `BodyRadius`, `ExperienceReward`,
`MoneyReward`, `KickPeriod`, `TurnRate`, `AgressionRadius`):

| id | HP | dmg | speed | XP | $ | id | HP | dmg | speed | XP | $ |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 Жук | 4 | 2 | 1.50 | 2 | 2 | 10 Жук 4 | 8 | 8 | 2.10 | 6 | 10 |
| 2 Ходячий | 10 | 4 | 0.94 | 3 | 3 | 11 Птиц 4 | 12 | 11 | 2.50 | 9 | 9 |
| 3 Птиц | 6 | 2 | 2.10 | 4 | 2 | 12 Ходячий 4 | 20 | 13 | 1.50 | 7 | 10 |
| 4 Жук 2 | 4 | 5 | 1.80 | 4 | 3 | 13 Жук 5 | 17 | 10 | 1.80 | 7 | 9 |
| 5 Птиц 2 | 6 | 5 | 2.30 | 5 | 5 | 14 Птиц 5 | 17 | 10 | 1.80 | 8 | 11 |
| 6 Жук 3 | 9 | 5 | 1.90 | 4 | 5 | **15 Ходячий 5** | 26 | 21 | 1.90 | **48** | **69** |
| 7 Ходячий 2 | 16 | 6 | 1.40 | 4 | 8 | **16 Птиц 6** | 17 | 17 | 2.80 | **67** | **47** |
| 8 Птиц 3 | 9 | 7 | 2.30 | 7 | 7 | **17 Жук 6** | 11 | 16 | 2.40 | **41** | **41** |
| 9 Ходячий 3 | 16 | 10 | 1.50 | 5 | 8 | **18 Ходячий 6** | 26 | 23 | 2.00 | **53** | **77** |

Plus a **tier zero below the starter set** — used only by DP26 `Передовая`, the unfinished zone:

| id | HP | dmg | speed | XP | $ | name |
|---|---|---|---|---|---|---|
| 22 | 4 | 2 | 1.10 | 2 | 1 | Жук №0 |
| 23 | 10 | 4 | 0.60 | 2 | 2 | Ходячий № 0 |
| 24 | 6 | 2 | 1.10 | 3 | 2 | Птиц № 0 |

That these three are *strictly weaker than id 1* is strong evidence for the §5 reading: DP26 was a
re-onboarding pass, building a gentler ramp underneath the shipped curve. (There is also id 1006
`Димон`, HP 1 / XP 20 — a joke build, ignore.)

Note the reward cliff at ids 15–18: 41–77 credits each against 2–11 for everything below. The
endgame chapters pay 10× per kill.

---

## 11. What the economy actually supports (simulation)

Walking the §4 campaign once, no replays, no deaths: each map's clear pays
`Σ count × MoneyReward` and `Σ count × ExperienceReward` (wave counts split evenly across the
roster active at that wave's `startTime`); level follows the §10.5 table; after each map, buy the
cheapest available upgrade in either slot while affordable.

Result over the 154 campaign maps: **level 15, 2.10 M XP, 2.13 M credits earned.**

| first map | zone | lvl | credits | armor | weapon |
|---|---|---|---|---|---|
| 17 | Secret Facility | 1 | 0 | Броня Стартовая | Пистолет Стартовый |
| 19 | Secret Facility | 2 | 84 | Броня Стартовая | Пистолет Рекрута |
| 20 | Secret Facility | 2 | 109 | Броня Рекрута | Пистолет Рекрута |
| 1062 | Secret Facility | 3 | 211 | Броня Рекрута | Узи |
| 1065 | Secret Facility | 4 | 92 | Броня Солдата | Узи |
| 1160 | Second Zone | 6 | 152 | Броня Солдата | Автомат |
| 1120 | Second Zone | 7 | 367 | Броня Ветерана | Автомат |
| 1077 | Third Zone | 8 | 1113 | Броня Ветерана | Дробовик |
| 1171 | Third Zone | 9 | 866 | Броня Офицера | Дробовик |
| 1081 | Fourth Zone | 10 | 1513 | Броня Офицера | Снайперская Винтовка |
| 1083 | Fourth Zone | 11 | 3399 | Броня Офицера | Пулемет |
| 1186 | Fifth Zone | 11 | 4233 | **Броня Генерала** | **Пулемет** |

**The soft line is exhausted at Fifth Zone, map 2 of 20 — 101 maps from the end.** From there to
Elite Mission the free player buys nothing: every remaining purchase is crystal-priced and
rank-gated. By the last chapter they are sitting on 1.7 M unspendable credits.

Two consequences, and they matter more for design than for the loadout table:

1. **Chapters 6–10 have no free progression.** The elite line is not optional flavour there — it is
   the only remaining curve. Any port that drops the crystal economy must replace it with something,
   or the back half of the campaign is flat.
2. **The credit economy is broken at the top** by the id 15–18 reward cliff: income scales 10× while
   the price ladder stops at 30 000. This is worth fixing rather than reproducing.

---

## 12. Auto-loadout: the per-map table

### 12.1 The question, answered

**Drop-point granularity is too coarse.** Third Zone alone needs five different pairs across its 20
maps, and Fifth Zone four. The data supports — and requires — **map spans inside a drop point**.
The table below is exactly that: contiguous runs of map ids, in play order, each with one pair.

### 12.2 The rule (what an auto-picker should implement)

Prices give the ladder and the pairing; the map payload decides where on the ladder you stand:

```
threat(map)  = Σ count_i · Damage_i / Σ count_i        # mean incoming damage per monster
load(map)    = Σ count_i · Health_i / LandingDuration  # HP the player must delete, per second

armor  = cheapest tier with Defence ≥ threat − 4          # keep chip damage under ~4/hit
weapon = cheapest tier whose best-so-far sust ≥ 1.15 · load
ratchet: never downgrade a slot on a later map
```

`− 4` and `× 1.15` are the two tuning knobs; they were chosen so the ladder starts at A0/W0 on the
first map and lands on the top pair by the last chapter. `best-so-far` (rather than the tier's own
dps) is what keeps §10.4's non-monotone price ladder from picking a downgrade.

The rule needs nothing but the map JSON and the item table — no player state — so it can run
offline as a lookup table (the one below) or live per map.

### 12.3 Campaign — 154 maps, in play order

| # | Armor | Weapon | Zone | maps |
|---|---|---|---|---|
| 1 | A0 Броня Стартовая (def 0) | W1 Пистолет Рекрута | Secret Facility | `17, 18, 19, 20, 14, 1058` |
| 2 | A0 Броня Стартовая | W2 Элитный Пистолет | Secret Facility | `1059, 1056, 1060, 1061, 1062, 1063, 1055, 1064, 1065, 1066, 1067, 1068, 1057` |
| 3 | A0 Броня Стартовая | W2 Элитный Пистолет | Second Zone | `1069, 1155, 1156, 1157, 1070, 1158, 1159, 1160, 1118, 1071, 1119, 1161, 1162, 1163, 1072, 1164` |
| 4 | A2 Броня Рекрута Элита (def 1) | W2 Элитный Пистолет | Second Zone | `1120, 1121, 1165, 1073` |
| 5 | A2 Броня Рекрута Элита | W2 Элитный Пистолет | Third Zone | `1074, 1122, 1123` |
| 6 | A3 Броня Солдата (def 2) | W2 Элитный Пистолет | Third Zone | `1075` |
| 7 | A3 Броня Солдата | W4 Элитный Узи | Third Zone | `1076, 1124, 1166, 1167` |
| 8 | A3 Броня Солдата | W5 Автомат | Third Zone | `1168, 1077` |
| 9 | A3 Броня Солдата | W6 Элитный Автомат | Third Zone | `1169, 1174, 1173, 1171, 1078, 1172, 1170` |
| 10 | A4 Элитная Броня Солдата (def 5) | W6 Элитный Автомат | Third Zone | `1125, 1126, 1079` |
| 11 | A4 Элитная Броня Солдата | W6 Элитный Автомат | Fourth Zone | `1080, 1175, 1176, 1177, 1081, 1127, 1128, 1129` |
| 12 | A6 Элитная Броня Ветерана (def 7.5) | W6 Элитный Автомат | Fourth Zone | `1130, 1082, 1178, 1179, 1180, 1181, 1083, 1182, 1183, 1184` |
| 13 | A6 Элитная Броня Ветерана | W7 Дробовик | Fourth Zone | `1185, 1084` |
| 14 | A6 Элитная Броня Ветерана | W7 Дробовик | Fifth Zone | `1085, 1186, 1086, 1187, 1088` |
| 15 | A6 Элитная Броня Ветерана | W8 Элитный Дробовик | Fifth Zone | `1188, 1190, 1189, 1131, 1090, 1191, 1192, 1193, 1132, 1091` |
| 16 | A6 Элитная Броня Ветерана | W12 Элитный пулемет | Fifth Zone | `1195, 1196, 1133, 1194, 1089` |
| 17 | A6 Элитная Броня Ветерана | W12 Элитный пулемет | Sixth Zone | `1092, 1201, 1205, 1204, 1093, 1199, 1198, 1200, 1197, 1094, 1134` |
| 18 | A8 Элитная Броня Офицера (def 11) | W12 Элитный пулемет | Sixth Zone | `1135, 1136` |
| 19 | A9 Броня Генерала (def 12) | W12 Элитный пулемет | Sixth Zone | `1137, 1095, 1206, 1203, 1207, 1202, 1096` |
| 20 | A9 Броня Генерала | W12 Элитный пулемет | Seventh Zone | `1208, 1213, 1212, 1209, 1097, 1214, 1216, 1218, 1217, 1098` |
| 21 | A11 Броня Героя Колонизации (def 15) | W12 Элитный пулемет | Seventh Zone | `1140, 1210, 1211, 1215, 1099, 1138, 1139, 1220, 1219, 1100` |
| 22 | A11 Броня Героя Колонизации | W12 Элитный пулемет | SpecOp Alpha | `1101, 1102, 1103, 1104, 1105` |
| 23 | A11 Броня Героя Колонизации | W12 Элитный пулемет | SpecOp Beta | `1107, 1108, 1109, 1110, 1111` |
| 24 | A11 Броня Героя Колонизации | W12 Элитный пулемет | Elite Mission | `1112, 1113, 1114, 1115, 1116` |

Weakest pair on the first map, hardest pair (`Броня Героя Колонизации` + `Элитный пулемет`) from
map 1140 on. **Span 16 is the one to look at twice** — the jump W8 → W12 happens because Fifth Zone
map 1195 demands 266 sustained dps and nothing on the ladder except the elite shotgun (261) comes
close. If §10.4's finding is honoured, W8 is the better weapon for spans 16–24 and W12 is only the
*shop-canonical* top. Pick one and be consistent: **W8 for a power-true picker, W12 for a
shop-true one.**

### 12.4 Десант (DP7) — its own track, 23 maps

Ratcheted separately, because it is not on the campaign path (§4).

| # | Armor | Weapon | maps |
|---|---|---|---|
| 1 | A0 Броня Стартовая | W2 Элитный Пистолет | `1029` |
| 2 | A0 Броня Стартовая | W5 Автомат | `1030, 1031` |
| 3 | A0 Броня Стартовая | W6 Элитный Автомат | `1032, 1033, 1034, 1035, 1036, 1037` |
| 4 | A0 Броня Стартовая | W8 Элитный Дробовик | `1038, 1039, 1040, 1041, 1042, 1043, 1044, 1045, 1046, 1047, 1048, 1049, 1050, 1053` |

**Armor never advances and the weapon runs to the top of the ladder.** Десант's monsters are the
starter roster (types 1–5, mean damage 2.7–3.6 — the starter suit is enough all the way through),
but its *volume* is campaign-endgame: map 1053 throws 1420 monsters in 110 s, demanding more
sustained dps than Elite Mission does. It pays starter-tier rewards for endgame-tier throughput.

This is decisive for §4's reading: **Десант is a farm / gauntlet track meant to be re-entered with
late-campaign weapons**, not a chapter you progress through. A storyline should treat it as an
optional operation, not a stage on the route.

---

## 13. Reproducing §10–§12

```
# item table (61 rows) — split on the INSERT prefix, brace-aware field split, UTF-16
old_shooter/src/trunk/Database/20150626 - TestRC/Data.sql
  → ItemTypes:  ItemClass 1 = Exoskeleton, 2 = Weapon, 4 = Bottle, 5 = Booster, 6 = MoneyItem
  → Monsters:   <Monster><Health><Damage><Speed><ExperienceReward><MoneyReward>…
  → Levels:     cumulative XP thresholds
# map payloads
monstro_client/Resources/MapConfigs/map_*.json  → monsterSpawnWaves[], monsterTypes[], landingDuration
```

Watch for three parsing traps:

1. The file is **UTF-16**; `grep` needs `-a` and Python needs an explicit decode.
2. `Data` XML contains parentheses and escaped quotes — a naive `split(',')` on the `VALUES (…)`
   tuple corrupts every row after the first XML column. Split at depth 0 with a quote-state machine.
3. Splitting rows on `VALUES \((.*?)\)` loses 3 of 61 rows (multi-line XML). Split on the
   `INSERT [dbo].[ItemTypes] ([Id]` prefix instead.

`maximumVictims` is 5000 for every type on every map — not a binding cap, ignore it. `energyCost` is
10000 on 250 of 251 maps, which looks like a failed extraction rather than a design; do not read
economy from it.

**Open items specific to this section**

1. Prices are TestRC. Query 4 in §7 replaces them with production values.
2. Rank progression is unknown — `Players.Rank`, `FighterRating`, `EliteRating` exist, but the rules
   that advance rank live in the C# server (`old_shooter/src/trunk/SourceFiles/Server/`). Until
   those are read, the elite line's *availability* over the campaign is an assumption; its
   *ordering* is not.
3. `GameRounds.InitialInventoryState` is an XML loadout snapshot **per round played**. That is the
   ground truth for this entire section: it says what players actually equipped on each map, rather
   than what the price ladder implies they should have. If the DB gets attached, diff it against
   §12.3 — that single query validates or replaces the whole table.
