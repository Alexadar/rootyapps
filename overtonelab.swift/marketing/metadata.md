# Overtone Lab — App Store metadata (draft, NOT uploaded)
- **Display name:** Overtone Lab · **Subtitle:** Sound & acoustics tools · **Category:** Music · **Price:** $14.99 (or subscription/tier TBD)
- **Bundle id:** oleksandr.aisixteen.overtonelab
- **Keywords:** acoustics,tuning,just intonation,cents,room,reverb,rt60,crossover,lufs,loudspeaker,horn,pipe,filter
- **Description:** A calculation studio for musicians, instrument builders and audio engineers — ten precision tools in four sections:
  - **Tuning** — Partch (just intonation & cents), Comma (EDO & temperament), Mersenne (string tension & frets)
  - **Acoustics** — Sabine (room reverberation), Webster (horns & Helmholtz), Bernoulli (pipe resonance)
  - **Signal** — Butterworth (filters & crossovers), Fletcher (A/C/Z weighting), Benchmark (LUFS loudness)
  - **Design** — Thiele (loudspeaker enclosures)
  Every tool is offline, each formula validated against an external reference.

## Provenance
This app consolidates 10 previously separate music tools into one product (Guideline 4.3 — one substantial app rather than many thin ones). Each tool's math is its own validated `*Kit` SPM package copied in verbatim, with its oracle tests. CommaKit's Scala archive stays gitignored.

Release: builds on sim; offline (sandbox-only, grep-clean); all copied Kit oracle tests green (Comma ScalaOracle over 5,401 .scl files passes). Screenshots are a first functional cut — **visual design to be redone**. NOT uploaded, no ASC record.

## Name availability
"Overtone Lab" — reserve in App Store Connect before finalizing (bare "Overtone" may collide; "Overtone Lab" is the chosen brand).
