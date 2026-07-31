import Foundation

/// The single door for every launch-environment override in the app.
///
/// Deep links (`OVERTONELAB_TOOL`, `OVERTONELAB_SCREEN`), the reel's demo animation
/// (`OVERTONELAB_DEMO`) and the capture language pin (`OVERTONELAB_LANG`) are scaffolding for tests,
/// screenshots and reels. None of it belongs in a build a customer runs: a Release app that honours
/// `OVERTONELAB_TOOL` can have its navigation driven from outside the app, and on macOS anyone can do
/// that with a single `open --env`.
///
/// So every read goes through here and returns `nil` in Release. Both the capture scripts
/// (`make_sim_shots.sh`, `make_mac_shots.sh`, the reel pipeline) and `xcodebuild test` use Debug
/// builds, so nothing in the media pipeline loses its hooks.
///
/// Verify the gate with the compilation condition, never with `strings` or `nm`:
///
///     for cfg in Debug Release; do
///       xcodebuild -showBuildSettings -scheme overtonelab.swift -configuration $cfg \
///         | grep -m1 SWIFT_ACTIVE_COMPILATION_CONDITIONS
///     done
///
/// `strings` cannot see these key names because Swift stores strings of ≤15 UTF-8 bytes inline in the
/// String struct — they are immediates, not literals — and `nm` on a Debug binary reads a small loader
/// stub, because a Debug build is split and the code lives in the `.debug.dylib`. Both return
/// clean-looking false negatives.
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
