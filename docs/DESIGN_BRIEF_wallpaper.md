# DESIGN BRIEF — on-device AI wallpaper generator (name TBD)

You are designing a small, complete app. Two screens. Read all of this before proposing anything.

---

## 1. What it is

**An on-device AI wallpaper generator.** The user types a prompt (or taps *Surprise me*), the image
is generated **entirely on their phone**, and it is saved to the app's **iCloud folder**.

**No account. No sign-in. No credits. No subscription. No ads. No network — ever.**

The whole app is: **Create** and **Gallery**. Nothing else.

---

## 2. Inspiration — `aisixteen.studio.old`, and what to leave behind

There is a predecessor in this repo at `../aisixteen.studio.old/`. **Look at it for feel, then
discard most of its architecture.**

**Take:** the create-flow rhythm (`Components/CreateItemPopup.swift`, 408 lines), the image
presentation (`FantasticImage.swift`), the general calm of the layout.

**Leave behind — all of it:** Firebase, Google Sign-In, SocketIO, `Login`, `AccountModal`,
`BuyPacksPopup`, `CreditPack`, `Price`, `User`, `Api`, `Chat`, `Collection`. That app was a
cloud SaaS with credit packs. **This one is a local tool.** Every screen that existed to manage an
account or sell credits simply does not exist here.

⚠️ **And do not inherit its visual system.** It is built on `.ultraThinMaterial` throughout —
`AppView`, `TopBar`, `FantasticModal`. That is the **previous** material generation. See §3.

---

## 3. ⚠️ Liquid Glass — the 2026 design system, and it is not optional

**Every control in this app is Liquid Glass.** Not `.ultraThinMaterial`, not `.regularMaterial`,
not `.thinMaterial`, not a blurred rectangle with a hand-rolled border. Those are the old system and
they are visibly dated next to the current one.

**Use the current API surface:**

- `.glassEffect()` — the base modifier, with `.regular` / tinted / `.interactive()` variants
- **`GlassEffectContainer`** — wrap groups of glass elements so they blend and morph as one system
  rather than as separate panes. This is the part people miss, and it is what makes it look native
  rather than pasted on.
- `glassEffectID` + a namespace — for elements that **morph between states**. The Create button
  becoming the progress indicator is exactly this.
- `.buttonStyle(.glass)` for buttons
- Let the system own the shapes — capsules and concentric corner radii, not arbitrary ones

**Design principle that matters more than the API:** glass is a *layer above content*, not a
decoration on it. The generated wallpaper is the content. Every control floats over it. **The image
is never covered by an opaque panel.**

Specify light and dark behaviour, and remember glass takes its character from what is behind it — a
dark generated wallpaper and a pale one must both leave controls legible.

---

## 4. Screen one — Create

**Two inputs, one action.**

- **A text field** for the prompt. Generous, calm, the primary object on screen.
- **A *Surprise me* button** that fills it with something good. This is not a gimmick — it is how
  people who don't know what to type get their first result. Design it as a first-class control, not
  an afterthought. Decide whether it fills the field visibly (so the user learns what a good prompt
  looks like) or generates directly. **Recommend one and say why.**
- **A Create button.**

### The waiting state is the real design problem

On-device diffusion takes **roughly 10–30 seconds**. That is a long time to look at a spinner, and
it is the single biggest risk to how this app feels.

**Two things must be true:**

**The progress must be real.** Diffusion runs a known number of steps, so actual progress is
available. **Never fake it.** A bar that lies is worse than no bar.

**Show the image forming.** Diffusion can decode intermediate latents cheaply — the picture emerges
from noise. Watching that happen turns a 20-second wait into the most interesting moment in the app.
Design for that, not for a percentage.

Design the **morph**: Create button → progress → finished image. `glassEffectID` exists for exactly
this transition, and it should feel like one object changing state, not three screens.

Also design: **cancel** mid-generation, and what a **failure** looks like.

---

## 5. Screen two — Gallery

Everything generated, saved to the app's **iCloud folder** so it syncs across the user's devices and
is visible in the Files app.

