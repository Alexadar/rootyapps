# CANDIDATE — CRM AI companion (per-CRM skins) — autoaso pass, 2026-08-16

Requested by the `fantastic_canvas` session. **Draft and stage only.** Method: iTunes Search API +
Apple autocomplete (`MZSearchHints`, storefront `143441-1,29`), US.

**Verdict: build ONE app, not a factory. The ASO case for per-CRM skins does not survive
measurement — but the portfolio-artifact case does, and it needs only one listing.**

---

## 1. There is no category demand. Only brand demand.

Autocomplete, US software storefront:

| Query | Hints |
|---|---|
| `ai for crm` | **none** |
| `lead scoring` | **none** |
| `crm for iphone` | 1, and it is an app title (`salesnow mobile crm for iphone`) |
| `pipedrive mobile` | **none** |
| `crm` (bare) | `crm video` · `crm iq` · `crmls` · **`crumbl`** · `cr-moj` — not a shopping query |
| `crm companion` | `mobile crm companion` · `ifs crm companion 9/10` — all existing enterprise titles |

Nobody searches for the concept. The generic terms are dead.

The brands, however, are alive:

| Query | Hints |
|---|---|
| `hubspot` | 10 — incl. generic `hubspot crm`, `hubspot sales`, `hubspot free`, **`hubspot ai`** |
| `pipedrive` | 6 — incl. `pipedrive crm`, and two third-party scanner titles |
| `attio` | 3 — `attio`, `attio crm`, `attio limited` |
| `go high level` | 3 · `gohighlevel` (one word) returns **1** |

**This is the crux.** The only capturable traffic is brand traffic, and reaching it requires
someone else's trademark in your app name.

---

## 2. Third-party branded apps survive — and cap out at 34 ratings

The important question is not whether Apple allows it. It is what it earns. Measured:

| App | Seller | Ratings | Price |
|---|---|---|---|
| Pipedrive CRM BizCard Scanner | Ruslan Savchyshyn | **34** | Free |
| Business Card Reader **4** Hubspot | Ruslan Savchyshyn | **1** | Free |
| Go High Level | WHATSGOODAPPS LLC | **1** | Free |
| Lead2Pipe Pipedrive Scanner | Tim Mehringer et al. | **0** | Free |
| HubSpot Marketing Prep | satoshi yoshida | **0** | $4.99 |
| *any third-party app with "attio" in the name* | — | **0 exist** | — |

Two observations that decide this.

**First, the factory pattern has already been run here, by someone else.** Ruslan Savchyshyn ships
the same business-card scanner as a thin skin against both HubSpot and Pipedrive — exactly the
proposed structure. Combined result: **35 ratings.** That is the measured ceiling of this strategy,
not a guess.

**Second, note the naming.** "Business Card Reader **4** Hubspot" — not "for". That is a deliberate
trademark dodge by a developer who presumably learned why.

---

## 3. Everything in this category is free

No paid CRM companion with meaningful traction exists in the sampled results. The single paid
third-party entry (`HubSpot Marketing Prep`, $4.99) has 0 ratings. First-party apps are all free:
HubSpot 15,408 ratings · Lead Connector 4,009 · HighLevel 3,689 · Zoho CRM 2,683 · Pipedrive 665.

There is no proven price point, and the portfolio rule forbids subscription — which is how every
competitor in this space actually monetizes. **A flat-priced B2B CRM companion has no precedent on
this store to point at.**

Side note worth having: **Pipedrive's own iOS app sits at 3.8★ with 665 ratings.** That is a rot
signal by the usual detector. It does not rescue the case, because the app is free and the buyer
expenses Pipedrive itself — but it is the one genuine weakness found.

---

## 4. Two risks that are larger than the ASO question

