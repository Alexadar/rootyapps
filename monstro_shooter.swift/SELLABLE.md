# Monstro Shooter — what a sellable version costs

**Date:** 2026-08-03 · **Status of report:** draft for joint review · **Nothing shipped, nothing changed.**

---

## 0. TL;DR

The code is real (61 Swift files, 8.3k lines, cross-platform, animated sprites, tested math kits).
**The game is not.** There is no score, no XP, no level-up, no pickup, no upgrade choice, no
progression, no persistence between runs. You pick a map from a dropdown, shoot bugs with a fixed
weapon for 45 seconds, and get a GAME OVER card. That is a playable engine, not a product.

On the price question, the measured answer is blunt:

> **$9.99 paid-upfront on the iOS App Store is not reachable for this game.** In the top 40 results
> for `top down shooter` there are **zero** paid apps. In `roguelike shooter` there are two, and both
> are ports of famous PC titles — Binding of Isaac ($14.99, cult brand) and Brotato ($4.99). In
> `roguelike survival` there is exactly one: Halls of Torment Premium ($4.99). The genre's paid price
> point on iOS is **$4.99, and it is reserved for games that were already famous somewhere else.**

$9.99 is real — on Steam, and on Mac. It is not real for an unknown iOS listing at cold start.
§4 gives the $9.99 spec anyway, because you asked for it, and §5 gives the version I'd actually ship.

---

## 1. What exists today — measured, not remembered

| | |
|---|---|
| Live listing | **Yes.** App ID 6752858611, "Monstro Shooter", **Free**, v1.0, released 2026-01-07, untouched since |
| Ratings | **0** |
| Ranks for | `monstro shooter` → **#1**. `top down shooter`, `roguelike shooter`, `survival shooter`, `alien shooter` → **NOT FOUND** in top ~190 |
| Code | 61 Swift files / 8,296 lines · macOS + iOS + iPadOS + visionOS · SpriteKit |
| Content shipped | 252 map JSONs (SQL dump of the Flash original), 6 of 24 monster types, 3 weapons, 4 exoskeletons |
| Content built but **not wired in** | 8 boosters, 5 tools (mines/artillery), 3 consumables, 33 equipment JSONs total |
| Extra machinery | `MonstroSim/` (652 MB, Metal + Core ML parity work), `torchsim/` (10 MB, RL training) |

### What the loop actually is

`Menu → 4 dropdowns (drop point / map / weapon / exoskeleton) → survive N seconds → GAME OVER → Try Again`

Verified absent in code (`grep` across all 61 files): `score`, `xp`, `levelUp`, any pickup/loot type,
`StoreKit`, `GameKit`. `experienceReward` exists as a field on `GameLevel` and is never read.
`SettingsManager` persists five dropdown selections and audio toggles — that is the entire save game.

### Three defects that are live on the App Store right now

1. **The debug overlay ships.** `GameScene+Core.swift:80` calls `setupDebugLabel()` unconditionally.
   Every player sees `Monsters: 35 | R: OFF Offset: 0.00` burned across the bottom-left. It is
   visible in your own marketing screenshots (`marketing/raw/ios/IMG_6148.PNG`).
2. **The description sells things that do not exist.** It promises "Beat your high score" (there is
   no score) and ends with "More maps and features coming soon!" — the second is a standing App
   Review 2.3/4.2 flag, the first is the exact 2.3.1 accuracy problem `autoaso.md` §6.6 warns about.
3. **The iTunes lookup returns 0 iPhone and 0 iPad screenshot URLs.** Verify in App Store Connect —
   if the product page genuinely has no phone screenshots, conversion is structurally zero.

### What it looks like

From `marketing/raw/`: the player is a ~15px teal droplet at the centre of a 4000px sand plain. The
camera is so far out the actor is unreadable. There are no bullets visible, no muzzle flash, no hit
flash, no XP gems, no damage numbers. The HUD is four unlabelled numbers (`1:04`, `1`, `11/131`,
`64`). The menu behind the PLAY button is a stock spaceship-and-asteroids image that appears nowhere
in the game, which is both a conversion problem and a metadata-accuracy problem.

