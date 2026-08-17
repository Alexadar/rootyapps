# DESIGN BRIEF — HVAC air-side calculator (working title TBD)

You are designing a new app. Read all of this before proposing anything. The measurement is done
and is not yours to re-open; the scope boundary in §2 is legal and safety-driven and is not
negotiable.

---

## 1. What the app is

**A psychrometric and air-side engineering calculator for HVAC technicians, designers and
contractors.** Every value is computed from published physics, on device, offline, with no
account and no network.

**One app, many tools** — not four apps. See §3.

**Paid-upfront, ~$29.99–39.99. No IAP, no subscription, no ads.**

**Platforms: iPhone, iPad, Mac, Apple Watch.**

---

## 2. ⚠️ The scope boundary — read before designing a single screen

This app is defined as much by what it excludes as what it includes. Two exclusion classes, both
absolute.

### Excluded — licensed data (legal)

| Excluded | Why |
|---|---|
| **ASHRAE Duct Fitting Database** — fitting loss coefficients | licensed ASHRAE product |
| **ACCA Manual D** — equivalent lengths of fittings | sold by ACCA |
| **ACCA Manual J** — load calculations | sold by ACCA; permit-path output additionally requires ACCA software approval |
| **SMACNA** duct construction standards | copyrighted and sold |

**Consequence you must design around:** this app **sizes straight duct from friction**. It is
**not a duct *design* tool** — total effective length and fitting equivalents are the licensed part.
Do not design a UI that implies a fitting library exists, and do not use the words "Manual D",
"ACCA", "ASHRAE approved" or "code compliant" anywhere.

### Excluded — life safety

**Flue sizing · vent sizing · combustion air · gas pipe sizing.** NFPA 54 / IFGC territory, where
the failure mode is carbon monoxide poisoning. This is not a disclaimer problem. Nothing in the UI
may hint these exist.

### What that leaves — and it is genuinely enough

Published physics, freely implementable, fully oracle-testable against published tables.

---

## 3. Function list — the tools

Each becomes an oracle-tested SPM Kit under `Kits/`, per the house pattern.

### 3.1 Psychrometrics — **the anchor of the whole app**

**Any two known, solve the rest**: dry bulb, wet bulb, dew point, relative humidity, humidity
ratio, enthalpy, specific volume, degree of saturation.

- Built on the **Hyland–Wexler** saturation-pressure correlations plus ideal-gas relations
- **Altitude / elevation correction** — most tools are lazy about this and it is wrong by a wide
  margin in Denver or Mexico City. Make it a first-class input, never a buried setting.
- **The chart itself.** A psychrometric chart is a dense 2-D nomogram, and rendering it legibly on
  a phone is the central design problem of this app. See §5.
- **Process lines**: sensible heating/cooling, humidification, dehumidification, mixing — drawn on
  the chart as vectors between states

### 3.2 Air-side heat

- Sensible `Qs = 1.08 × CFM × ΔT`
- Latent `Ql = 4840 × CFM × ΔW`
- Total `Qt = 4.5 × CFM × Δh`
- **Altitude-corrected forms of all three constants** — the 1.08 is sea-level only
- Solve in any direction: given load, find CFM; given CFM and load, find ΔT

### 3.3 Duct sizing from friction

- Colebrook / Darcy–Weisbach: CFM + friction rate → diameter
- **Velocity check against noise limits** — this is the check that separates a working system from
  a whistling one
- Round ↔ rectangular equivalent: `De = 1.30 × (a·b)^0.625 ÷ (a+b)^0.25`
- Material roughness selection (galvanized, flex, fibrous, spiral) — published physical constants
- Lockable dimensions for what-ifs: lock diameter, vary flow; lock height, solve width

### 3.4 Fan laws

Affinity relations — CFM ∝ RPM, SP ∝ RPM², BHP ∝ RPM³ — plus air-density correction.

### 3.5 Air mixing

Two airstreams (CFM + condition each) → mixed condition. **Pairs directly with the chart** — the
mixed state should appear on the chart between the two inputs.

### 3.6 Water pipe sizing

Darcy or Hazen–Williams, with velocity and erosion limits.

### 3.7 Units

IP ↔ SI throughout, per-field and globally. This trade works in both and switching must be free.

### 3.8 Deferred to a later version — do not design now

Refrigerant properties, superheat and subcooling. The only clean source is **CoolProp** (MIT
licensed); NIST REFPROP is not free. Porting is real work. Note it exists so the architecture
leaves room, but it is **not in 1.0**.

---

## 4. Why this app — the reasoning

Measured 2026-08-08/10 (Apple autocomplete with `X-Apple-Store-Front: 143441-1,29`, iTunes Search
API). You do not need to agree with it, but do not design against it.

**The price ceiling is unusually high for a utility.** The incumbent psychrometric app sells at
**$59.99**. Duct calculators sell at **$3.99 / $9.99 / $19.99–22.99**. This trade pays.

**The incumbents are fragmented and stale.** One developer (Pheinex) sells four separate
single-purpose apps — Duct Calculator $19.99, Psychrometric Chart $59.99, Pipe Sizer $12.99, Fan
Law $9.99 — **all last updated in 2024**. Buying the set costs over $100.

