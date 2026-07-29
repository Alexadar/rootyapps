# UI-test plan — audit, build, run and fix an app's UI tests, then ship the fix

> **Usage:** replace every `<app>` with one app folder name, paste the whole thing into a fresh
> Claude Code session opened at `/Users/oleksandr/Projects/rootyapps`, and send. One app per session.
> You need supply nothing else: the whole testing plan is inline, and the one hand-off (§F, the
> release mechanics) points at a file already in the repo.
>
> App folders: `kerfcalc.swift` · `truecourse.swift` · `ephemeris.swift` · `eartharound.swift` ·
> `marinenav` · `overtonelab.swift` · `par` · `producertycoon.swift`

---

You are working on **`<app>`** in this monorepo, and only on it. Do not modify other app folders.

Your job, end to end: **audit its UI tests, bring them up to the standard below, run them on every
platform the app ships, fix what they find, and get the fix into App Store review** — stopping to ask
me only where this prompt says to stop.

**Everything about testing is in this prompt** — §A–§E and the appendix are complete on their own,
so do not go looking for context before starting. Repo files that matter:

| File | When |
|---|---|
| `docs/RELEASE_runbook.md` | **Required for §F only.** Archive, upload, attach, submit. |
| `storypole/` | Optional worked example — every rule below is already applied there: 37 UI tests green on iPhone, iPad and macOS, 169 Kit assertions in 0.014 s, submitted to review. Copy `storypole/storypoleUITests/UITestSupport.swift` almost verbatim, and read `.../DimensionKitTests/TapeCalcStateSpaceTests.swift` for the §C.2 pattern. |
| `uitests.md` | Optional — the same rules with more war stories. |

**When this prompt and any doc disagree, follow this prompt.**

---

## A. Non-negotiable rules

1. **XCUITests run on simulators. Never on my physical devices** — a run launches and kills the app
   dozens of times. Devices get installs only, so I can try the real thing.
2. **A macOS UI-test run seizes my entire screen for several minutes. Ask me before the first one.**
   iOS-Simulator runs need no permission.
3. **If a fix changes anything visible, HALT and ask me.** See §E. This is the most important rule here.
4. Never create an App Store app record, change price, or assign a build to an external TestFlight
   group without asking. Submitting a version is authorised by this prompt once §D and §E are clean.
5. **Never fork the shared `marketing/` scripts into an app folder.** Call them in place. Three apps
   once shipped the same font bug because each had a private copy.
6. No StoreKit, ads, subscriptions or IAP in a utility app.
7. **Commit only if I ask.** Leave work in the tree and say so.
8. Report honestly. If tests fail, paste the output. If you skipped something, name it and say why.

---

## B. Audit first — do not write anything yet

Run these and report the hit count for each. Every one is a real failure mode, explained in §H.

```bash
cd <app>

# 1. Hard-coded element types. Every hit on a RESULT or CARD identifier is a latent
#    cross-platform failure: it passes on iOS and fails on macOS, and the failure message
#    reads exactly like the app failing to render.
grep -nE 'app\.(otherElements|staticTexts|buttons|images)\["' *UITests/*.swift

# 2. Direct `.label` reads. On macOS a plain SwiftUI Text has an EMPTY label; its string is
#    in `value`. Every such assertion silently compares against "".
grep -n '\.label' *UITests/*.swift

# 3. Accessibility container shapes — see §H traps 1, 4, 5.
grep -rn "accessibilityElement(children:" --include="*.swift" .
grep -rn "accessibilityIdentifier" --include="*.swift" . | wc -l

# 4. Test hooks that ship to customers. Should resolve to ONE accessor file (see §C.5).
grep -rn "ProcessInfo.processInfo.environment" --include="*.swift" .

# 5. What exists today.
grep -rh "func test" *UITests/*.swift 2>/dev/null | wc -l
find Kits -name Package.swift 2>/dev/null | wc -l
```

Also confirm the test target is actually wired, because a missing test action makes
`xcodebuild build-for-testing` print success while building nothing:

```bash
grep -A6 "type: bundle.ui-testing" project.yml     # needs TEST_TARGET_NAME + supportedDestinations
```