---

## 2. The market, measured (iTunes Search API, US, 2026-08-03)

**Autocomplete — what people actually type** (`MZSearchHints`, storefront header set per §6.45):

| Seed | Verdict |
|---|---|
| `roguelike` | **Demand.** Generic completions: `roguelike games`, `roguelike survival`, `roguelike shooter`, `roguelike deck builder`, `roguelike td`, `roguelike dungeon crawler`. Almost none are product names. |
| `survivor` | **Demand + heavy supply.** `survival shooter`, `survival games` are generic; `survivor!.io`, `vampire survivors` are titles. |
| `top down shooter` | **Demand, crowded.** Bare term completes, plus 7 product names using it as a suffix. |
| `bullet heaven` | **Thin.** 3 hints, 2 of them product names. Nobody types this. |
| `twin stick` | **Dead.** 2 junk hints. Do not spend a character on it. |

**Incumbents — who ranks and at what price:**

| Term | Results | Paid | The paid ones |
|---|---|---|---|
| `top down shooter` | 40 | **0** | — |
| `roguelike shooter` | 39 | 2 | Binding of Isaac $14.99 (4.5★, 4.2k) · Brotato:Premium $4.99 (4.7★, 3.6k) |
| `roguelike survival` | 39 | 1 | Halls of Torment: Premium $4.99 (4.8★, 1.4k) |

And the free competition is not weak — this is the `autoaso.md` intake warning firing:
Survivor!.io (4.7★, **244,100** ratings), Monster Survivors (4.7★, 88k), Heroes vs Hordes (4.8★, 33k),
Vampire Survivors (free on mobile by design), 20 Minutes Till Dawn, Deep Rock Galactic: Survivor.
Poncle priced Vampire Survivors at $5 on Steam and **free on mobile**, saying plainly that the mobile
market does not support a couple of dollars.

**Cross-check against the portfolio's own rule** (`autoaso.md` §6.47): *"utilities are found by SEARCH,
games are found by FEATURING and word of mouth… four games shipped in this portfolio sit at zero
ratings."* Monstro Shooter is one of those four. ASO cannot rescue it; craft and featuring can.

---

## 3. Why the price question has a different answer than the quality question

Two independent gaps, and it is worth not confusing them:

- **Quality gap:** the game lacks the genre's core loop entirely. Fixable with work. §4/§5 spec it.
- **Price gap:** even a *good* version of this game does not sell at $9.99 on a cold iOS listing,
  because zero unknown games in the category do. Isaac charges $14.99 on the strength of a decade of
  brand. Brotato and Halls of Torment charge $4.99 on the strength of being PC hits first.

So the honest framing for our review: **build the game to the §5 bar, then choose where $9.99 lives.**
The three candidate homes for a $9.99 price, ranked by realism:

1. **Steam / macOS desktop.** $9.99 is the median indie price there and buyers expect to pay.
   Cost: the game is SpriteKit, so Steam means macOS-only (small audience) unless ported. You have
   `MonstroSim/` (Metal) already — that is the only reason this is even on the list.
2. **Mac App Store premium.** Keyboard+mouse is this genre's native input and the game already has
   it. Premium pricing is normal on Mac. But Mac game volume is very small.
3. **iOS paid-upfront at $9.99.** Not recommended at any content level, on the evidence above.

---

## 4. If the answer must be $9.99 — the full spec

This is what the game has to contain before the price is defensible anywhere. It is the same content
bar Brotato and Halls of Torment cleared at *half* this price, so treat it as the floor, not the goal.

### 4a. The core loop it does not have (this is the whole project)

The genre's hook is not shooting. It is **the level-up draft.** Kill → gem drops → magnet pulls it in
→ bar fills → game pauses → **pick 1 of 3 upgrades** → build compounds → screen fills with your own
absurd damage. Monstro Shooter currently implements the shooting and none of the rest.

