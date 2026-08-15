import XCTest

/// Cross-platform element reading, shared by the iOS/macOS suite **and** the watchOS suite.
///
/// One file, listed in both test targets' `sources`. It is deliberately not copied: the same helper
/// existing twice is how `ChartGeometry` ended up with two definitions that disagreed about which
/// way the zodiac turns, and how three renderers each shipped the same font bug.
///
/// ## The trap this exists for
///
/// The same SwiftUI `Text` publishes its string in a DIFFERENT attribute depending on the platform,
/// so an iOS suite can be fully green while macOS fails every assertion that reads a number:
///
/// | element | iOS | macOS |
/// |---|---|---|
/// | plain `Text` leaf | `label` = "6° 25′" | `label` = **""**, `value` = "6° 25′" |
/// | `.accessibilityElement(children: .combine)` | `label` = combined | `label` = combined |
///
/// So `.label` works on macOS *only* for combined elements. Every test reading a plain `Text` would
/// compare against `""` and fail printing nothing — which reads like "the screen never loaded" and
/// sends you hunting a navigation bug that does not exist.
///
/// Always read through `text`, match with `textMatches`, and query with `any`.
extension XCUIElement {

    /// The string a user would read, whichever attribute this platform chose to put it in.
    var text: String {
        let l = label
        if !l.isEmpty { return l }
        return (value as? String) ?? ""
    }
}

/// A predicate matching `needle` in EITHER attribute.
///
/// `NSPredicate(format: "label CONTAINS[c] %@")` silently matches nothing on macOS for plain text.
func textMatches(_ needle: String) -> NSPredicate {
    NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", needle, needle)
}

/// An element by identifier, whatever TYPE SwiftUI published it as.
///
/// Never write `app.staticTexts["x"]` or `app.otherElements["x"]`. The type changes with modifiers
/// **and** across platforms — a `.combine`d card is a `staticText` on iOS and a `group` on macOS —
/// and `app.otherElements["x"]` passing on iOS while failing on macOS is the single most expensive
/// trap here, because the failure is indistinguishable from a real rendering bug.
func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: id).firstMatch
}

/// Every element currently published under `id` — for counting rows.
func allMatching(_ app: XCUIApplication, _ id: String) -> XCUIElementQuery {
    app.descendants(matching: .any).matching(identifier: id)
}

/// An option inside an open `Picker`/`Menu`, by its visible title.
///
/// Two traps meet here, and the first attempt hit both. `app.descendants(matching: .any)` with a
/// CONTAINS predicate walks the entire tree, which on macOS took **127 seconds** and then failed
/// with "Failed to get matching snapshots: Timed out while evaluating UI query" — a message that
/// says nothing about the real problem. And a `.menu`-style Picker on macOS opens an **NSMenu**,
/// whose items are not in the app's normal view hierarchy at all; they are `menuItems`, while on iOS
/// the same options are `buttons`.
///
/// So this asks the two cheap, specific questions instead of one expensive general one. It is the
/// deliberate exception to "never assume the element type": the type difference *is* the thing being
/// handled, and both possibilities are tried rather than assumed.
func menuOption(_ app: XCUIApplication, _ title: String) -> XCUIElement {
    let item = app.menuItems[title]
    if item.waitForExistence(timeout: 5) { return item }
    let button = app.buttons[title]
    if button.waitForExistence(timeout: 5) { return button }
    return item   // return the macOS-shaped one so a failure message names something real
}

/// A segment inside a segmented `Picker`, by its visible title, scoped to the control.
///
/// Scoped on purpose. A whole-tree `descendants(matching: .any)` with a CONTAINS predicate is the
/// query that took **127 seconds** and then failed with "Timed out while evaluating UI query"; used
/// for lens switching it cost ~115s per test across five tests before this existed.
///
/// Measured from `app.debugDescription` on macOS: a segmented Picker publishes a `RadioGroup`
/// carrying the identifier, whose children are `RadioButton`s labelled with the segment title. iOS
/// publishes them as `buttons`. Both are tried rather than assumed — the type difference IS the
/// thing being handled.
func segment(_ app: XCUIApplication, in group: String, titled title: String) -> XCUIElement {
    let control = any(app, group)
    let radio = control.radioButtons[title]
    if radio.waitForExistence(timeout: 5) { return radio }
    let button = control.buttons[title]
    if button.waitForExistence(timeout: 5) { return button }
    return radio   // return the macOS-shaped one so a failure names something real
}