**If the app ships on the Mac, the UI-test target needs `supportedDestinations: [iOS, macOS]`** or
`xcodebuild` refuses with "does not support My Mac's platform".

---

## C. Bring the suite up to standard

Four layers. They prove different things:

| Layer | Proves | Cost |
|---|---|---|
| `swift test` per Kit | the number is right, against a cited published source | ~ms |
| Model/unit tests | the state space — every branch, toggle, operator path | ~ms |
| UI tests | the right number reaches the right label; deep links land; known defects stay fixed | **~1.1 s per interaction** |
| Looking at rendered frames | clipping, truncation, collisions, *the wrong screen entirely* | minutes |

**Do not re-litigate arithmetic in a UI test.** The Kits own that. A UI test proves *wiring*.

### C.1 One numeric check per feature, plus a coverage guard

One test per shipping calculator/feature asserting a known value on screen. Duplicate the expected
values from the Kit tests **on purpose** — if someone changes a Kit answer, both layers must be
updated, and the diff makes that visible. Then add a guard so a new feature cannot ship untested:

```swift
func testEveryToolHasANumericCheck() {
    let covered = [/* every tool id asserted above */]
    XCTAssertEqual(covered.count, <N>, "the catalog ships <N> tools")
    XCTAssertEqual(Set(covered).count, covered.count, "duplicate in the coverage list")
}
```

### C.2 Cover the STATE SPACE, not the happy path

**This is the part almost every app here is missing.** A shipped watch app had a measurement-unit
toggle that did nothing: every number correct, every screen rendering, suite green — because controls
were only ever tested in their default state.

| Control | Assert | Catches |
|---|---|---|
| Toggle / segmented / picker | flip it, assert the OUTPUT changed; flip back, assert it RETURNED. Every position, both directions. | dead toggle · one-way toggle · label changes but number doesn't |
| Unit switch (in/mm, ft/m, °/%) | same input in both units, and the conversion between them | a unit that relabels without converting |
| Operator pairs | `+`/`−`, `×`/`÷`, both orders, plus the inverse `a + b − b == a` | sign dropped · subtraction implemented as addition |
| Chained ops / accumulator | `a op b op c` for every pairing; `=` pressed twice | state left dirty between operations |
| Mode × mode | the CROSS PRODUCT, not each alone | the pair nobody tried |
| Boundaries & refusals | zero, negative, empty, and the value the app must REFUSE — assert the refusal is *visible* | silent clamping, silent `nil`, wrong answer where an error was owed |

Rule of thumb: for a control with more than one state, the test count equals the number of states;
for two interacting controls, the product.

**Put the combinatorial cases in a Kit or model test, never XCUITest.** 64 combinations through a
keypad at ~1.1 s per tap is 20 minutes nobody will run; against the model it is microseconds. Keep
exactly **one** UI assertion per control to prove the binding is wired — because a model test cannot
catch a view bound to the wrong property.

If the state machine lives in the app target (a view model, a settings store) rather than a Kit, add a
`bundle.unit-test` target for it — but check first whether the logic is already in a Kit.

### C.3 Deep links must work in BOTH layouts

Read env at launch to seed navigation (`<APP>_TOOL`, `<APP>_TAB`). **The expensive trap:** a compact
layout has a `TabView`; a regular layout has a `NavigationSplitView` with no tabs at all. If the
router sets `selectedTab` and the regular root only watches a sidebar selection, **every tab deep link
silently lands on the default screen at regular width** — which is how an iPad screenshot of a
calculator ends up captioned "Every number has a source".

```swift
func testTabDeepLinkReachesItsScreenInEveryLayout() {
    let app = XCUIApplication()
    app.launchEnvironment["<APP>_TAB"] = "2"
    app.launch()
    let marker = app.staticTexts.containing(textMatches("<text only that screen has>")).firstMatch
    XCTAssertTrue(marker.waitForExistence(timeout: 10), "deep link landed on the wrong screen")
}
```

Run it on an iPhone sim **and** an iPad sim. Passing on one proves nothing about the other.

### C.4 Pin the locale, twice

