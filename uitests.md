# UI tests — the shared harness

> **Paste this into a session working on any app in this monorepo.** Self-contained; assume no
> memory of other chats. It describes how to build a UI-test suite that catches real things, how to
> run it on every platform, and every trap that has already cost time.
>
> Written 2026-07-29 from the Storypole build. Its first honest run of a "finished" suite found
> **five app bugs and five test bugs**, and rendered frames found four more that no assertion could
> have. Every rule below is here because something shipped, or nearly shipped, without it.
>
> **Start with §3 if the suite has never run on macOS.** That same suite — 38/38 green on iPhone and
> iPad — failed **15 of 39 on the Mac**, every failure printing an empty string. None of it was a
> macOS bug in the app: SwiftUI publishes accessibility differently there, and four distinct traps
> (§3) were hiding behind iOS's more forgiving behaviour. One was a genuine accessibility defect —
> the app's primary number was unreachable by VoiceOver on both platforms, and only macOS said so.

---

## 0. Three layers. All three are required.

Every app here is oracle-first: the maths lives in `Kits/*/` and is asserted by `swift test`
against cited published sources. **That is where correctness is proved.** Do not re-litigate
arithmetic in a UI test.

| Layer | Proves | Cost |
|---|---|---|
| `swift test` per Kit | the number is right, against a cited authority | milliseconds |
| **UI tests** | the right number reaches the right label; known defects stay fixed | 5–20 s each |
| **Looking at rendered frames** | clipping, truncation, collisions, *the wrong screen entirely* | minutes |

**The third row is not optional and is not covered by the second.** Storypole's suite was 19/19
green while the app was shipping a clipped card, a truncated sidebar, two overlapping labels, and —
worst — a **screenshot of the calculator captioned "Every number has a source"**, because a deep
link silently landed on the wrong screen. Assertions saw nothing wrong. Frames did.

---

## 1. Simulator for tests. Devices for looking. Ask before macOS.

```bash
# iPhone
xcodebuild test -scheme <app> -destination 'platform=iOS Simulator,name=<APP>-iPhone' \
  -only-testing:<app>UITests

# iPad — RUN THIS TOO. Several apps here have had iPad-only bugs.
xcodebuild test -scheme <app> -destination 'platform=iOS Simulator,name=<APP>-iPad' \
  -only-testing:<app>UITests

# macOS — SEIZES THE WHOLE SCREEN. Ask the owner first. See §9 for the permission it needs.
xcodebuild test -scheme <app> -destination 'platform=macOS' -only-testing:<app>UITests

# watchOS — XCUITest is not worth trusting here. Install and look.
```

**After a failure, re-run ONLY the failed tests.** A full UI suite is ~7½ minutes on macOS and the
whole point of a fix round is a fast answer on the thing you changed. `-only-testing:` takes a
single test, and repeats:

```bash
xcodebuild test -scheme <app> -destination 'platform=macOS' \
  -only-testing:<app>UITests/DefectChecks/testBoardFeetShowsTheCaution \
  -only-testing:<app>UITests/DefectChecks/testWireGaugeStatesItsLimits
```

Pull the names straight out of the last log — no hand-transcribing:

```bash
grep -E "^Test Case .* failed" test.log | sed -E 's/.*-\[[A-Za-z]+\.([A-Za-z]+) ([A-Za-z]+)\].*/-only-testing:<app>UITests\/\1\/\2/'
```

**When you changed APP code rather than a test, the affected set is wider than the failed set** —
a shared component (a readout, a result row) is read by tests that were green. Find them by
identifier and re-run that set, not the whole suite:

```bash
awk '/func test/{n=$2; sub(/\(.*/,"",n)} /calc\.readout|bf\.caution/{if(n) print n}' <app>UITests/*.swift | sort -u
```

Run the **full** suite once at the end, on every platform, before calling it done. Targeted re-runs
are for the fix loop; they are not the definition of done (§11).

**Never point a test run at the owner's physical device.** It launches and kills the app dozens of
times. Physical devices get installs only, so the owner can try the real thing:

```bash
xcodebuild -scheme <app> -destination 'id=<udid>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <udid> <path>/<App>.app
```

---

## 2. Dedicated, locale-pinned simulators

