# LEAD — sheet-music reader (not recogniser)

**Status: LEAD, not a decision.** Demand and field are measured; the wound analysis that would justify
building has **not** been run. Do not start from this document alone.
Measured 2026-07-29, US storefront, iTunes Search API + `MZSearchHints` (`X-Apple-Store-Front: 143441-1,29`).

---

## 1. The finding

**In the sheet-music audience, the money is in the reader, not the recogniser.**

This came out of asking whether OMR was worth a second attempt after NoteScan. It isn't — but the
measurement surfaced something better next door.

### Demand splits cleanly

```
sheet music reader   -> 6 hints      music scanner       -> 6 hints
score reader         -> 6 hints      sheet music scanner -> 3 hints
music notation       -> 6 hints
pdf to midi          -> — NONE —
sheet music to midi  -> — NONE —
```

Reading and displaying scores has strong, broad demand. **Converting sheet music to MIDI has zero App
Store search volume.** Nobody looks for that job.

### And the money agrees

| App | Price | Ratings | ★ | Updated | What it is |
|---|---|---|---|---|---|
| **forScore** | **$24.99** | **42,315** | **4.81** | 2026-04-23 | reader/organiser — **no ML** |
| MuseScore | Free | 76,831 | 4.6 | current | notation + community library |
| Musicnotes | Free | 42,530 | 4.8 | current | store-attached reader |
| Sheet Music Scanner | Free | 6,364 | 4.5 | current | **OMR** |
| **PlayScore 2** | Free | 4,525 | **4.2** | current | **OMR** — the incumbent, and the weakest rating in the top set |
| Piascore | Free | 1,672 | 4.6 | 11.6 mo | reader |
| Newzik | Free | 1,458 | 4.6 | 1.4 mo | reader |
| Halbestunde | Free | 1,390 | 4.3 | 0.7 mo | reader |

**forScore is the highest-price / highest-volume paid app found anywhere in the July 2026 search:
$24.99 × 42,315 ratings.** The OMR apps — the hard ML problem — are free and an order of magnitude
smaller, and their leader sits at 4.2★.

**Conclusion on OMR: drop it.** NoteScan's difficulty was not bad luck. It attacked the
expensive-to-build, cheap-to-sell half of a market whose valuable half needs no ML at all.

---

## 2. What forScore actually is

`forScore, LLC` · released **2010-04-09** · v15.1.2 · **27 MB** · Music · minOS 17.0 ·
iOS/iPadOS/macOS/visionOS.

**27 MB is the whole app. No model, no weights, no inference.** What $24.99 buys:

- PDF import from anywhere; iCloud sync across all devices
- Metadata, instant search, **setlists**, smart bookmarks for multi-part files
- Display craft: portrait, two-page landscape, and **Reflow** — systems laid end-to-end like a
  horizontal teleprompter for small screens
- **Annotation in layers**, shown or hidden at will
- **Links and buttons** so a repeat is one tap, not a scroll
- **Bluetooth page-turner pedal** — hands-free
- Metronome, tuner, pitch pipe, piano keyboard
- Page turns synced across nearby devices for an ensemble

Everything serves one moment: **a musician on a stand, hands on the instrument, who must not fumble a
page turn.** Sixteen years of refining that.

Note it also runs an optional annual "forScore Pro" subscription *on top of* the $24.99 — and still
holds 4.81★. Additive rather than hostage-taking; buyers do not punish it.

---

## 3. What building one would take

Almost none of it is exotic.

| Feature | Built with |
|---|---|
| PDF render, search, thumbnails | **PDFKit** |
| Annotation, layers | **PencilKit** |
| Library sync | **CloudKit** |
| Metronome, tuner, track playback | **AVFoundation** |
| Bluetooth page-turner pedal | standard **BLE HID** — pedals present as a keyboard, so key events |
| Setlists, metadata, bookmarks | plain data modelling |

**The one genuinely algorithmic feature is Reflow** — find staff systems on a page, re-lay them
end-to-end. Open, well-published work: projection profiles, run-length encoding, Hough transform for
staff lines.

**Why this matters for us:** staff-line detection is the *easy, solved* half of OMR. The half that
defeated NoteScan is symbol recognition — noteheads, accidentals, beams. Reflow needs none of it; it
only needs to know where systems are. That is segmentation, not recognition. **NoteScan's preprocessing
work is directly reusable here, pointed at a tractable problem instead of an intractable one.**

---

## 4. Why this is a lead and not a plan

**The wound analysis has not been run.** We do not know what forScore users complain about, or whether
there is an opening at all. That is the exact step that turned the tape-measure niche into Storypole,
and it is missing here.

**The incumbent is formidable.** Sixteen years, 42,315 ratings, 4.81★, actively maintained, and it
appears in Apple keynotes and retail stores by its own description. Every competitor has had access to
the same frameworks and none has passed 1,700 ratings. **The moat is not technical — it is craft.**
A head-on sibling is buildable and would probably be mediocre.

**Against that:** the audience demonstrably pays a high price upfront, the category is not
subscription-poisoned, Apple ships nothing here, and there is no free giant *among readers* — MuseScore
and Musicnotes are library/store plays, not stand tools.

---

## 5. Next step if picked up

1. **Wound analysis on forScore, Piascore, Newzik, Halbestunde** — Customer Reviews RSS, ≥3.4 s
   throttle. Look specifically for: iPad/Mac parity, sync failures, setlist limits, pedal support,
   annotation loss, import friction, and any subscription resentment around forScore Pro.
2. **Only if a real wound appears**, check whether it is addressable by craft rather than scale.
3. If it is, the build is a PDFKit/PencilKit/CloudKit app plus Reflow — no model, no licence gate, no
   training. Which also means **no moat from our ML capability**; the differentiator would have to be
   the same obsessive fit-to-the-moment that forScore has.

**Related:** `docs/instruments_ml_2026-07-29.md` (the on-device thesis), `docs/ondevice_models_2026-07-29.md`
(model survey — note this lead needs *none* of it), `docs/HANDOFF_storypole.md` (same shape: the
incumbent has no ML either, and its moat is drawing the answer on a picture of a tape).
