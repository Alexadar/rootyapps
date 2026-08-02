# kerfcalc — Standards Maintenance

The correctness moat depends on cited external standards. Some are permanent; some drift. This is
the playbook for keeping them current. The canonical machine-readable list lives in
`KerfCalc/Views/Standards.swift` (shown to users in the Reference tab); the test-backed values live
in each `*Kit`'s oracle suite; the ledger is `docs/VALIDATION.md`.

## Volatility tiers
| Tier | Meaning | Examples | Review cadence |
|---|---|---|---|
| **Fixed** | Math / physics / definitional — won't change | NIST in≡25.4 mm, ASTM A615 bar table, framing-square √(rise²+144), geometry | Never (spot-check on major toolchain change) |
| **Code cycle** | Building codes, revised ~every 3 yr; jurisdictions adopt different editions | IRC/IBC stairs, ACI 360R joints, ACI 318 lap, NCMA TEK | Each code cycle (~3 yr) + on adoption news |
| **Product** | Manufacturer sheets & estimating conventions; market-dependent | Quikrete yields/coverage, aggregate densities, waste %, paint coverage | Annually / when a sheet is revised; already user-editable in-app |

## When something changes — the update is mechanical
1. **Bump the value** in the owning `*Kit` source (e.g. `StairCode.irc2021`, `Concrete.bag80lbYieldFt3`).
2. **Bump the oracle test** in that Kit's `*OracleTests.swift` to the new cited number, and update the `// oracle:` citation to the new edition/date.
3. **Bump the edition string** in `Standards.swift` (the Reference tab updates automatically).
4. **Update `docs/VALIDATION.md`** row.
5. `swift test` — the suite **fails loud** if a transcribed value drifts from its test, so re-validation is verify-by-running, not by eyeballing.

Because codes are *inputs* (Stairs is IRC/IBC-selectable) and product figures are *editable defaults*,
a standards change is a data + test edit — never a logic rewrite.

## Review checklist (fold into RELEASE_CHECKLIST before any release)
- [ ] IRC/IBC edition still current for the target market? (check ICC code-adoption map)
- [ ] ACI 318 / 360R editions unchanged? (lap kept as "rule of thumb, not design" — insulated)
- [ ] ASTM A615 bar table unchanged? (nominal areas/weights — historically stable)
- [ ] Quikrete #1101 / #1136 data sheets — yields/coverage still as transcribed?
- [ ] Aggregate densities & waste factors reasonable for region? (user-editable; defaults cited)
- [ ] `swift test` green across all Kits after any bump
- [ ] Human cross-checks (framing square, stair calculator) still agree

## Not our job to track
Physics and definitions (NIST 1959 agreement, π, 27 ft³/yd³, Pythagoras). If these "change," revalidate the universe, not kerfcalc.