One per app, so a concurrent capture from another session can never be frontmost:

```bash
xcrun simctl create <APP>-iPhone com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5
```

**Then pin the region, or ten tests fail on a decimal separator.** A fresh sim can boot in a
comma-decimal region, and anything formatting through `NumberFormatter` renders `152,11`:

```bash
P=~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Library/Preferences/.GlobalPreferences.plist
/usr/libexec/PlistBuddy -c "Set :AppleLocale en_US" "$P"
```

Belt and braces — **pin it in the test too**, so the suite is deterministic anywhere:

```swift
app.launchEnvironment["<APP>_LANG"] = "en"
```

Not cosmetic. These are US-market apps; a screenshot reading `152,11` is a wrong listing.

---

## 3. Accessibility identifiers — five traps, each of which cost a full debugging round

Traps 3–5 are **macOS-only**. They are the reason a suite can be 100% green on iPhone and iPad and
still fail 15 of 39 on the Mac, with every failure message printing an empty string — which reads
like "the screen never loaded" and sends you hunting for a navigation bug that does not exist.
If your suite has only ever run on iOS, assume you have all three.

**Trap 1 — an identifier on a container OVERWRITES its children's.**

```swift
HStack { ForEach(options) { Button(…).accessibilityIdentifier("denominator.\(d)") } }
    .accessibilityIdentifier("denominator")      // ← destroys all six
```

All six chips then report as `denominator`. Nothing can address an individual one — not a test, not
VoiceOver. Identifiers go on leaves, never on both.

**Trap 2 — never assume the element TYPE.** SwiftUI decides whether a styled card surfaces as
`otherElement`, `staticText` or something else; it changes with modifiers **and it differs per
platform**. Query by identifier alone:

```swift
private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: id).firstMatch
}
```

**This is the single most expensive trap in this document — not because it is subtle, but because
it is indistinguishable from a real bug.** Two assertions written as
`app.otherElements["bf.caution"]` passed on iOS and failed on macOS, where that same card is
published as a `StaticText`. The failure says only "the caution must be shown", which reads as *the
app is not rendering the card*. Chasing that produced, in order: swapping `.combine` for `.contain`
(broke iOS), moving the identifier to the leaf `Text` (broke iOS differently), adding a
scroll-into-view helper, flipping the macOS scroll direction, and disabling macOS window-state
restoration — five plausible fixes, all landing on the wrong layer, before a dump showed the element
had been present and correctly identified the entire time. **Grep the suite for hard-coded element
types before you debug anything else:**

```bash
grep -nE 'app\.(otherElements|staticTexts|buttons|images)\["' <app>UITests/*.swift
```

Every hit on a *result* or *card* identifier is a latent cross-platform failure. Keys and text
fields are safe — their type is stable.

**Trap 3 (macOS) — a plain `Text` has an EMPTY `label`; its string is in `value`.**

Measured from `app.debugDescription` on both platforms, same build, same view:

| element | iOS | macOS |
|---|---|---|
| plain `Text` leaf | `label` = `12' 6-1/2"` | `label` = **`""`**, `value` = `12' 6-1/2"` |
| `.accessibilityElement(children: .combine)` | `label` = combined | `label` = combined |

So `element.label` works on macOS *only* for combined elements. Every assertion reading a plain
`Text` compares against `""`. Same trap in predicates: `NSPredicate(format: "label CONTAINS[c] %@")`
silently matches nothing. Never touch `.label` directly — go through a helper:

```swift
extension XCUIElement {
    /// The string a user would read, whichever attribute this platform put it in.
    var text: String { label.isEmpty ? ((value as? String) ?? "") : label }
}
func textMatches(_ needle: String) -> NSPredicate {
    NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", needle, needle)
}
```

**Trap 4 (macOS) — `.accessibilityElement(children: .combine)` DESTROYS the children's identifiers,
and macOS synthesises a joined one.** A readout card with `calc.readout` and `calc.decimal` inside
surfaced as a single element with `identifier: 'calc.readout-calc.decimal'` — so
`app.staticTexts["calc.readout"]` did not exist *at all*. iOS happened to keep the children
addressable, which is what hid it.

Two correct shapes, and which to use is a real design decision, not a test workaround:

