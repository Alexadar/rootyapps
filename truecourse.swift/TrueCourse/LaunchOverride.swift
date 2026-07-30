import Foundation

/// Launch-time overrides used by the UI tests and the marketing capture scripts — and compiled out
/// of any build a customer runs.
///
/// The app reads a few environment variables so a test can deep-link to a tool/sub-screen and so a
/// screenshot/reel can open on a screen holding a real calculation:
///
/// | variable | used by |
/// |---|---|
/// | `TRUECOURSE_TOOL`, `TRUECOURSE_SCREEN` | UI tests + capture — open a named tool/sub-screen at launch |
/// | `TRUECOURSE_DEMO` | capture — auto-sweep animation for the reel |
/// | `TRUECOURSE_LANG` | UI tests — reserved locale pin (the real pin is the sim's `AppleLocale`) |
///
/// None of it belongs in a shipped build: a Release app that honours `TRUECOURSE_TOOL` is a shipped
/// app whose navigation can be driven from outside — and on macOS anyone can do that with
/// `open --env`. So the lookup is compiled out: under `#if !DEBUG` this returns `nil`
/// unconditionally and the variable names are not even present in the binary. Capture and tests both
/// run Debug builds, so nothing in the pipeline is affected — if a script ever needs one of these
/// against a Release build, fix the script, don't widen this.
enum LaunchOverride {
    /// The value of a launch override, or `nil` in a Release build.
    static func value(_ key: String) -> String? {
#if DEBUG
        ProcessInfo.processInfo.environment[key]
#else
        nil
#endif
    }

    /// Whether a launch override is present (non-nil). Always `false` in a Release build.
    static func isSet(_ key: String) -> Bool { value(key) != nil }
}
