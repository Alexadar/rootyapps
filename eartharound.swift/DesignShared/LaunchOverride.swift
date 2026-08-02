import Foundation
import SpaceWeatherFeed

/// Launch-time overrides used by the UI tests and by the marketing capture scripts.
///
/// ## Debug builds only — a shipped app has no env-var back door
///
/// The app reads a handful of environment variables so a test can pin state, and so a screenshot can
/// be taken of a screen holding a plausible reading instead of an empty one:
///
/// | variable | used by |
/// |---|---|
/// | `EARTHAROUND_TAB` | tests and capture — open Dashboard or Geomagnetic at launch |
/// | `EARTHAROUND_THEME` | capture — pin dark/night so a previous run's choice cannot leak in |
/// | `EARTHAROUND_DEMO` | capture only — the 27 s self-driving tour |
/// | `EARTHAROUND_WATCH_PAGE` | tests and capture — land a watch page 0…2 |
/// | `EARTHAROUND_LANG` | tests — pin the language, because `Fmt` follows it |
/// | `EARTHAROUND_FIXTURE` | tests — seed a known snapshot instead of live NOAA data |
///
/// Every one is scaffolding and none belongs in a build a customer runs: a Release app that honours
/// `EARTHAROUND_TAB` is an app whose navigation can be driven from outside it, and on macOS anyone
/// can do that with `open --env`. So the lookup itself is compiled out — under `#if !DEBUG` this
/// returns `nil` unconditionally and the variable names are not even present in the binary.
///
/// Before this existed there was no `#if DEBUG` anywhere in the repository, and both accessors
/// (`DemoDriver.env`, `WatchDemo.env`) read the environment in Release too.
///
/// Capture and tests both run Debug builds, so nothing in the media pipeline is affected. **If a
/// script ever needs one of these against a Release build, that is the bug** — fix the script.
public enum LaunchOverride {

    /// The value of a launch override, or `nil` in a Release build.
    public static func value(_ key: String) -> String? {
#if DEBUG
        ProcessInfo.processInfo.environment[key]
#else
        nil
#endif
    }

    /// Whether a launch override is set to `1`. Always `false` in a Release build.
    public static func flag(_ key: String) -> Bool { value(key) == "1" }

    // MARK: - Test fixture

    /// Seed the app group with a known snapshot and suppress network refresh.
    ///
    /// eartharound is not a calculator: every number on screen comes from live NOAA/GFZ feeds, so a
    /// UI test asserting "Kp 5.3" would be asserting today's weather — wrong tomorrow, and flaky
    /// whenever a feed is slow. With `EARTHAROUND_FIXTURE=1` the store paints from this fixed
    /// snapshot instead (`SpaceWeatherStore` is already cache-first), which makes a numeric
    /// assertion a test of WIRING: does this value reach that label.
    ///
    /// Values match `SpaceWeatherEntry.placeholder`, which the widget already used for its
    /// gallery preview, so there is one set of fixture numbers rather than two.
    @discardableResult
    public static func installFixtureIfRequested() -> Bool {
        guard flag("EARTHAROUND_FIXTURE") else { return false }
        SharedStore().save(SpaceWeatherSnapshot.uiTestFixture, at: Date())
        return true
    }

    /// True when the fixture is active, so the store can skip fetching over it.
    public static var fixtureActive: Bool { flag("EARTHAROUND_FIXTURE") }
}