```swift
// Children must stay individually addressable (a readout: fraction, decimal, error) → .contain
.accessibilityElement(children: .contain)

// The block is one utterance (a prose caveat, a label+value row) → .combine, then name the RESULT
.accessibilityElement(children: .combine)
.accessibilityIdentifier("bf.caution")          // ← without this, macOS invents the identifier
```

**Trap 5 (macOS) — an identifier on a bare container is a silent no-op.** With no
`accessibilityElement` modifier, a `VStack` is never published as an element on macOS and the
identifier goes nowhere. On iOS it usually surfaces anyway. Add `.combine` or `.contain` first.

Corollary to Trap 2: a `.combine`d element is **not** a `staticText` on macOS — it is a group. So
`app.staticTexts["bf.total"]` fails there while `any(app, "bf.total")` succeeds. Every `ResultRow`
style query must go through `any()`.

**When a query fails, DUMP — do not guess.** Two rounds of guessing cost more than one dump:

```swift
func testDumpHierarchy() {
    let app = XCUIApplication(); app.launch()
    _ = app.buttons["<known id>"].waitForExistence(timeout: 10)
    print("<<<H>>>"); print(app.debugDescription); print("<<<END>>>")
}
```
Then `sed -n '/<<<H>>>/,/<<<END>>>/p' log`. It prints the real identifier *and* type of everything.
Remember `xcodegen generate` after adding the file or you get "Executed 0 tests".

**Convention:** `<area>.<thing>` — `calc.readout`, `key.digit7`, `bf.total`. One on **every input
and every result**.

---

## 4. Deep links — and verify they work in BOTH layouts

Read env at launch and seed navigation:

```swift
if let raw = env["<APP>_TOOL"], let tool = Tool(rawValue: raw) { … }
else { selectedTab = Int(env["<APP>_TAB"] ?? "") ?? 0 }
```

**⚠️ THE EXPENSIVE ONE.** A compact layout has a `TabView`; a regular layout has a
`NavigationSplitView` with **no tabs at all**. In Storypole `Router` set `selectedTab`, and
`RegularRoot` only watched `router.sidebar` — so **every `<APP>_TAB` deep link silently landed on
the default screen at regular width.** It produced an iPad screenshot of the calculator captioned
*"Every number has a source"*, and put the same wrong screen into the macOS preview. One upload
from a wrong listing.

Every app here with both layouts is a candidate. **Check it, and keep the regression test:**

```swift
func testTabDeepLinkReachesItsScreenInEveryLayout() {
    let app = XCUIApplication()
    app.launchEnvironment["<APP>_TAB"] = "2"
    app.launch()
    let marker = app.staticTexts.containing(
        textMatches("<text only that screen has>")).firstMatch     // §3 Trap 3 — not `label ...`
    XCTAssertTrue(marker.waitForExistence(timeout: 10), "deep link landed on the wrong screen")
}
```

---

## 4a. Cover the STATE SPACE, not the happy path

**The bug that wrote this section:** a watchOS measurement-unit toggle that did nothing. Every
calculation was right, every screen rendered, every test was green — and the toggle was dead. No
assertion ever flipped it, because the suite tested each screen in its **default state only**.

A calculator is mostly branches, and a suite that walks one path through them is theatre. Enumerate:

| Control | What must be asserted | The failure it catches |
|---|---|---|
| **Toggle / segmented / picker** | Flip it and assert the OUTPUT CHANGED. Then flip back and assert it **returned**. Both directions, every position. | Dead toggle · one-way toggle · toggle that changes the label but not the number |
| **Unit switch** (in/mm, ft/m, °/%) | The same input in both units, and the conversion between them. | A unit that relabels without converting — the number stays, the unit lies |
| **Operator pairs** | `+` and `−`, `×` and `÷`, in both orders. Then the inverse: `a + b − b == a`. | Sign dropped · subtraction implemented as addition · operator applied to the wrong operand |
| **Accumulator / chained ops** | `a op b op c` for every pairing, plus `=` pressed twice. | State left dirty between operations. Storypole shipped exactly this: `10' × 8' =` then `× 4"` computed an area a second time because the accumulator's dimension was not reset. |
| **Mode × mode** | If two modes exist, test the CROSS product, not each alone. | The pair nobody tried — a precision setting that only misbehaves in metric |
| **Boundary + refusal** | Zero, negative, empty, and the value the app must REFUSE. Assert the refusal is *visible*. | Silent clamping, silent `nil`, a wrong answer where an error was owed |

