# Thiele — App Plan

## Positioning
Offline **loudspeaker / subwoofer design** (Thiele-Small). Target: audio DIYers, car-audio & hi-fi builders. One-time $12.99. Acceptability 🟢.

## Offline & privacy
No network/account. All on-device.

## ThieleKit (pure math, Foundation-only)
- `TS`: derive/estimate Thiele-Small params (Fs, Qts, Vas relationships).
- `Sealed`: box Qtc, F3, required Vb for a target Qtc.
- `Ported`: **vented box** alignment (Vb, tuning Fb, port length from diameter & count), port air velocity/compression check.
- `Response`: modeled low-frequency SPL (2nd/4th-order), group delay.
- `Room`: axial room modes, RT60 (Sabine).
- Types: `Driver`, `Enclosure`, `Port`.

## Screens (iOS tabs)
- **Driver** (T/S) · **Enclosure** (sealed/ported) · **Response** · **Crossover** · **Room**.

## Bundled data / licensing
Physics constants; example drivers. Formulas public (Thiele/Small papers, Dickason *Loudspeaker Design Cookbook*).

## Icon (ImagePlayground prompt)
"Speaker cone / driver seen head-on with a port hole, warm orange on deep navy, minimal geometric vector, no text."

## App Store metadata (draft)
- Name **Thiele** · Subtitle "Loudspeaker box design" · Category Music · Age 4+ · $12.99.
- Keywords: loudspeaker,subwoofer,thiele small,ported,sealed,enclosure,box,crossover,car audio,diy.
- ⚠️ Verify name; fallback "Thiele Box".

## Screenshots (captions)
Driver → "From T/S parameters." · Enclosure → "Sealed & ported alignments." · Response → "See the low-end response." · Room → "Modes & RT60."

## Validation & oracles (see ../VALIDATION.md)
- **Oracle-backed**: a **solved enclosure from the standard loudspeaker-design textbook** (Dickason) — driver T/S → published **Vb, Fb, F3, port length**; a vented-box alignment matched to the book's numbers (±3%).
- **Identity/invariant**: sealed Qtc increases as Vb decreases (monotonic); port length →∞ as area→0; response asymptotes to driver rolloff.
- **Edge/domain**: **port end-correction** (flanged vs unflanged), port air velocity (compression flag), very low Qts drivers, tiny/huge Vb.
- **Human checkpoints** (RELEASE_CHECKLIST): cross-check a design vs **WinISD / a textbook worked example**; verify port length includes the correct end correction.
