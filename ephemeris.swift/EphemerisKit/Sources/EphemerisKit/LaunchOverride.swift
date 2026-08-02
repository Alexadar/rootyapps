import Foundation

/// The one place any `EPHEMERIS_*` launch override is read — and the gate that keeps them out of
/// shipping builds.
///
/// Deep links, demo seeding, the pinned instant and locale pinning are all test and capture
/// scaffolding. None of it belongs in a build a customer runs: a Release app that honours
/// `EPHEMERIS_TAB` can have its navigation driven from outside the app, and on macOS anyone can do
/// that with `open --env`. `#if DEBUG` makes every one of them return nil in Release.
///
/// It lives in the Kit rather than the app target because three processes read these keys — the app,
/// the watch app and the widget extension. A per-target copy is how `ChartGeometry` came to have two
/// definitions that silently disagreed about which way the zodiac turns.
///
/// Capture and tests both use Debug builds, so gating breaks nothing in the media pipeline
/// (`grep "configuration Release" marketing/*.sh` finds nothing).
///
/// Do not verify the gating with `strings` or `nm` — both return clean-looking false results. Swift
/// stores strings of 15 UTF-8 bytes or fewer inline in the String struct, so these key names are
/// immediates rather than literals and never appear in the string table; and `nm` on a Debug binary
/// reads a ~200 KB loader stub, because Debug builds are a dylib split with the code in
/// `<App>.debug.dylib`. Check `SWIFT_ACTIVE_COMPILATION_CONDITIONS` per configuration instead.
public enum LaunchOverride {

    /// The raw value for `key`, or nil in a Release build.
    public static func value(_ key: String) -> String? {
#if DEBUG
        let raw = ProcessInfo.processInfo.environment[key]
        return (raw?.isEmpty ?? true) ? nil : raw
#else
        nil
#endif
    }

    /// True only when `key` is explicitly `"1"`. Absent, empty or anything else is false.
    public static func flag(_ key: String) -> Bool { value(key) == "1" }

    public static func int(_ key: String) -> Int? { value(key).flatMap(Int.init) }

    public static func double(_ key: String) -> Double? { value(key).flatMap(Double.init) }

    /// The instant the app should treat as "now", when a test pins it.
    ///
    /// Every screen here renders the live sky, so a UI test asserting a planet's position has no
    /// stable expected value unless the clock is pinned. Accepts a full ISO-8601 timestamp
    /// (`2026-03-20T12:00:00Z`); returns nil if unset or unparseable, so a typo falls back to the
    /// real clock rather than to a silently wrong date.
    public static func pinnedDate(_ key: String = "EPHEMERIS_DATE") -> Date? {
        guard let raw = value(key) else { return nil }
        return ISO8601DateFormatter().date(from: raw)
    }
}