**Rule of thumb:** for every control that has more than one state, the test count is the number of
states, not one. For every pair of controls that interact, it is the product.

### Where this coverage belongs — and why it is not the UI suite

Driving 64 combinations through a keypad at ~1 s per tap is 20 minutes and nobody will run it.
Driving them through the model is milliseconds. So split by what each layer can actually prove:

| Layer | Owns | Cost |
|---|---|---|
| **Kit tests** (`swift test`) | the arithmetic, against its cited source | ~ms |
| **Model tests** (app unit-test target, no UI) | **the state space above** — every toggle, operator, accumulator path, mode pair | ~ms |
| **UI tests** (XCUITest) | the *wiring*: the key reaches the model, the model's answer reaches the screen, the deep link lands, the layout holds | **~1 s per interaction** |

Most apps here have Kit tests and UI tests and **no middle layer**, so combinatorial coverage has
nowhere cheap to live and silently doesn't get written. If the app has an `ObservableObject` driving
a screen (`CalcModel`, a view model, a settings store), it needs a `bundle.unit-test` target — that
is where "every toggle, both directions" goes. The UI suite then asserts the toggle **exists and is
hooked up once**, not that it is correct in all 64 combinations.

**A dead toggle is caught by the model test only if the toggle's binding is the thing under test.**
If the model is right and the view binds to the wrong property, only the UI catches it — so keep
exactly one UI assertion per control: flip it on screen, assert the readout changed.

Add `<APP>_DEMO=1` too — it seeds a representative calculation. Costs nothing in normal use, and
stops a store screenshot of the front door showing `0`.

---

## 4b. Test hooks must not ship

A UI suite needs the app to be drivable: deep-link to a screen, pin the locale, seed a demo value
for a screenshot. That is scaffolding, and **none of it belongs in a build a customer runs.** A
Release app that honours `<APP>_TOOL` is an app whose navigation can be driven from outside it —
and on macOS anyone can do that with `open --env`.

Put every launch override behind ONE accessor, compiled out of Release:

```swift
public enum LaunchOverride {
    /// The value of a launch override, or `nil` in a Release build.
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

Then `grep -rn "ProcessInfo.processInfo.environment" <app-sources>` must return **only that file**.
Storypole had six raw reads scattered across the app, the watch app and the shared design module —
`_TOOL`, `_TAB`, `_DEMO`, `_LANG`, `_WIN`, `_WATCH_TOOL` — every one of them shipping.

Capture and tests both run Debug builds, so nothing in the pipeline breaks. Confirm that rather than
assume it: `grep -rn "configuration Release" *.sh` should find nothing in the capture scripts.

### Verifying it is really gone — two probes that LIE

Both of these look like proof and are worthless:

| probe | why it fails |
|---|---|
| `strings <binary> \| grep STORYPOLE_` | Swift stores strings ≤15 UTF-8 bytes **inline in the String struct**. `STORYPOLE_TOOL` is 14 bytes, so it is an immediate, never a literal in `__cstring`. Returns 0 hits in Debug *and* Release — a clean-looking result that proves nothing. |
| `nm -u <app>/Contents/MacOS/<App>` | A Debug build is a **dylib split**: the main binary is a ~200 KB loader stub and the code is in `<App>.debug.dylib` beside it. You are reading the stub. (This is in the root README too.) |

The probe that actually decides it is the compilation condition, because the guarantee is
compile-time, not runtime:

```bash
for cfg in Debug Release; do
  xcodebuild -showBuildSettings -scheme <app> -configuration $cfg \
    | grep -m1 SWIFT_ACTIVE_COMPILATION_CONDITIONS