// MARK: - Launch

/// The instant every assertion in this suite is written against.
///
/// The app renders the live sky, so a numeric assertion needs the clock pinned or its expected value
/// changes every second. Read by `LaunchOverride.pinnedDate()`, which is DEBUG-only.
///
/// `2026-07-15T12:00:00Z`, chosen by scanning candidates rather than by hand: every body sits at
/// least **3°19′ clear of a sign boundary** and 17 aspects are in orb, so the Aspects tab has
/// something to assert.
///
/// The first choice — the March equinox — was a trap twice over. It left the Sun 6 arcminutes from
/// the Pisces/Aries edge, and it had zero aspects. Worse, when this constant was briefly out of sync
/// with the expected values, that knife-edge turned a 22-arcminute offset into an apparent
/// *whole-sign* change (29°54′ Pisces vs 0°16′ Aries) — which reads like a chart-rendering bug
/// instead of the wrong input date it actually was.
let pinnedInstant = "2026-07-15T12:00:00Z"

/// Los Angeles — matches the `en` capture place, so houses and angles are defined and stable.
let pinnedLatitude = "34.052"
let pinnedLongitude = "-118.244"

extension XCUIApplication {

    /// A launch with the clock, place, zone and language all pinned.
    ///
    /// Locale is pinned twice on purpose (§C.4): the simulator's `AppleLocale` **and**
    /// `EPHEMERIS_LANG`. A fresh sim can boot in a comma-decimal region, where every formatted
    /// number renders `152,11` and tests fail on the separator rather than the arithmetic.
    @discardableResult
    func launchPinned(tab: Int? = nil, screen: String? = nil,
                      lens: String? = nil) -> XCUIApplication {
        launchEnvironment["EPHEMERIS_DATE"] = pinnedInstant
        // The display zone must equal the DEVICE zone, or the pinned instant is not the instant the
        // chart computes from.
        //
        // `ChartViewModel.instant` deliberately reads `date`'s wall-clock components in the device
        // zone and rebuilds them in the chosen zone — that is what makes "3pm in Tokyo" mean 3pm in
        // Tokyo when you pick a zone. It also means a UTC instant plus a *different* display zone
        // lands somewhere else entirely: with the device on UTC+3 and the display zone on
        // America/Los_Angeles, the effective instant was **10 hours** past the pinned one, which
        // showed up as the Sun sitting 24 arcminutes off and the Ascendant in the wrong place.
        //
        // Reading the runner's own zone keeps this identity on any machine, instead of hard-coding a
        // zone that happens to match one developer's simulator.
        launchEnvironment["EPHEMERIS_TZ"] = TimeZone.current.identifier
        launchEnvironment["EPHEMERIS_LAT"] = pinnedLatitude
        launchEnvironment["EPHEMERIS_LON"] = pinnedLongitude
        launchEnvironment["EPHEMERIS_PLACE"] = "Los Angeles"
        launchEnvironment["EPHEMERIS_LANG"] = "en"
        if let tab { launchEnvironment["EPHEMERIS_TAB"] = String(tab) }
        if let screen { launchEnvironment["EPHEMERIS_SCREEN"] = screen }
        // Houses is a LENS now, not a tab, so it is unreachable by tab index alone.
        if let lens { launchEnvironment["EPHEMERIS_LENS"] = lens }

        // Pin every PERSISTED preference that changes a number on screen.
        //
        // Without this the suite is order-dependent: the house-system test switches to Whole Sign,
        // that choice is written to UserDefaults, and the *next* test then reads a 1st cusp of
        // 0° 00′ instead of the Ascendant — a failure that looks like a houses bug and moves
        // depending on which test ran first.
        //
        // `-key value` launch arguments land in the NSArgumentDomain, which outranks the persisted
        // domain for that launch only. So this needs no app code, leaves no residue on the
        // simulator, and cannot be defeated by whatever a previous test saved.
        launchArguments += [
            "-houseSystem", "placidus",
            "-dateStepSeconds", "86400",
        ]
        launch()
        return self
    }
}