These are US-market apps. A fresh sim can boot in a comma-decimal region and every formatted number
renders `152,11`, failing tests on the separator rather than the arithmetic — and a screenshot reading
`152,11` is a wrong listing.

```bash
xcrun simctl create <APP>-iPhone com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max com.apple.CoreSimulator.SimRuntime.iOS-26-5
P=~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Library/Preferences/.GlobalPreferences.plist
/usr/libexec/PlistBuddy -c "Set :AppleLocale en_US" "$P"
```

```swift
app.launchEnvironment["<APP>_LANG"] = "en"     // belt and braces, in every launch helper
```

Never `simctl erase` a pinned sim — it wipes this.

### C.5 Test hooks must not ship

Deep links, demo seeding and locale pinning are scaffolding, and none of it belongs in a build a
customer runs: a Release app honouring `<APP>_TOOL` can have its navigation driven from outside, and
on macOS anyone can do that with `open --env`. Route every override through one accessor:

```swift
public enum LaunchOverride {
    public static func value(_ key: String) -> String? {
#if DEBUG
        ProcessInfo.processInfo.environment[key]
#else
        nil
#endif
    }
    public static func flag(_ key: String) -> Bool { value(key) == "1" }
}
```

Then `grep -rn "ProcessInfo.processInfo.environment" <sources>` must return only that file.

**Verify it with the compilation condition — not with `strings` or `nm`, which both return
clean-looking FALSE results:**

```bash
for cfg in Debug Release; do
  xcodebuild -showBuildSettings -scheme <scheme> -configuration $cfg | grep -m1 SWIFT_ACTIVE_COMPILATION_CONDITIONS
done
# Debug -> DEBUG     Release -> (empty)     ... check the watch target separately
```

`strings` cannot see these names because Swift stores strings ≤15 UTF-8 bytes inline in the String
struct, so they are immediates, never literals. `nm` on a Debug binary reads a ~200 KB loader stub —
Debug builds are a dylib split and the code lives in `<App>.debug.dylib`.

Capture and tests both use Debug builds, so nothing in the media pipeline breaks. Confirm with
`grep -rn "configuration Release" *.sh` (should find nothing).

### C.6 The three helpers every suite needs

```swift
extension XCUIElement {
    /// The string a user would read, whichever attribute this platform put it in.
    /// macOS leaves `label` EMPTY for a plain Text and puts the string in `value`.
    var text: String { label.isEmpty ? ((value as? String) ?? "") : label }
}

/// `NSPredicate(format: "label CONTAINS[c] %@")` silently matches nothing on macOS.
func textMatches(_ needle: String) -> NSPredicate {
    NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", needle, needle)
}

/// An element by identifier, whatever TYPE SwiftUI published it as — it differs per platform.
private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: id).firstMatch
}
```

Use `.text` everywhere; never `.label` directly. Use `any(...)` for every result and card.

---

## D. Run it

```bash
xcodebuild test -scheme <scheme> -destination 'platform=iOS Simulator,name=<APP>-iPhone' -only-testing:<app>UITests
xcodebuild test -scheme <scheme> -destination 'platform=iOS Simulator,name=<APP>-iPad'   -only-testing:<app>UITests
# macOS — ASK ME FIRST (it takes over the screen). Needs a one-time Accessibility grant for
# the test runner; without it you get "Timed out while enabling automation mode".
xcodebuild test -scheme <scheme> -destination 'platform=macOS' -only-testing:<app>UITests
```

Plus every Kit: `for k in Kits/*/*/; do (cd "$k" && swift test); done`. That is still the real gate.

**Expect macOS to fail where iOS passed.** That is not a macOS bug in the app — it is §H traps 2–5.
A suite that has only run on iOS almost certainly has all of them.

**In the fix loop, re-run only the failed tests.** A full macOS suite is ~6 minutes; a targeted set is
seconds. `-only-testing:` takes one test and repeats:

```bash
grep -E "^Test Case .* failed" test.log \
  | sed -E 's/.*-\[[A-Za-z]+\.([A-Za-z]+) ([A-Za-z]+)\].*/-only-testing:<app>UITests\/\1\/\2/'
```

