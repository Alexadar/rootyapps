import XCTest

/// Shared launch helper. Every test goes through this.
///
/// - `EARTHAROUND_FIXTURE=1` seeds a deterministic snapshot. Without it these tests would be
///   asserting today's space weather: right this afternoon, wrong tomorrow, flaky whenever NOAA is
///   slow. See `SpaceWeatherSnapshot.uiTestFixture`.
/// - `EARTHAROUND_LANG=en` pins the language. `Fmt` formats from the APP GROUP, not
///   `Locale.current`, so a previous capture in German leaves German numbers behind and
///   `-AppleLanguages` cannot correct it. Every number here would then read "5,3".
/// - `EARTHAROUND_DEMO` is deliberately NEVER set: it swaps Liquid Glass for an opaque bar and
///   starts a 27-second tour that mutates tab and theme underneath the test.
func launchApp(tab: String? = nil, fixture: Bool = true) -> XCUIApplication {
    let app = XCUIApplication()
    if fixture { app.launchEnvironment["EARTHAROUND_FIXTURE"] = "1" }
    app.launchEnvironment["EARTHAROUND_LANG"] = "en"
    if let tab { app.launchEnvironment["EARTHAROUND_TAB"] = tab }
    app.launch()
    return app
}