**Guideline 4.3 (spam).** Three or four apps sharing one core and differing only by which CRM they
skin is the textbook shape 4.3 targets. The portfolio already carries 4.3 exposure on the AISixteen
trilogy and manages it with genuinely divergent UI grammar. Skins that differ only by connector have
no such defence. **This risk is created entirely by the factory pattern and disappears if one app
ships.**

**Guideline 5.2.1 / trademark.** HubSpot, Pipedrive, GoHighLevel and Attio are registered marks.
Nominative "for X" use is a real doctrine but it is not an App Review policy, and the brand owner
can act independently of Apple. The surviving examples avoid "for". Any name using a CRM brand
should be treated as revocable, and the app should not depend on it.

Two further conversion problems, outside ASO but fatal if unaddressed:

- **Token custody.** A HubSpot private-app token is broadly scoped. Asking a business owner to paste
  one into an unknown solo developer's app is a hard sell no ASO fixes. On-device custody is the
  right architecture and the right story — it must be the *first* thing on the product page, not a
  privacy footnote.
- **Foundation Models device gate.** On-device Apple Intelligence needs an eligible device with the
  feature enabled. Same constraint flagged for the tarot build. On a B2B buyer's older work phone
  the app does nothing.

---

## 5. The reframe that actually decides this

The stated second purpose is a **freelance portfolio artifact** — something installable from the
App Store during an Upwork sales call, demonstrating a real LangGraph StateGraph, a normalized
connector layer, human-in-the-loop approval, token custody and an audit log.

**Under that criterion the ASO analysis is nearly irrelevant.** A sales-call artifact needs one
listing that exists and demos well. It does not need to rank, and it does not need revenue.

That is a legitimate goal and this concept serves it well. It is simply a different goal from every
other app in this repo, and it should be judged and scoped as such — the screening questions in
both job descriptions map onto features, not onto App Store placement.

---

## 6. Which skin first — if one ships anyway

**HubSpot.** It is the only brand with generic-modifier autocomplete depth (`hubspot crm`,
`hubspot sales`, `hubspot free`, `hubspot ai`), it has a free tier so the addressable base is
largest, and `hubspot ai` returning as a hint means the intent already exists as a query.

Not GoHighLevel first, despite the strongest economic argument (AI Employee at $50–97/mo per
sub-account). Its search surface is one hint on the one-word spelling, its buyer is the agency owner
rather than the 1.4M white-labelled SMBs, and its ecosystem sells through agency channels rather
than App Store search. It is a good *second* skin and a bad first listing.

Attio last — zero third-party presence, 28 ratings on the first-party app, no measurable search.

---

## 7. RECOMMENDATIONS

| # | Recommendation | Basis |
|---|---|---|
| 1 | **Ship one app, not a factory.** | Factory measured at 35 total ratings; creates the 4.3 risk by itself |
| 2 | **Judge it as a portfolio artifact, not a revenue app.** | No category demand, no paid precedent, brand traffic not safely capturable |
| 3 | **HubSpot first** if a skin is used at all. | Only brand with generic-modifier hint depth incl. `hubspot ai` |
| 4 | **Keep the brand out of the app name; put it in the subtitle/description.** | Surviving examples avoid "for"; name should not be revocable |
| 5 | **Lead the product page with on-device token custody.** | Pasting a scoped CRM token is the conversion blocker, not discovery |
| 6 | **Do not build the GHL skin on the AI-Employee price argument.** | Buyer is the agency owner; ecosystem does not sell via App Store search |
| 7 | **Resolve the Foundation Models device gate before scoping.** | B2B buyers on older devices get a non-functional app |
| 8 | **Do not use this to test the portfolio's pricing model.** | Everything here is free/subscription; no signal transfers back to the utility apps |

---

## 8. What was NOT measured

Reviews of the first-party CRM apps (the missing-function list), non-US storefronts, Google Play as
a demand proxy, and whether HubSpot's App Marketplace terms permit an App Store listing at all —
that last one is a contract question, not a measurement, and should be read before any naming
decision.