Minimum for this to work:
- XP gems with a pickup radius, and a radius that is itself upgradeable
- Level-up pause + 3-card draft, weighted, with re-roll
- **25–30 upgrade cards** that interact (not 25 flat +10% damage cards — the "aha" is in synergies)
- **4–6 weapons that evolve** at max rank into a visibly different weapon
- Escalating 15–20 minute run with a hard end (boss or timer), not a 45-second wave list

### 4b. Meta-progression between runs

- Persistent soft currency dropped by enemies, survives death
- A permanent upgrade tree (~20 nodes) purchased with it
- **3–4 playable characters** with genuinely different starting weapons/stats, unlocked by play
- Unlock ladder for stages and weapons — every death must move something forward

### 4c. Feel — the cheapest, highest-leverage work in the list

Currently there is essentially no feedback. Needed: hit flash, knockback, damage numbers, kill
particles, screen shake on big hits, muzzle flash, bullet tracers, level-up fanfare, layered SFX,
controller support (Mac/iPad), and **a camera 2–3× tighter** so the player is readable.

### 4d. Content curation — subtract, don't add

- **252 maps → 4–6 hand-tuned stages** with distinct enemy rosters and hazards. 252 SQL-dumped wave
  lists is not content; it is a database. Nobody plays map #1183.
- **6 → 10–12 enemy types** plus **3–5 bosses.** Bosses are currently zero and are the thing
  screenshots and previews are made of.
- Wire in the 33 equipment JSONs that already exist (boosters/tools/consumables) or delete them.
- Kill the 4-dropdown menu. Replace with: character → stage → GO.
- Remove the Russian drop-point names (`Тренировочная база`, …) or localise them properly.

### 4e. Platform and store work

- Game Center leaderboards + achievements (free, and the "high score" the description already
  promises)
- `SKStoreReviewController` at end of a *successful* run — 0 ratings is the single biggest
  conversion drag on the page
- At least one IAP with a real display name — per `autoaso.md` §6.5, an app shipping no StoreKit
  forfeits an indexed search surface entirely
- Real screenshots + an **unframed** app preview from actual gameplay (`app-preview-no-framing`)
- **Featuring nomination** in App Store Connect — free, judged on story and craft not metrics, 0
  ratings does not disqualify. This is the only lever that has ever moved a game in this portfolio.

**Honest effort estimate: 2–4 months of focused solo work.** 4a alone is ~3 weeks. Not a weekend of
polish on an existing build.

---

## 5. What I'd actually ship — the recommendation

Build every line of §4. Then price it like this:

**Free download + one-time "Full Game" unlock at $4.99–$6.99, universal across iOS and macOS.**

Rationale:
- It matches your own compass, which since 2026-07-29 permits *games* to use free + one-time unlock
  IAP while utilities stay paid-upfront.
- It matches the genre's only two successful paid iOS entries ($4.99, both).
- It defeats the cold-start problem that killed the paid listings: a free download is the only way
  this ever accumulates the ratings that Apple confirms feed ranking.
- It creates the IAP display-name surface the app currently forfeits.
- It keeps the actual grievance as the pitch — **no ads, no energy, no timers, no live-ops, plays
  offline, buy once.** Every free incumbent in §2 monetises exactly the way players complain about.
  That is the portfolio's standard wedge and it is genuinely true here.

Then, if the game is good, **$9.99 on Mac and/or Steam later**, where that price is native. Ship
mobile first, use it to prove the loop, and let desktop carry the higher price.

Free-tier boundary that respects 3.1.1 and doesn't feel like a demo: stage 1 + one character free,
unlimited; unlock buys all stages, all characters, and the meta-progression tree.

---

## 6. Store fixes worth doing regardless of the above

These are cheap and independent of the game work.