Design: the grid, a single-image view, and the actions — **set as wallpaper**, share, delete, and
*regenerate from this prompt* (the prompt is stored with the image; make it visible and reusable).

Design the **empty state** properly. It is the second thing every new user sees, and it should
teach — a *Surprise me* invitation belongs here.

---

## 6. What you may decide, and what you may not

**Yours:** the visual language within Liquid Glass, layout and typography, how the prompt field
behaves, the *Surprise me* interaction, the generation-progress presentation, the gallery grid,
navigation between the two screens, empty and error states, light/dark treatment.

**Not yours:**

- **The material system.** Liquid Glass, current APIs, everywhere. No `.ultraThinMaterial`.
- **The monetization.** No ads, no subscription, no credits, no consumables. If a paid unlock exists
  it is a **single non-consumable** — but do not design a paywall, a trial, or an upgrade prompt
  unless the owner says so.
- **Offline-only.** No account, no sign-in, no cloud generation. iCloud is used **only** as the
  user's own storage. If a screen implies a server, it is wrong.
- **Two screens.** Resist adding a third. Every feature this app doesn't have is a feature the
  incumbents were hated for.

**Accessibility floor:** Dynamic Type throughout; VoiceOver on every control and on generated
images; **legibility over glass in both themes** — this is where glass designs usually fail, so
prove it against a black wallpaper and a white one; nothing conveyed by colour alone; and **respect
Reduce Transparency and Reduce Motion**, which matter more than usual in a glass-heavy design.

---

## 7. Platforms — universal: iPhone, iPad, Mac

One app, Universal Purchase. Design all three; they are not the same screen scaled.

### ⚠️ The asymmetry that shapes the whole "set as wallpaper" action

**iOS and iPadOS give apps no way to set the wallpaper.** There is no public API. The best an app
can do is save to Photos and *tell the user* to go to Settings → Wallpaper and pick it. The job ends
outside the app.

**macOS can.** `NSWorkspace.setDesktopImageURL` sets the desktop directly. **On Mac the app finishes
the job; on iPhone it hands the user a file and an instruction.**

Design that honestly rather than pretending the platforms match:

- **Mac:** a real *Set as Desktop* action that works, immediately, on the current display — and
  consider multi-display and Spaces
- **iOS/iPadOS:** save to Photos, then a clear, short handoff telling the user exactly where to go.
  Do **not** dress this up as if the app did it. A wallpaper app that lies about setting the
  wallpaper is the first 1-star review.

### Per-platform character

| | |
|---|---|
| **iPhone** | the default case. One hand, portrait, phone-shaped output |
| **iPad** | more room for the gallery; landscape output matters here |
| **Mac** | **desktop-shaped output** — wide aspect ratios, high resolution. Also the fastest hardware, so generation is quicker and larger sizes are realistic. The window is a design object, not a stretched phone screen |

**Aspect ratio is a real input**, not a detail: phone portrait, iPad, and desktop widescreen are
different generations. Decide whether the user picks it or the platform implies it.

---

## 8. Deliver

1. **Create**, in every state: empty · prompt typed · generating (with the emerging image) ·
   complete · failed · cancelled
2. **Gallery**: empty · populated grid · single image with actions
3. The **morph** from Create button → progress → result, specified as a transition, not three stills
4. **The design system** — glass treatments, tints, type scale, spacing, the light/dark tokens
5. **Legibility proof** — controls over a near-black wallpaper and a near-white one
6. **Reduce Transparency / Reduce Motion** variants
7. The ***Surprise me*** decision (§4) with reasoning
8. Anything here the platform or the physics won't support — say so rather than designing around it
   silently

---

## 9. The one thing to keep in mind

Every competitor in this category is a **free ad farm or a subscription trap** — measured recent
ratings of **1.82★, 1.97★, 2.19★, 2.22★**, with complaints of *"ads every 3 seconds"* and
*"you have to pay to get anything"*.

This app's entire position is that it is **calm, private, offline, and asks for nothing**. The design
should feel like that — unhurried, uncluttered, no badges, no counters, no prompts to upgrade. The
absence of noise *is* the product.
