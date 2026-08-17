import Foundation

/// The single door for every launch-environment override in the app.
///
/// The deep link (`AIRCORE_TOOL`), the state reset the UI suite needs (`AIRCORE_RESET`) and the
/// screenshot seed (`AIRCORE_DEMO`) are scaffolding for tests and capture. None of it belongs in a
/// build a customer runs: a Release app that honours `AIRCORE_TOOL` can have its navigation driven
/// from outside the app, and on macOS anyone can do that with a single `open --env`.
///
/// So every read goes through here and returns `nil` in Release. Tests and the capture scripts use
/// Debug builds, so nothing in the pipeline loses its hooks.
///
/// Verify the gate with the compilation condition, never with `strings` or `nm`:
///
///     for cfg in Debug Release; do
///       xcodebuild -showBuildSettings -scheme aircore -configuration $cfg \
///         | grep -m1 SWIFT_ACTIVE_COMPILATION_CONDITIONS
///     done
///
/// `strings` cannot see these key names — Swift stores strings of ≤15 UTF-8 bytes inline in the
/// String struct, so they are immediates rather than literals — and `nm` on a Debug binary reads a
/// loader stub, because a Debug build is split and the code lives in the `.debug.dylib`. Both
/// return clean-looking false negatives.
public enum LaunchOverride {

    /// The override for `key`, or `nil` in any non-DEBUG build.
    public static func value(_ key: String) -> String? {
#if DEBUG
        ProcessInfo.processInfo.environment[key]
#else
        nil
#endif
    }

    /// True only when `key` is present at all — for switches whose value carries no information.
    public static func isSet(_ key: String) -> Bool { value(key) != nil }

    /// `key` set to "1".
    public static func flag(_ key: String) -> Bool { value(key) == "1" }
}
