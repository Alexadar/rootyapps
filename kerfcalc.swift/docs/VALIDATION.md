# kerfcalc — Validation & Oracle Ledger

Extends the family policy in `../../calculators/VALIDATION.md`. **Rule:** I write the implementation
and the harness; I never author the expected values. Every expected value cites an external source —
a building code, a published framing/roofing reference, a NIST factor, a manufacturer data sheet, or a
**second independent implementation**. Anything I generate myself is labelled `NOT oracle-backed`.

Test taxonomy: **Oracle-backed** (vs a published/independent number) · **Identity** (a definition,
cross-checked numerically) · **Invariant** (bounds / round-trips / cancellation).

---

## Calc #1 — Feet-inch-fraction arithmetic  ✅ 10/10 green
Kit: `Kits/Dimension/DimensionKit` · Tests: `Tests/DimensionKitTests/FeetInchOracleTests.swift`
Independent oracle: `Tests/DimensionKitTests/Oracles/feetinch_oracle.py` (CPython `fractions.Fraction`).

| Case | Formula / convention | Expected (source) | Test | Result |
|---|---|---|---|---|
| 6'2½" + 2'7¾" | exact rational inches | **425/4 in = 8'10¼"** — CPython Fraction oracle **and** published carpentry worked example (74.5+31.75=106.25) | `addSubExactInches`, `formattingWorkedExample` | ✅ |
| 6'2½" − 2'7¾" | exact rational | 171/4 in (Fraction oracle) | `addSubExactInches` | ✅ |
| 6'2½" × 3 | scale by number | 447/2 in (Fraction oracle) | `scaleByNumber` | ✅ |
| 6'2½" ÷ 2 | scale by number | 149/4 in (Fraction oracle) | `scaleByNumber` | ✅ |
| 12'6½" + 3⅜" / − 3⅜" | exact rational | 1231/8, 1177/8 in (Fraction oracle) | `mixedAndRatio` | ✅ |
| (12'6½") ÷ (3⅜") | dimension ÷ dimension → ratio | 1204/27 (Fraction oracle) | `mixedAndRatio` | ✅ |
| 1⅓" × 3 ; 1⅓"+1⅓"+1⅓" | exactness (no fp drift) | 4/1 in exactly (Fraction oracle) | `exactThirdsCancel` | ✅ |
| round(⅓", 1/16) / (1/32) | nearest 1/N, tie→away | 5/16 ; 11/32 (Fraction oracle) | `roundToNearestFraction` | ✅ |
| round(7/32", 1/16) tie ; round(−7/32") | tie away from zero | 1/4 ; −1/4 (Fraction oracle) | `roundToNearestFraction` | ✅ |
| 120" ÷ 7 then round 1/16 | non-clean division | 120/7 exact ; 137/8 rounded (Fraction oracle) | `divisionThenRound` | ✅ |
| Formatting 42.75/223.5/153.875/17.125" | ft-in-frac readout | 3'6¾" / 18'7½" / 12'9⅞" / 1'5⅛" (Fraction oracle inches) | `formattingReadouts` | ✅ |
| Parse `6' 2 1/2"`, `12'6-1/2"`, `-2' 6"` … | parser round-trip | 149/2, 301/2, −30 in (Fraction oracle) | `parsingRoundTrips` | ✅ |
| Rational reduce / sign / zero | Identity/Invariant | 2/4=1/2, −3/−6=1/2, 0/5=0 | `rationalInvariants` | ✅ |

**Convention note.** Rounding = nearest multiple of 1/N, ties **away from zero** (symmetric). N ∈ {2,4,8,16,32,64}, power-of-two carpentry denominators. Both implementations use this rule; tie cases are cross-checked against the independently-authored Fraction oracle.

---

## Calc #2–#10 — ✅ built & green (48 tests total across 4 Kits)
| # | Calc | Kit | Convention source (cited in tests) | Tests |
|---|---|---|---|---|
| 2 | Unit conversion | DimensionKit | NIST SP811 App. B (in≡25.4 mm, ft≡0.3048 m); intl-foot default, survey-foot flagged | ✅ 5 |
| 3 | Rafters | FramingKit | NAVEDTRA 14044 + framing-square table (3→12.37, 6→13.42, 7→13.89, 18→21.63; hip 6→18.00) | ✅ |
| 4 | Right-angle / pitch | FramingKit | right-triangle trig (identity) + published roof-pitch→angle table (4/12=18.43°…) | ✅ |
| 5 | Stairs | FramingKit | IRC 2021 R311.7 (7¾/10/6'8"/⅜) + IBC; published 108" worked example (14R@7.71, 169" stringer) | ✅ 13 (§3-5) |
| 6 | Area & volume | GeometryKit | geometry identities (π, Heron, cylinder), 27 ft³/yd³ | ✅ |
| 7 | Concrete | GeometryKit | Quikrete #1101 data sheet (0.60 ft³/80 lb → 45 bags/yd³) | ✅ 8 (§6-7) |
| 8 | Materials | MaterialsKit | roofing √(1+(rise/12)²)=1.118@6/12; NCMA 1.125 CMU/ft²; BIA 6.86 brick/ft²; waste% NOT-oracle | ✅ |
| 9 | Compound miter / crown | MaterialsKit | **borrowed** KerfKit — published crown tables (38°→31.62°/33.86°, 45°→35.26°/30°) | ✅ 4 (§8-9) |
| 10 | Circles / arches / columns / post-holes | GeometryKit | segment ½r²(θ−sinθ); cylinder → Quikrete bags | ✅ |
| — | **Keypad tape engine** | DimensionKit | `TapeCalc` state machine — published `6'2½"+2'7¾"=8'10¼"` proven end-to-end via keystrokes | ✅ 7 |

## Concrete/masonry depth — ConcreteKit ✅ 10 tests
Kit: `Kits/Concrete/ConcreteKit` · Tests: `ConcreteKitOracleTests.swift`, `SiteOracleTests.swift`
| Calc | Convention source (cited) | Test |
|---|---|---|
| Rebar | **ASTM A615 / CRSI** bar table — #4=0.20 in²/0.668 lb·ft, #8=0.79/2.670, #9=1.00/3.400, #11=1.56/5.313 | ✅ |
| Rebar mat/weight | table × geometry (11×11 bars @12" in 10×10 → 220 lf → 147 lb for #4) | ✅ |
| Rebar lap / hook | field rule 40×dₐ min 12" (CRSI/ACI §25.5, **reference-not-design**); hook 12×dₐ | ✅ |
| Footing / wall | geometry identity (100'×16"×8" strip = 88.89 ft³ = 3.292 yd³) | ✅ |
| Aggregate | geometry + **cited typical densities** (crushed stone 1.35 t/yd³, base 1.62); supplier-varying, editable | ✅ |
| Mortar | **QUIKRETE Mason Mix #1136** — 80-lb bag ≈ 13 block / 37 brick | ✅ |
| Grout | **NCMA TEK 3-2A** — fully-grouted 8" CMU ≈ 2.1 yd³ (56 ft³) per 100 ft² | ✅ |
| Ready-mix | NRMCA typical full truck ≈ 10 yd³; short-load < 1 yd³ | ✅ |
| Control joints | **ACI 360R** — max spacing 24–36× thickness(in) = 2–3× in feet (4"→8–12 ft) | ✅ |
| Pavers / retaining | geometry (4×8 = 4.5/ft²); pattern waste % editable convention | ✅ |

**Cross-checks still human-in-the-loop (RELEASE_CHECKLIST):** rafter table vs a physical framing square + one online calc; stairs vs an independent stair calculator; feet-inch vs `feetinch_oracle.py` (committed, re-runnable). Green ≠ safe-to-build; verify against the locally adopted code.
