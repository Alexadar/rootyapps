# DESIGN PROMPT — the seams between states

You designed this app already. The bundle in `design_handoff_aisixten_wallpapers/` is built and
running on a real iPhone with a real on-device Stable Diffusion model. **This brief is about what
the built version revealed: the states are right, the moves between them are not.**

Read the existing bundle first. Everything in it stands — colours, type, spacing, radii, the white
glass, the morph spec `1b`. This is not a redesign. It is the set of transitions the original brief
did not have to name because nothing was running yet.

---

## 1. What is actually built

Two screens — **Create** and **Gallery** — behind a floating glass segment control, plus a one-time
model-download gate. One glass object carries `glassEffectID("job")` through: Create capsule →
progress capsule → picture frame → *Save for Wallpaper*. All of that works.

Real numbers from the device, which matter because they change what the design is for:

| | |
|---|---|
| Model load, first generation of a session | **several seconds**, and the app can do nothing else useful during it |
| Generation | ~1.6 steps/sec on Mac; slower on iPhone. 20–28 steps ⇒ **15–30 s** |
| Latent preview | decoded every 2–3 steps, so the picture visibly resolves |
| Output | **512 × 512 square**, upscaled and cropped to the screen |

---

## 2. The six seams, in the order they hurt

### 2a. The model wakes up — a state with no honest progress ⚠️ the important one

Before step 1 there is a multi-second load of several hundred megabytes. There is **no fraction to
show**: Core ML reports nothing between "started loading" and "loaded". The app currently says
"Waking the model…" in the progress capsule with no fill, because the one rule that cannot bend is
that **no progress indicator in this app may be fake**.

The app now preloads speculatively as soon as Create appears, so in the common case this state
flashes past. But it is guaranteed to be visible on a cold launch when someone taps Create fast, and
it must be designed for that, not hidden.

**Design a waiting state that is honest about being unmeasurable.** Not a spinner, not an
indeterminate bar. Something that reads as *the machine is warming up*, is calm at 400 ms and still
calm at eight seconds, and — critically — **transitions into the step counter without a jump**,
because it is the same glass object that then becomes the progress capsule.

Also decide: if the load finishes in 200 ms, does this state appear at all, or is there a threshold
below which it is skipped? A state that flickers is worse than one that lasts.

### 2b. The finished picture was a dead end 🔴 shipped broken, patched, needs designing

The complete state is a full-bleed picture with *Save for Wallpaper*, share and regenerate. On
device it turned out there was **no way back to the prompt at all**. You could re-run the same
prompt forever; you could not write a different one. The worst possible place to trap someone —
immediately after a 25-second wait that succeeded.

A back circle was patched into the top-left as a stopgap. **Design the real exit.** Questions:

- Is going back a *dismissal* of the picture, or a *return* to a prompt that was never lost?
  (The prompt is in fact still there — the app never discards it.)
- The picture is already saved to the gallery. Does leaving need to say so, or is the existing
  "Saved to your iCloud folder" plate enough?
- Should the prompt field re-appear **over** the finished picture — editing in place, the picture
  still visible behind glass — rather than the picture disappearing? That would make "change one
  word and try again" the obvious move, which is how people actually use these.

### 2c. Create ⇄ Gallery, while something is happening

The segment control currently **hides entirely** during generation, on the reasoning that it is
chrome competing with the forming picture. That means the user is locked to Create for 25 seconds
with no way to look at anything else.

Decide properly: is a generation something you can walk away from? The job survives; only the view
is bound to it. If the answer is yes, design what the Gallery shows while a generation is running
elsewhere (a forming tile? a returning affordance?) and how coming back re-attaches. If the answer
is no, design a *stated* reason rather than a control that silently vanishes.

### 2d. Cancel, mid-flight

The spec says cancel plays the morph in reverse. It does. But cancel is available from three
visually different states — the bare progress capsule, the picture frame with a half-formed image,
and (now) the model-loading state — and reversing from a 300 × 540 frame holding a recognisable
picture is a much bigger visual event than reversing from a capsule.

**Design the reverse from each.** In particular: when a half-formed picture disappears, where does
it go, and does anything acknowledge that it existed? Right now a toast says "Stopped — your prompt
is kept" and the image is simply gone.

### 2e. Gate → first wallpaper

The gate's Ready state offers *Make your first wallpaper* and *Surprise me*. Both drop the user into
Create — one with an empty field, one with a prompt already written. This is the only moment the app
gets to teach, and it is currently a plain screen swap.

Design the handoff. If *Surprise me* was tapped, the prompt should arrive **visibly** — the user
needs to see a good prompt being written, because that is the entire pedagogical point of the
control.

### 2f. Failure, from a picture that had started to form

The failure card is specified (`1a`) and reachable, but the transition into it is only specified
from the capsule: *stops widening, drains tint, morphs into the card*. On device, failures happen
mid-run — most often out of memory, at which point **a partly-formed picture is already on screen**.

Design that path: frame with a half-picture → failure card. Does the picture stay behind the card?
Fade? The card is much smaller than the frame it replaces.

---

## 3. The constraint that shapes all of it

**Progress is never simulated.** Download bytes are real, diffusion steps are real, and where no
measurement exists — the model load — the interface must say something true rather than animate
something plausible. Every state you design has to survive the question *what number is this, and
where does it come from?*

Two accessibility requirements carry into every transition, per the existing bundle `1h`:

- **Reduce Motion** — geometry morphs become 0.2 s opacity crossfades at the same final positions.
  The emerging-image preview is kept: it is content changing, not the interface moving.
- **Reduce Transparency** — every glass fill becomes its opaque token, and **geometry does not
  move**. The setting changes material, never meaning or layout.

---

## 4. Known-wrong, do not design around it

The output is currently a **512 × 512 square**, upscaled and cropped to a 9:19.5 screen. So the
composition on a phone is mostly lost and the picture is soft. That is a model-conversion limit
(Core ML graphs are fixed-shape), not a design decision, and it is being fixed separately by either
converting a unet per aspect ratio or adding a super-resolution pass.

**Design for a correctly-shaped, sharp wallpaper.** Do not compensate for the current crop.

---

## 5. Deliver

1. **The waking state** (2a), and its transition into the step counter — as a sequence, not a still.
2. **The exit from a finished picture** (2b), including whether the prompt returns over the image.
3. **A ruling on leaving a generation** (2c), and whatever that implies for Gallery.
4. **Cancel, reversed from all three states** it is reachable from (2d).
5. **The gate handoff** (2e), with *Surprise me* writing its prompt visibly.
6. **Failure from a half-formed picture** (2f).
7. Reduce Motion and Reduce Transparency variants of anything above that moves.
8. Anything here you think is the wrong question — say so instead of answering it.
