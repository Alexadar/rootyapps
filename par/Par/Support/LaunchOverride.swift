import Foundation

/// The one place the app reads launch-time overrides — and only in a build that is not shipped.
///
/// `PAR_TOOL`, `PAR_TAPE` and `PAR_TAPE_SEED` are scaffolding for the screenshot pipeline, the reel
/// recording and the UI tests. None of it belongs in a build a customer runs: a Release app that
/// honours `PAR_TOOL` can have its navigation driven from outside, and on macOS anyone can do exactly
/// that with `open --env PAR_TOOL=bond`. `PAR_TAPE_SEED` is worse — it would let a stranger's process
/// decide whether the app opens showing four fabricated loan rows.
///
/// Gating on `#if DEBUG` costs the pipeline nothing, because both capture scripts build the `Capture`
/// configuration and `project.yml` defines it as `Capture: debug` with
/// `SWIFT_ACTIVE_COMPILATION_CONDITIONS: "DEBUG PAR_CAPTURE"`. Release alone loses the hooks.
///
/// Verify with the compilation condition, never with `strings` or `nm` — both return clean-looking
/// false negatives here. `strings` cannot see these names because Swift stores strings of 15 UTF-8
/// bytes or fewer inline in the `String` struct, so they are immediates rather than literals; and `nm`
/// on a Debug binary reads a small loader stub, since a Debug build is split and the code lives in
/// `Par.debug.dylib`.
///
///     for cfg in Debug Release Capture; do
///       xcodebuild -showBuildSettings -scheme Par -configuration $cfg \
///         | grep -m1 SWIFT_ACTIVE_COMPILATION_CONDITIONS
///     done
///     # Debug -> DEBUG    Release -> (empty)    Capture -> DEBUG PAR_CAPTURE
public enum LaunchOverride {

    /// The value of a launch override, or nil in a shipping build.
    public static func value(_ key: String) -> String? {
        #if DEBUG
        ProcessInfo.processInfo.environment[key]
        #else
        nil
        #endif
    }

    /// True only when the override is explicitly "1", and only in a non-shipping build.
    public static func flag(_ key: String) -> Bool { value(key) == "1" }

    /// True unless the override is explicitly "0" — for a default-on switch like the seeded tape.
    public static func isNotDisabled(_ key: String) -> Bool { value(key) != "0" }
}
