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
/// | `STORYPOLE_TOOL`, `STORYPOLE_TAB` | UI tests and capture — open a named screen at launch |
/// | `STORYPOLE_DEMO` | capture — seed a representative calculation |
/// | `STORYPOLE_LANG` | UI tests — pin the locale so numbers do not render `152,11` |
/// | `STORYPOLE_WIN` | capture — fix the macOS window at exactly 16:9 |
/// | `STORYPOLE_WATCH_TOOL` | capture — the watch app resumes its last tool otherwise |
///
/// Every one of them is scaffolding, and none has any business in a build a customer runs: a
/// Release app that honours `STORYPOLE_TOOL` is a shipped app whose navigation can be driven from
/// outside it, and on macOS anyone can set that with `open --env`. So the lookup itself is compiled
/// out — under `#if !DEBUG` this returns `nil` unconditionally and the variable names are not even
/// present in the binary.
///
/// Capture and tests both run Debug builds, so nothing in the pipeline is affected. **If a script
/// ever needs one of these against a Release build, that is the bug** — fix the script, do not
/// widen this.
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
}
