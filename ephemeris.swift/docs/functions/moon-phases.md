# Moon phases and lunar calendar

**Status:** **shipped** — engine, month calendar, iOS/macOS widget and full/new-moon notifications.
Void-of-course is now implemented too (`Events/VoidOfCourse.swift`), as an optional overlay that is
off by default
**Lives in:** `EphemerisKit/Sources/EphemerisKit/Events/MoonPhases.swift` (quarters, illumination,
waxing state, current phase) over `Astronomy/RiseSet.swift` for moonrise/moonset. The older
`Lunations.swift` still feeds the event timeline and is unchanged
**Surfaces:** `MoonCalendarView.swift` (a Sky **destination**, pushed from a live row) · `MoonDisc.swift` (hemisphere-correct
terminator) · `EphemerisWidgetIOS/MoonPhaseWidget.swift` · `Services/MoonNotifications.swift`
**Tests:** `MoonPhasesTests.swift` (14) · `VoidOfCourseTests.swift` (11) · `MoonDiscTests.swift` (5) ·
`MoonNotificationTests.swift` (6) · `EventCatalogTests.swift` ·
**Oracle:** `Oracles+moonphases.swift` (3 entries, Espenak) · `Oracles.swift`
**Gate:** 0 — needs **no birth data**. See [`../ASTROLOGY_LINKS.md`](../ASTROLOGY_LINKS.md)

## What it does

New moon, full moon and the quarters — found by root-finding on Sun–Moon elongation, the same
machinery as [[events]]. Plus the derived layer a lunar calendar needs: illuminated fraction for
any instant, the current phase name, moonrise and moonset, and void-of-course periods (the Moon
between its last aspect and its next sign ingress).

The computation is already there. What is missing is that it is buried in a general event timeline
rather than presented as the thing a large audience actually wants.

## Why anyone pays

⚠️ **This is the correction to an earlier read.** Measured 2026-08-17, moon-phase is the **only
consumer-facing astro niche with a working paid model**:

| App | Price | Ratings | State |
|---|---|---|---|
| **Mooncast** | **$3.99** | **3,619** | active (2026-02) |
| **My Moon Phase Pro — Alerts** | **$3.99** | **2,581** | active (2026-06) |
| The Moon: Calendar Moon Phases | Free | 117,721 | — |

~6,200 combined *paid* ratings at $3.99. Lower price than the $8.99–29.99 chart tier, far higher
volume. Demand: `moon calendar` returns 10 autocomplete hits with roughly five generic.

**And it is gate-0** — it works before a user has entered anything. That makes it the natural
first-run surface for an app whose every other function is locked behind birth data.

## The oracle

**Kind: external.** Genuinely well-served — unusual for anything esoteric-adjacent.

| Source | What it pins |
|---|---|
| **NASA GSFC / national almanacs** | published new- and full-moon times, to the minute, for any year |
| **Meeus, *Astronomical Algorithms*, ch. 49** | phases of the Moon, with worked examples carrying numbers to transcribe |

| Identity | Must hold |
|---|---|
| Phase exactness | at a returned new moon, Sun–Moon elongation is **0°** ±1e-6°; full is **180°** |
| Published agreement | transcribed NASA times match to within the stated tolerance — this is real external ground truth, not construction |
| Synodic spacing | consecutive new moons are ~29.53059 days apart |
| Illumination closure | fraction is 0 at new and 1 at full, monotonic between, and never leaves [0,1] |
| Quarter ordering | new → first quarter → full → last quarter, strictly, with no skips |
| Void-of-course | starts at the Moon's last exact aspect and ends at its sign ingress — both from existing machinery |
| Polar honesty | moonrise/moonset can fail to occur at high latitude; absence must be reported, never fabricated |

**What a wrong implementation cannot fake:** agreement with published NASA times across a decade.
A mean-phase approximation drifts by hours from true phase and fails immediately.

## Suggested design

- **A calendar grid, not a timeline.** This is the one function whose audience thinks in months.
  It is a different surface from [[events]] — do not merge them.
- **A widget is the point.** Current phase, illumination, days to full. This is the most
  glanceable value in the entire app and the reason the two paid competitors sell.
- **Notifications for full and new moon** — both paid incumbents lead on alerts. That is the
  feature being bought.
- Void-of-course as an optional overlay for practitioners; off by default, since it means nothing
  to the larger audience.
- ⚠️ **Render the moon correctly for the hemisphere.** A southern-hemisphere waxing crescent points
  the other way. Getting this wrong is a visible, frequently-reported defect.
- Polar latitudes: say "the Moon does not set today" rather than inventing a time.

## Failure modes

- Mean phase instead of true phase — passes a spot check, drifts hours over a year
- Northern-hemisphere-only moon rendering
- Fabricating moonrise/moonset above the Arctic Circle
- Merging this into the event timeline, where its audience will not find it

## Related

[[events]] · [[astronomy-core]] · [[planetary-hours]] · [[returns]]