| # | Action | Impact |
|---|---|---|
| 1 | Gate `setupDebugLabel()` behind `LaunchMode.debug` | Live build shows debug text to every player |
| 2 | Rewrite the description to match the shipping build; delete "high score" and "coming soon" | 2.3.1 exposure |
| 3 | Verify screenshots exist on the product page (lookup returns 0) | Conversion is zero without them |
| 4 | Put the head nouns in indexed fields — the app ranks for **nothing** but its own name | Same disease as Kerf Calc: the genre words are absent |
| 5 | Draft Title/Subtitle/Keywords around `roguelike`, `survival`, `shooter`, `offline`, `no ads` — the terms autocomplete proved are demand, not supply | Discovery |
| 6 | Do **not** spend characters on `twin stick` or `bullet heaven` | Measured dead |

Do #1–#3 before any metadata work; shipping better keywords into a page with a debug overlay and an
inaccurate description just buys traffic for a bad page.

---

## 7. What to decide together

1. **Is this the game you want to spend 2–4 months on?** The engine is genuinely good and the ML
   work (`MonstroSim`, `torchsim`, 652 MB of parity engineering) is impressive — but none of it is
   visible to a buyer, and none of it is on the critical path to a sellable game. Deciding to ship
   this means deciding to stop that.
2. **Price shape:** free+unlock (my recommendation) vs paid-upfront at $4.99 vs holding out for
   $9.99 on desktop.
3. **Fidelity of the port:** the Flash original's rules are documented to the formula in
   `old-shooter-gameplay.md` and `RULES.md`, and faithfulness has been the project's north star. But
   the original had no level-up draft — that mechanic is what makes the genre sell in 2026.
   **Parity with the Flash game and commercial viability now point in different directions.** That is
   the real fork in this project and it should be an explicit decision, not a drift.
4. **Scope of §4:** which items are v1 and which are v1.1. My cut for v1: 4a + 4c + a reduced 4b
   (currency + tree, one extra character) + 4 stages. Bosses and characters 3–4 can wait.

---

## Sources

- [Best iOS games without in-app purchases (Slant, 2026)](https://www.slant.co/topics/3480/~best-ios-games-without-in-app-purchases)
- [Vampire Survivors' free mobile release (Engadget)](https://www.engadget.com/vampire-survivors-ios-android-mobile-free-005055880.html)
- [Vampire Survivors developer on mobile monetisation (PocketGamer.biz)](https://www.pocketgamer.biz/vampire-survivors-developer-takes-new-approach-to-monetisation/)
- [Why $7.99 became the sweet spot for indie games (TechSpot)](https://www.techspot.com/news/110930-why-799-has-become-sweet-spot-indie-games.html)
- [Indie game monetization in 2026 (StraySpark)](https://www.strayspark.studio/blog/indie-game-monetization-2026-pricing-strategy)
- [Mobile's broken app store discoverability (PocketGamer.biz)](https://www.pocketgamer.biz/mobiles-broken-app-store-discoverability/)
- [Star Survivor: Premium, $2.99 (App Store)](https://apps.apple.com/us/app/star-survivor-premium/id6464449923)
- [Bullet heaven genre overview (Rogueliker)](https://rogueliker.com/bullet-heaven-games-like-vampire-survivors/)
- [Roguelikes with the best progression systems, 2026 (BulletHaven)](https://bulletheaven.com/blog/BlogPost12_RoguelikesWiththeBestProgressionSystems2026)
- [Developing for Apple Arcade: what indie devs need to know](https://medium.com/@atnoforgamedev/developing-for-apple-arcade-what-indie-devs-need-to-know-4aca6d5b2294)
- [Indie Mac developers on shipping in 2026 (TheSweetBits)](https://thesweetbits.com/we-asked-indie-mac-developers-about-ship-outside-the-app-store/)
- Primary data: iTunes Search API + `MZSearchHints` autocomplete, US storefront, queried 2026-08-03.
  App Store Connect app record 6752858611.