done
# Debug -> DEBUG          Release -> (empty)
```

With `DEBUG` undefined in Release, `LaunchOverride.value` **is** `return nil`. Check the watch
target separately — it is a different target with its own settings.

---

## 5. What to assert

Two files, answering different questions.

### `DefectChecks.swift` — this app's reasons to exist

One test per named defect, each quoting the review or bug it came from so nobody deletes it as
redundant. Plus:

- **`app.state == .runningForeground`** after anything risky. "A label exists" does not prove the
  app did not crash and relaunch.
- **A control-is-never-disabled sweep** across every stage of a flow, if that is a defect here.
- **Every screen opens** — deep-link into all of them, assert non-empty and still running.

### `CalculationChecks.swift` — one number per feature

For each tool, assert the **on-screen value** against the **same worked example its Kit asserts**.
Duplicate the number deliberately: if a Kit's answer changes, both layers must change and the diff
makes that visible.

```swift
/// A 2×4×8 is exactly 5⅓ board feet — NIST PS 20-20 §2.2.
/// Kit oracle: `LumberOracleTests.boardMeasure`.
func testBoardFeetForATwoByFour() {
    let app = open("boardFeet")
    assertShows(app, "bf.total", "5.333")
}
```

End with a **coverage guard**, or a new feature ships untested while the suite stays green:

```swift
func testEveryToolHasANumericCheck() {
    XCTAssertEqual(covered.count, Tool.allCases.count)
}
```

---

## 6. Gestures

- `XCUIElement.press(forDuration:thenDragTo:)` takes an **element**. To drag to a point on the
  *same* element, go through coordinates:
  ```swift
  let from = el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
  let to   = el.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
  from.press(forDuration: 0.05, thenDragTo: to)
  ```
- **If a drag does one step then dies, the view is swapping identity mid-gesture.** An `if` in the
  body that flips when the drag sets state cancels the gesture. Render one view and change what it
  *draws*; drive appearance with `.opacity`, never insertion/removal. The same swap makes SwiftUI
  cross-fade the outgoing view, which reads as a **ghost sliding under your finger**.

---

## 7. watchOS: focusable Buttons steal the Digital Crown

`.digitalCrownRotation(…)` only delivers to the view that **holds focus**, and `Button` is
focusable. Add any button beside a crown-driven field — a mode picker, a stepper — and tapping it
kills the crown. Nothing crashes; the value just stops responding, and any action consuming it
re-applies the stale amount.

```bash
grep -rl "digitalCrownRotation" --include='*.swift' . | xargs grep -ln "Button\|Toggle\|Picker"
```

Fix: `@FocusState`, `.focused($x)` on the crown view, and set it back in `.onAppear` **and** every
button's action. `.focusable()` alone is not enough.

**Nothing catches this but a wrist** — it only manifests on watchOS, and iOS/macOS builds compile
neither the target nor its focus behaviour.

---

## 8. Scheme wiring

```yaml
schemes:
  <app>:
    build:
      targets:
        <app>: all
        <app>UITests: [test]
    run: { config: Debug }
    test:
      config: Debug
      targets: [<app>UITests]
