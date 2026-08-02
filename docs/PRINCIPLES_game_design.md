# Principles — mystery as a distribution engine, and the loop that drives it

> Crystallised from design literature, developer statements and store measurement. General by design:
> no titles, because the mechanisms are portable and the examples date.

---

## 1. Why mystery, specifically

Games are found by charts, editorial featuring and word of mouth — **not by search.** Nobody types a
genre hoping to find yours. That leaves very few channels reachable without a budget, and only one of
them scales.

**Mystery is a distribution mechanism, not a narrative flavour.** It is the only design property
identified that turns the audience itself into the channel:

- Featuring gives one impression
- Search gives a trickle, and only when the mechanic has a name people already type
- Spectacle sells installs **only if you are buying ads**
- **Mystery makes players talk to each other, and that conversation is the marketing**

## 2. The mechanism

Mystery is **intentional withholding of information.** Four levers:

| Lever | What is withheld |
|---|---|
| **The locked door** | what's behind it — but limit concurrent mysteries or the player is overloaded |
| **The rules** | how systems work; stay silent instead of tutorialising |
| **The landscape** | what's over the horizon; avoid maps and chatty companions |
| **The enigma** | the central question |

The strongest variant is **knowledge-gating**: progression locked behind what the player *knows*, not
what they own. Upgrades are entries in a notebook.

### Why it produces sharing

Three properties an ordinary reward loop lacks:

1. **The reward is transferable but not consumable.** Telling you my discovery costs me nothing and
   makes me feel expert. Giving you my sword costs me a sword.
2. **Partial knowledge compels posting.** Someone holding two-thirds of a secret posts it, because
   posting is how the last third arrives.
3. **Being wrong is social.** Theories are more fun to argue about than facts. Ambiguity generates
   threads; a clean answer generates one wiki entry.

**A puzzle no individual can solve alone forces players to pool information — and that pooling is the
distribution.** It is a design decision, not a marketing activity.

---

## 3. The reward is understanding

In a normal game the reward is **acquisition**. Here it is **comprehension**, which changes everything:

- **It cannot be given.** You can hand someone a sword; you cannot hand them the moment it clicks.
- **It cannot be taken away**, so it resists power-creep and devaluation.
- **It is free to produce.** You are not balancing an economy, you are pacing information.

---

## 4. The loop

```
GAP ──► PURSUIT ──► INFORMATIVE FRICTION ──► REVELATION ──┐
 ▲                                                        │
 └────────────  which must open a NEW gap  ───────────────┘
```

1. **The gap.** Something is withheld *and the player notices it is withheld*. An unnoticed gap
   produces nothing — they must feel the shape of the hole.
2. **Pursuit.** They form a theory and act. They must be able to act **wrongly**; if only one action is
   possible there is no theory, only instruction.
3. **Informative friction.** The attempt fails, and the failure teaches. This is the difference between
   a mystery and an obstacle: a door labelled "needs red key" is an obstacle; a door that does something
   unexpected is a mystery.
4. **Revelation that opens a new gap.** It resolves the question *and reframes something already seen*.

**The loop only sustains if step 4 feeds step 1.** Most attempts fail here — they build a *chain* of
puzzles rather than a *cycle*.

### Pacing

| Layer | Interval | Content |
|---|---|---|
| Core | 30–90 sec | a small "oh" — a mechanism responds |
| Meta | 10–15 min | a revelation that reframes prior material |
| Arc | per session | the invisible question — *there was a whole layer here* |

Missing the 30–90 second beat makes atmospheric games feel dead. Missing the 10–15 minute beat makes
players quit.

**The most valuable moment is the gap between "I know something is coming" and "I don't know what."**
The anticipation, not the payoff.

### The confirmation gate

**Never confirm one thing at a time. Batch confirmation into thresholds.**

Allow guessing freely and without penalty, but only confirm when several deductions are simultaneously
correct. This makes brute force useless, converts partial knowledge into a real threshold, removes fail
states entirely, and makes each payoff substantial rather than a drip of noise.

It is the mechanical opposite of a hint button.

### The layered structure

| Layer | Audience | Function |
|---|---|---|
| 1 | everyone | a complete, satisfying game you can finish |
| 2 | enthusiasts | harder secrets, findable alone with effort |
| 3 | the community | genuinely requires pooling |

**Layer 1 stops ordinary players bouncing. Layer 3 is the marketing department.** Difficulty here is
the point — a hard problem is an opportunity for players to bond over a shared experience. Most games
ship only layer 1 and then wonder why nobody talks about them.

**Layer 3 cannot be added later.** It must be woven through from the start.

