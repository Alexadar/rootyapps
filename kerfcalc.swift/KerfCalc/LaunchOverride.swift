import Foundation

/// Launch-time overrides used by the UI tests and by the marketing capture scripts.
///
/// ## Debug builds only — a shipped app has no env-var back door
///
/// The app reads a handful of environment variables so a test can deep-link to a tool, and so a
/// screenshot can be taken of a screen holding a real calculation instead of `0"`:
///
/// | variable | used by |
/// |---|---|
/// | `KERFCALC_TOOL`, `KERFCALC_TAB` | UI tests and capture — open a named screen at launch |
/// | `KERFCALC_SCREEN` | capture — pick a tool's sub-screen (the `SubScreenPicker` index) |
/// | `KERFCALC_DEMO` | capture — self-play a calculation so the reel shows the app working |
/// | `KERFCALC_WIN` | capture — fix the macOS window at exactly 16:9 |
///
/// Every one of them is scaffolding, and none has any business in a build a customer runs: a Release
/// app that honours `KERFCALC_TOOL` is a shipped app whose navigation can be driven from outside it,
/// and on macOS anyone can set that with `open --env`. So the lookup itself is compiled out — under
/// `#if !DEBUG` this returns `nil` unconditionally and the variable names are not even present in the
/// binary.
///
/// Capture and tests both run Debug builds, so nothing in the pipeline is affected. **If a script ever
/// needs one of these against a Release build, that is the bug** — fix the script, do not widen this.
///
/// Verify the gate with the compilation condition, never with `strings` or `nm`:
/// ```
/// xcodebuild -showBuildSettings -scheme kerfcalc.swift -configuration Release \
///   | grep -m1 SWIFT_ACTIVE_COMPILATION_CONDITIONS      # must not contain DEBUG
/// ```
/// `strings` cannot see these names because Swift stores strings ≤15 UTF-8 bytes inline in the String
/// struct, so they are immediates and never literals; and `nm` on a Debug binary reads a ~200 KB
/// loader stub, because a Debug build is a dylib split with the code in `<App>.debug.dylib`.
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

    /// Whether a launch override equals `expected`. Always `false` in a Release build.
    public static func matches(_ key: String, _ expected: String) -> Bool { value(key) == expected }
}
