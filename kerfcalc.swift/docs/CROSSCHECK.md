# kerfcalc — independent cross-check (zero-worry evidence)

Every calc, one canonical input, cross-checked against an **independent published authority** (not by
running any competitor). Each row maps to an oracle test in the Kit suites (92 tests green). Cross-checks
are ToS-clean: cited documents/tables, or reproduced by a second implementation.

| # | Calc | Input | App output | Independent reference | Source | ✓ |
|---|---|---|---|---|---|---|
| 1 | Feet-inch tape | 6'2½" + 2'7¾" | 8'10¼" | 74.5"+31.75"=106.25"=8'10¼" | carpentry math / CalculatorSoup | ✓ |
| 1b | Tape ×/÷ chain | 8'4½"×3−2'6"÷2 | 11'3¾" | 100.5×3−30÷2 = 135.75" | geometry (immediate-exec) | ✓ |
| 1c | **Tape area** | 10' × 8' | **80 sq ft** | 120"×96"=11520 in²÷144 | CM-Pro dimension math | ✓ |
| 1d | **Tape volume** | 10'×8'×4" | **26.67 cu ft** | 11520×4÷1728 | CM-Pro dimension math | ✓ |
| 2 | Convert | 1 ft | 0.3048 m; 304.8 mm | in ≡ 25.4 mm, ft ≡ 0.3048 m | NIST SP 811 | ✓ |
| 3 | Rafter (line) | 6/12, 12 ft | 13.42"/ft, 161.00" | framing-square table 6→13.42 | NAVEDTRA 14044 / InspectAPedia | ✓ |
| 3b | **Rafter actual cut** | 6/12, 12', 1½" ridge, 12" tail | 173.58" | 161−0.84+13.42 | slope-factor identity | ✓ |
| 4 | Right angle / pitch | 3-4-5; 6/12 | 5, 36.87°; 26.57° | atan tables | roof-pitch tables (barntoolbox) | ✓ |
| 5 | Stairs | 108" rise | 14 R @7.71", 169" stringer | published worked example | FIRGELLI / IRC R311.7 | ✓ |
| 5b | **Stairs headroom** | 76" measured | CHECK (< 6'8") | IRC 80" minimum | IRC 2021 R311.7.2 | ✓ |
| 6 | Area / Volume | r=1; cyl r=1 h=1 | π; π ft³ | πr², πr²h | geometry identity | ✓ |
| 7 | Concrete | 1 yd³ | 45 × 80-lb bags | 27 ÷ 0.60 | QUIKRETE #1101 | ✓ |
| 7b | **Concrete +waste** | 27 ft³ +10% | 1.1 yd³, 50 bags | 29.7 ft³ | editable convention (flagged) | ✓ |
| 8 | Footing | 100'×16"×8" | 3.29 yd³ | 88.9 ft³ ÷ 27 | geometry + QUIKRETE | ✓ |
| 9 | Rebar | #4 | 0.20 in², 0.668 lb/ft | ASTM A615 bar table | ASTM A615 / CRSI | ✓ |
| 10 | Aggregate | 20'×10'×4" crushed stone | 3.33 t | 2.47 yd³ × 1.35 | supplier-typical density (flagged) | ✓ |
| 11 | Pavers | 4×8, 200 ft², +10% | 991 | 144/32=4.5/ft² | geometry + waste (flagged) | ✓ |
| 12 | Roofing | 6/12, 2000 ft² | ×1.118, 22.36 sq | √1.25 slope factor | roofing tables (roofpitch.net) | ✓ |
| 13 | Estimate (drywall) | 1000 ft² | 35 sheets (+10%) | ÷32 × 1.10 | 4×8 geometry; waste flagged | ✓ |
| 13b | **Estimate (paint)** | 1000 ft², 2 coats | 5.71 gal | ÷350 × 2 | paint-mfr TDS 350 ft²/gal | ✓ |
| 14 | Miter (crown) | 45° spring, 4 sides | 35.26° / 30.00° | published crown table | crown-molding tables | ✓ |
| 15 | Mortar | 100 block | 8 × 80-lb bags | ÷13 | QUIKRETE Mason Mix #1136 | ✓ |
| 16 | Grout / joints | 100 ft²; 4" slab | 2.07 yd³; 8–12 ft | NCMA / ACI 360R | NCMA TEK 3-2A · ACI 360R | ✓ |

## Honest limits (flagged in-app + tests, NOT oracle-verified)
- **Waste %** (concrete/drywall/brick/roofing) and **paint coverage 350 ft²/gal** — cited *conventions* / mfr-TDS ranges, editable, not fixed constants.
- **Aggregate densities** — supplier/moisture vary; typical values, editable.
- **Rebar lap** — 40×dₐ field rule, explicitly NOT an ACI 318 design value.
- **Rafter actual cut** — assumes run to ridge centre, plumb-cut tail; birdsmouth/HAP not deducted from the along-rafter length.
Green ≠ safe-to-build: verify against the locally adopted code (RELEASE_CHECKLIST is the human checkpoint).