---

## 5. Failure modes

| Failure | Symptom | Cause |
|---|---|---|
| Too obtuse | players quit, or open a walkthrough on day one | the gap has no visible shape |
| Too clear | played once, never mentioned | revelation closes instead of reframing |
| Obstacle, not mystery | "go find the key" | failure isn't informative |
| Dead air | atmospheric but boring | missing the short beat |
| Noise, not revelation | payoffs feel cheap | confirming one thing at a time |
| Explained too early | the world stops being interesting | the enigma resolved before the layers did |

Being too obtuse fails **as badly** as being too clear, because players go straight to a guide — and a
guide converts revelation into instruction.

---

## 6. Structure: chapters

**Each chapter is one turn of the loop. But if chapters only resolve themselves you have built an
anthology** — pleasant, and it evaporates.

**Run two loops at once:**

| | Local (chapter) | Global (game) |
|---|---|---|
| Question | *how do I open this?* | *what happened here?* |
| Resolves | every 10–15 min | at the ending |
| Reward | mechanical satisfaction | understanding |

**Every chapter revelation must pay both** — answering locally while depositing a fragment of the
global picture. That is what makes chapters compound instead of evaporate.

**Escalation:** early chapters local-dominant (teach the loop, plant the question) → middle balanced →
late chapters where the puzzles are almost formalities because the player is racing the answer →
ending, pure global revelation.

**The ending must recontextualise earlier chapters, not merely conclude.** A finale that concludes
satisfies once. A finale that reframes sends people back to replay — and that replay is the
distribution.

**Chapter one does double duty:** a complete local loop the player *solves* (proving fairness, teaching
rhythm) **and** the first hint that something larger is wrong. Without the second, the reason to
continue is "more puzzles," which is far weaker than "I need to know what this place is."

### Sizing

**10–15 minutes per chapter.** Below ~8 there is no room for informative friction and it degrades into
a puzzle with a solution. Above ~20 it exceeds a mobile session, the player is interrupted and loses
the thread. Chapter boundaries double as save points.

**Perceived size is counted in chapters, not hours.** Two games of equal length, one with twice the
chapters, draw dramatically different "too short" complaints — players count endings.

---

## 7. What to disclose

**On the store page: show the chapter count.** It pre-empts the entire length complaint before purchase.

**In-game: show the floor, hide the ceiling.**

| Layer | Show the count? |
|---|---|
| 1 — the complete game | **Yes** — reduces anxiety, makes progress legible |
| 2 — secrets | **No** |
| 3 — the community layer | **Never** — its existence *is* the revelation |

A visible total kills the **invisible question** — the moment a player learns the world contains a
layer they never knew existed. If the interface says "7 of 10," that discovery is impossible.

**Best form: show the shape of their ignorance.** Mark where they are incomplete without revealing
what they are missing. That converts a progress display from an anxiety-reducer into a curiosity
generator.

---

## 8. Endings

**Structurally the loop recurses forever. Practically it must end — and "never" is the one ending that
destroys it retroactively.**

Mystery is a depleting resource. If revelations keep arriving with no floor, players stop concluding
"there's more" and start concluding **"there's nothing"** — and they retroactively decide the earlier
mysteries were also empty.

**What can be endless is interpretation of a finished work.** Ambiguity inside a *completed* thing
invites debate forever; ambiguity inside an unfinished one reads as the author not knowing. Same
surface, opposite effect, and players detect the difference quickly.

**The sustainable pattern is local closure with global openness** — each release resolves its own
question completely while the larger world stays open. That also happens to be the business shape that
lets a small studio sell a body of work to the same audience, each release marketing the previous ones.

**Never make continuation conditional in public.** "I'll continue if you like it" transfers your risk
to the buyer, who reads it as "this mystery may never be answered" — fatal in the one genre that runs
on trusting that something is genuinely being withheld. Ship something complete; continue because it
worked.

---

## 9. Two market realities to hold alongside the design

**Free-to-play charts are leaderboards of ad spend**, not of what people love. Positions there are
purchased and optimised for extraction. The premium chart is a different market with different values,
where craft sustains near-perfect ratings for a decade.

**In free-to-play, mechanics and feel win; in premium, art wins.** A cheaper-looking product routinely
outsells a prettier one in the first market, because the loop holds attention. In the second, the art
*is* what is being bought.

**And the thing that actually decides casual play is neither** — it is *feel*: snap timing, the weight
of a clear, haptics, transition curves. Cheap to describe, very expensive to get right, invisible in
screenshots, and produced by iteration count on one artifact rather than by shipping many.