When you changed **app** code, the affected set is wider than the failed set — a shared component is
read by tests that were green. Find them by identifier and re-run that set. Full suite once at the end,
on every platform.

**When a query fails, DUMP — do not guess.** One `print(app.debugDescription)` costs less than two
wrong hypotheses; it prints the real identifier and type of everything. In the reference build, five
plausible fixes went to the wrong layer before a dump showed the element had been present and
correctly identified the entire time. Remember `xcodegen generate` after adding a test file, or you
get "Executed 0 tests".

Do **not** shorten `waitForExistence` timeouts for speed — they cost nothing when the element is
present and only pay out when something is genuinely wrong.

---

## E. Fix what you find — and STOP if it changes the UI

Classify **every** fix before applying it:

| Kind | Action |
|---|---|
| **Test-only** — wrong element type, `.label` → `.text`, missing wait, wrong query | Fix and continue. |
| **App fix, nothing visible changes** — accessibility identifiers, `.combine` → `.contain`, DEBUG-gating a launch hook, a model/state-machine bug behind an unchanged screen | Fix and continue. State explicitly in your report that the pixels are unchanged, and why. |
| **App fix that changes ANYTHING visible** — layout, spacing, a control added/removed/renamed, any user-visible string, colours, icons, fonts | **HALT. Do not apply it.** Report what you found, what the fix would be, and what it would cost. Then ask me. |

**Why:** a screenshot freezes the build it was taken from. Any visible change invalidates every store
screenshot and preview, on every platform and in every locale, requiring a full re-capture — and
re-capture is where the expensive mistakes live. One app shipped 15 screenshot sets across 3 platforms
showing a control that had been deleted the same day. Whether that cost is worth paying is my call.

**If you are unsure whether a change is visible, treat it as visible and ask.**

---

## F. Ship the fix

Only if §D is green on every platform and §E produced **no** visible change. Otherwise stop and report.

First establish the real state — never assume it:

```python
import asc_client as a        # in marketing/logic; creds from env, see that file
for v in a.get(f"/v1/apps/{app_id}/appStoreVersions?limit=10")["data"]:
    print(v["attributes"]["platform"], v["attributes"]["versionString"], v["attributes"]["appStoreState"])
```

| State | Action |
|---|---|
| `PREPARE_FOR_SUBMISSION`, never submitted | Bump the **patch of `MARKETING_VERSION`** (not the build number), then ship. |
| `WAITING_FOR_REVIEW` | The fix can still get in, but the queued submission must be cancelled first. **Ask me before cancelling.** |
| `IN_REVIEW` | Needs a developer reject and loses the queue position. **Ask me first** — shipping as the next version is often better. |
| `READY_FOR_DISTRIBUTION` / live | New version, and write `whatsNew`. |

**The archive / upload / attach / submit mechanics live in `docs/RELEASE_runbook.md`.** Follow it
rather than improvising — it carries the signing trap, the screenshot-slot requirements, and the
several things App Store Connect's API cannot do.

---

## G. Report

Finish with, in this order:

1. The audit hit counts from §B.
2. What you changed, and in which layer (Kit / model / UI test / app).
3. Per-platform results: test counts and wall-clock, for iPhone, iPad, macOS and every Kit.
4. **Anything you halted on**, with the fix you would apply and its cost.
5. The release action taken — or the exact blocker, quoted from Apple's error.
6. Any new trap worth adding to `uitests.md`, including **negative results** — things you tried that
   did not work, so nobody repeats them.

---

## H. Appendix — the five accessibility traps, in full

Traps 2–5 are macOS-only. They are why a suite can be 100% green on iPhone and iPad and fail a third
of its tests on the Mac, with every failure printing an **empty string** — which reads like "the screen
never loaded" and sends you hunting a navigation bug that does not exist.

**1 — An identifier on a container OVERWRITES its children's.**

```swift
HStack { ForEach(options) { Button(…).accessibilityIdentifier("denominator.\(d)") } }
    .accessibilityIdentifier("denominator")      // ← destroys all six
```

All six then report as `denominator`; nothing can address one — not a test, not VoiceOver. Identifiers
go on leaves, never on both.