**One maintained suite at $29.99–39.99 replaces all four.** That is the entire commercial thesis,
and it is the Overtone Lab shape (26 tools, one binary, one price) applied to a trade that pays
more than musicians do.

**It also avoids Guideline 4.3.** Shipping four thin calculators from one account is the
spam-app pattern. One deep record is both safer and better ASO — ranking signal concentrates
instead of splitting.

**And it never decays.** Hyland–Wexler will still be correct in 2040. No server, no API drift, no
content treadmill.

**Honest constraint:** the audience is small — the $59.99 incumbent has 34 ratings in eleven years.
This is a **$5–10k/year** app. Design accordingly: it should feel precise and permanent, not
ambitious. Do not propose features that need ongoing content or a backend.

---

## 5. The central design problem: the chart on a small screen

A psychrometric chart plots dry-bulb temperature against humidity ratio, overlaid with curved
constant-RH lines, diagonal wet-bulb and enthalpy scales, and specific-volume lines. On paper it is
a wall poster. **Making it readable and touchable on a phone is the hard part of this design, and
it is the differentiator.**

Questions for you to answer, not for me to dictate:

- What is legible at 393 pt wide, and what has to be progressively disclosed?
- Is the chart the primary interface, or a *view* onto values entered numerically?
- How does a user place and drag a state point precisely with a thumb?
- How are two states and the process line between them shown without clutter?
- What does the chart become on Watch — if anything?

**Both directions must work:** type values and see the point move, or move the point and see values
update. Neither may be second-class.

---

## 6. Platform matrix — design all four

### iPhone — the field tool

The user is **in a crawlspace, on a roof, or in a plant room**. One hand. Possibly gloves. Possibly
bright sun or a headlamp. Hands may be dirty.

- Large touch targets, high contrast, legible at arm's length
- Single-hand reachability — primary inputs in the lower half
- Recently-used tools must be one tap from launch
- Assume interruption: state must survive backgrounding mid-calculation

### iPad — the chart

The screen the psychrometric chart deserves. Use the width: chart and inputs side by side, process
lines visible, multiple state points comparable at once. This is where a designer would actually
sit and think about a system.

### Mac — desk work and reporting

The user is writing up a job. Keyboard entry, tab between fields, and — importantly —
**getting results out**: copy a value, copy a table, export a state set. Consider drag-out. Mac
should feel like a tool on a desk, not a phone app in a window.

### Apple Watch — decide the scope and argue it

**This is a real call, not a checkbox.** A technician holding gauges in both hands has no free hand
for a phone, and a wrist glance is genuinely valuable — that is the case *for*.

Against: the chart cannot render meaningfully at that size, and text entry is painful.

**Propose what the watch does and justify it.** A plausible shape is a single quick conversion —
dry bulb + RH in via the crown, dew point and wet bulb out — plus a readout of the last state
computed on the phone. **An argued "no watch app" is an acceptable answer.** What is not acceptable
is a shrunken phone app.

If you include it, the Digital Crown is the primary input and must be the fastest path to a value.

---

## 7. What you may decide, and what you may not

**Yours:** the visual language and design system, the chart rendering and interaction, navigation
and tool organisation, how altitude is surfaced, unit switching, the Watch scope call, and how
results are copied and exported.

**Not yours:**

- **The scope boundary (§2).** Do not add fittings, load calc, or anything combustion-related, and
  do not imply they exist.
- **The pricing model.** Paid-upfront, no IAP, no subscription, no ads. Do not design a paywall, a
  trial, or an upgrade prompt.
- **Offline-only.** No account, no cloud, no network. If a screen implies a server, it is wrong.
- **Compliance language.** Never "Manual D", "ACCA", "ASHRAE approved", "code compliant".
- **The Kit pattern.** Every computation lives in an oracle-tested SPM package; correctness is
  proven against published tables. This constrains what can be claimed on screen: **if a number is
  displayed, it must be one a Kit can prove.**

**Accessibility floor:** Dynamic Type throughout, VoiceOver on every computed value *and* on the
chart (a chart that is invisible to VoiceOver is a failed screen — state points need labels and
rotor navigation), and **nothing conveyed by colour alone** — process direction, warnings and
out-of-range values all need shape or text.

---

## 8. Deliver

1. **The chart design** at all four sizes, with the interaction model in both directions (§5)
2. **Screen inventory** — every tool, every state: empty, mid-entry, computed, out-of-range/invalid
3. **Navigation** — how a user moves between tools, and how recent/favourite tools surface
4. **The design system** — tokens, type scale (numbers are the hero and must be tabular), spacing
5. **iPhone / iPad / Mac layouts**, each designed for its actual use context per §6 — not one layout
   scaled three ways
6. **The Watch call**, argued either way
7. **Altitude** — where it lives so it is never silently wrong
8. **Unit switching** — the interaction, and what happens to entered values
9. Anything in this brief the physics or the platform will not support — say so rather than
   designing around it silently

---

## 9. Naming

Not decided. Constraints when it is:

- The **App Store name must carry a head noun** users search — e.g. `<Brand>: HVAC Calculator`.
  A one-word wordmark alone is the Kerf Calc mistake.
- Measured search terms in this space: `duct calculator`, `hvac calculator`, `psychrometric`
- Avoid any name implying certification, compliance, or an association with ACCA/ASHRAE/SMACNA