```

- `xcodebuild build-for-testing` on a scheme with **no** test action silently builds nothing and
  still prints `TEST BUILD SUCCEEDED`. It is not evidence the tests compile.
- The UI-test target must declare every platform it will run on, or macOS refuses outright:
  ```yaml
  supportedDestinations: [iOS, macOS]     # "does not support My Mac's platform" otherwise
  ```
- A watch app needs **its own scheme**: `xcodebuild -target … -derivedDataPath` is rejected
  ("-scheme is required"), and the main scheme cannot target a watch simulator.

---

## 9. macOS needs a one-time permission

```
Failed to initialize for UI testing: "Timed out while enabling automation mode."
```

That is not a code bug. macOS XCUITest needs the host process to hold **Accessibility** permission:
**System Settings → Privacy & Security → Accessibility**, add the terminal you run from (and
Xcode). iOS/iPad simulators need nothing. Ask the owner — it is their machine, and the run takes
over their screen.

---

## 10. Look at the frames. This is where the worst bugs are.

Assertions cannot see layout. Capture and *look*:

```bash
./make_sim_shots.sh en            # phone
PLATFORM=ipad ./make_sim_shots.sh en
./make_mac_shots.sh
```

**Per-platform frame validators are NOT interchangeable.** Each app's script checks the pixels
before keeping a frame, and the check depends on the app's palette *and platform*:

| | assertion | why |
|---|---|---|
| dark app (overtonelab) | `mean < 90` | near-black studio UI |
| light app (storypole) iOS/macOS | `mean > 150` | warm paper |
| **same light app on watchOS** | `mean < 120` | watchOS resolves `Color(light:dark:)` to the **dark** set |

Copying one into another rejects every good frame and passes a black one.

**For reels, tile and look** — the README in `marketing/reels/` says so and it is right:

```bash
ffmpeg -i store_preview_*.mp4 -vf "fps=1/2,scale=160:-1,tile=7x2" -frames:v 1 tile.png
```

Two things only tiling finds:
1. **Caption drift.** A scene's `src` window taken from its marker starts during the *navigation*,
   so the caption sits over the previous screen. Push each window past its own navigation.
2. **Windows are per-capture and cannot be shared between platforms.** The iPad walkthrough ran
   65.3 s where the iPhone ran 59.7 s, with entirely different boundaries. Re-cut each from its own
   `.build/reel-dd/scenes.runtime.json`.

---

## 11. Definition of done

- [ ] All Kits `swift test` green — still the real gate.
- [ ] `xcodebuild build` green on every platform the app ships.
- [ ] UI tests green on an **iPhone sim and an iPad sim** (macOS too, once permission is granted).
- [ ] Every input and result has an `accessibilityIdentifier`; none is shadowed by a container, and
      every `.combine` either names its combined element or is a `.contain` (§3 Traps 1, 4, 5).
- [ ] No test reads `.label` directly — all text goes through the `text` / `textMatches` helpers (§3
      Trap 3). Grep for it: `grep -n '\.label' *UITests/*.swift` should return only comments.
- [ ] Every feature has one numeric check; a coverage guard asserts the list is complete.
- [ ] A deep-link test proves `<APP>_TAB` works in **both** layouts.
- [ ] If the app has a watch target: crown focus verified on a real wrist.
- [ ] **Someone has looked at rendered frames and a tiled reel.**
- [ ] Nothing was run against the owner's physical devices.

---

## 11a. Making the suite fast — measured, not guessed

Storypole's 38 UI tests took **441 s on macOS**. Profile before optimising: the per-test seconds are
already in the log.

```bash
grep -E "^Test Case .* passed \(" test.log \
  | sed -E "s/.*\[[A-Za-z]+\.([A-Za-z]+) ([A-Za-z]+)\]' passed \(([0-9.]+) seconds\)/\3s  \1.\2/" \
  | sort -rn | head -12
```

**The two costs, measured on this repo:**

| | Cost | Note |
|---|---|---|
| `app.launch()` | **2.4 s** (macOS) / **4 s** (iOS sim) | per launch, unavoidable |
| any interaction — `tap()`, a query, `waitForExistence` on a present element | **~1.1 s** | XCUITest re-snapshots the AX tree and waits for idle before every event |

Everything else is noise: the sum of the test bodies *was* the whole run — 441 s of 441 s. There is
no harness overhead to trim, and there were no `sleep`s.

**What did NOT work — do not repeat it.** Hypothesis: the keypad's press spring (0.18 s) was being
charged to every tap via XCUITest's idle wait, so gating animations behind a `<APP>_UITEST=1` flag
should help. Implemented, measured: **65.9 s → 65.5 s.** Nothing. The ~1.1 s is the snapshot
handshake, an order of magnitude bigger than any animation. The change was reverted. If you find
yourself about to disable animations for speed, this was already tried.

**Also measured and NOT the cause** (so nobody re-runs these): scroll-into-view helpers, macOS
window-state restoration (`-ApplePersistenceIgnoreState`), and `scroll(byDeltaX:deltaY:)` direction.
All were chased against a failure that turned out to be a hard-coded element type (§3 Trap 2).

**What actually works, in order of leverage:**

1. **Move combinatorial coverage to a model test** (§4a). `testEveryDenominatorSurvives` costs 66 s
   for six denominators through the keypad; the same six against the model are milliseconds — and
   you can afford all 64 instead of 6. **This is the only lever that changes the order of
   magnitude.**
2. **Navigate, don't relaunch.** `testEveryToolOpens` calls `launch()` 16 times = 63 s. One launch
   plus 16 in-app navigations is ~20 s for the same coverage.
3. **Parallelise — but split the classes first.** `-parallel-testing-enabled YES` shards by test
   **class**, not by method, so two big classes give you 2 workers and no more. Split by screen and
   the same flag gives real speedup. iOS Simulator only: it clones sims. On macOS, parallel UI tests
   put multiple instances of a single-instance app in a focus fight — flaky, don't.
4. **Targeted re-runs in the fix loop** (§1). Not a speedup of the suite, but the thing that
   actually gets your minutes back day to day.

Do **not** shorten `waitForExistence` timeouts to go faster — they cost nothing when the element is
present and only pay out when something is genuinely wrong. A short timeout buys no speed and
trades it for flakiness.

---

## 12. The full catch list — what to audit other apps for

Everything below is real, from one app in one pass. Use it as the checklist.

| Found by | Bug |
|---|---|
| **Frames** | A **deep link landed on the wrong screen** at regular width, producing a screenshot of the calculator captioned "Every number has a source". The most dangerous find. |
| Frames | A card **clipped behind iOS 26's floating tab bar** (it overlays scroll content). |
| Frames | Mac **sidebar truncating half its tool names** — no `navigationSplitViewColumnWidth` floor. |
| Frames | Two labels rendering as `1112` because an out-of-range label was **clamped instead of dropped**. |
| Frames | Hero store shot showing `0` — fixed with `<APP>_DEMO=1`. |
| Tiled reel | **Caption drift**, twice: `src` windows starting during navigation, and iPhone windows reused for iPad. |
| UI test | Typing a fraction finer than the display precision **silently discarded it** (`5" 1/32` at 1/16 → `5"`; a 1/32 is exactly half a sixteenth, so round-half-to-even sent it to zero). |
| UI test | Container `accessibilityIdentifier` **overwrote six children's**. |
| UI test | Comma-decimal locale rendering `152,11` in a US-market app. |
| **macOS run** | `.accessibilityElement(children: .combine)` **destroyed the readout's identifier** — macOS published the card as `calc.readout-calc.decimal`, so `calc.readout` did not exist and the app's primary number was unaddressable by tests *and* VoiceOver. Green on iOS throughout. (§3 Trap 4) |
| macOS run | A plain `Text` has an **empty `label`** on macOS; the string is in `value`. Every assertion reading `.label` compared against `""`, and the failure messages printed nothing — they read like an empty screen. (§3 Trap 3) |
| macOS run | `accessibilityIdentifier` on a **bare container** is a silent no-op on macOS — three caveat blocks (`bf.caution`, `awg.caveat`, `oc.provenance`) were unreachable. (§3 Trap 5) |
| macOS run | A `.combine`d element is a **group, not a `staticText`** — `app.staticTexts["bf.total"]` failed where `any(app,"bf.total")` passed. |
| **Nobody** | A watchOS **measurement-unit toggle that did nothing.** Every number right, every screen green — no test ever flipped it. Toggles are tested in their default state or not at all. (§4a) |
| Model bug | An **accumulator not reset between operations**: `10' × 8' =` then `× 4"` computed an area twice. Chained-operator paths are where calculators actually break. (§4a) |
| macOS run | `app.otherElements["<id>"]` for a card that macOS publishes as a `StaticText` — passed on iOS, failed on macOS, and the message read like a rendering bug. Five wrong fixes before a dump. (§3 Trap 2) |
| Release audit | Six `<APP>_*` **launch overrides shipping in the Release binary** — deep links, demo seeding, locale pinning. An app whose navigation is drivable with `open --env`. (§4b) |
| Device only | **watchOS Buttons stealing Digital Crown focus** — crown dead, actions re-applying a stale value. |
| Build | Watch target naming an `AccentColor` it compiles no asset catalog for — a warning on every build. |
| Test bug | `press(forDuration:thenDragTo:)` given a coordinate instead of an element (never compiled). |
| Test bug | Guessing `otherElements` for cards SwiftUI exposes differently. |
| Test bug | `build-for-testing` "succeeding" against a scheme with no test action. |
| Test bug | `UDID=$(… | grep …)` under `set -euo pipefail` aborting the script when the sim does not exist yet — exactly the first-run path. |