**2 — Never assume the element TYPE.** It changes with modifiers **and** per platform: a `.combine`d
card is a `staticText` on iOS and a **group** on macOS. `app.otherElements["x"]` passing on iOS and
failing on macOS is the single most expensive trap here, because the message is indistinguishable from
a real rendering bug. Always query by identifier alone (`any(...)`).

**3 — A plain `Text` has an EMPTY `label` on macOS**; the string is in `value`. Measured, same build:

| element | iOS | macOS |
|---|---|---|
| plain `Text` leaf | `label` = `12' 6-1/2"` | `label` = **`""`**, `value` = `12' 6-1/2"` |
| `.accessibilityElement(children: .combine)` | `label` = combined | `label` = combined |

So `.label` works on macOS *only* for combined elements. Use `.text` / `textMatches` (§C.6).

**4 — `.combine` DESTROYS the children's identifiers, and macOS synthesises a joined one.** A readout
card containing `calc.readout` and `calc.decimal` surfaced as a single element with
`identifier: 'calc.readout-calc.decimal'`, so `calc.readout` did not exist at all. iOS happened to keep
the children addressable, which is what hid it. Two correct shapes:

```swift
.accessibilityElement(children: .contain)                    // children stay addressable
.accessibilityElement(children: .combine)                    // one utterance…
.accessibilityIdentifier("bf.caution")                       // …so name the RESULT explicitly
```

This is a real accessibility defect, not merely a test problem: combining made the app's primary number
one blob to VoiceOver on both platforms, and only macOS revealed it.

**5 — An identifier on a bare container is a silent no-op on macOS.** With no `accessibilityElement`
modifier the container is never published; on iOS it usually surfaces anyway. Add `.combine` or
`.contain` first.

**Bonus, off-screen content:** neither platform publishes content that has never been on screen, and
they disagree about which shape survives scrolling. Where a prose card sits below the fold, encapsulate
the difference once rather than copying a hack into every call site:

```swift
func spProse(_ identifier: String) -> some View {
#if os(macOS)
    self.accessibilityElement(children: .combine).accessibilityIdentifier(identifier)
#else
    self.accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
#endif
}
```

### Measured performance facts

- `app.launch()` ≈ 2.4 s (macOS) / 4 s (iOS sim). Any interaction ≈ **1.1 s** — XCUITest re-snapshots
  the accessibility tree and waits for idle before every event.
- A 38-test suite took 441 s, and the sum of the test bodies *was* the whole run — so there is no
  harness overhead to trim. The only lever that changes the order of magnitude is moving combinatorial
  coverage out of the UI (§C.2).
- **Dead ends, already tried, do not repeat:** disabling animations behind a flag (65.9 s → 65.5 s, no
  effect — the ~1.1 s is the snapshot handshake, not animation); scroll-into-view helpers; macOS
  window-state restoration (`-ApplePersistenceIgnoreState`); `scroll(byDeltaX:deltaY:)` direction. All
  four were chased against a failure whose real cause was a hard-coded element type (trap 2).
- `-parallel-testing-enabled YES` shards by test **class**, not method — two big classes give two
  workers. iOS Simulator only; on macOS parallel UI tests put several instances of a single-instance
  app in a focus fight.

### Other traps worth knowing

- `press(forDuration:thenDragTo:)` takes an **element**, not a coordinate. For a drag within one
  element, go coordinate-to-coordinate via `XCUICoordinate`.
- Changing view identity mid-gesture cancels the gesture. An `if isScrubbing { A } else { B }` swap
  killed a drag after one step; render one view and change only what it draws.
- watchOS: focusable `Button`s steal Digital Crown focus, leaving the crown dead and actions applying a
  stale value. Fix with `@FocusState` and hand focus back — and **write the regression test**, because
  the crown IS scriptable: `XCUIDevice.shared.rotateDigitalCrown(delta:)`, in `XCUIAutomation`'s
  `XCUIDevice.h` gated on `TARGET_OS_WATCH`, since Xcode 13. Scrub → tap the button → scrub again;
  before the fix the second rotation changes nothing. Only *rendering* still needs eyes (a
  complication on a real face), so "install and look" applies to appearance, **not** to interaction.
