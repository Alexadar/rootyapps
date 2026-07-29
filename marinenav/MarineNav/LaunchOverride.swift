import Foundation

/// The single door for launch-time overrides — and it is closed in Release.
///
/// Deep links (`-tool tides`, `-page declination`) and locale pinning are capture and test
/// scaffolding. None of it belongs in a build a customer runs: an app that honours `-tool` can
/// have its navigation driven from outside, and on macOS anyone can do that with
/// `open --args -tool …`. Both hooks previously read `ProcessInfo.processInfo.arguments`
/// unconditionally, so they shipped.
///
/// Every override must route through here, so that
/// `grep -rn "ProcessInfo.processInfo" MarineNav MarineNavWatch` returns this file and nothing else.
///
/// **Verify the gating with the compilation condition, not with `strings` or `nm`** — both return
/// clean-looking FALSE negatives:
///
/// ```
/// for cfg in Debug Release; do
///   xcodebuild -showBuildSettings -scheme marinenav -configuration $cfg \
///     | grep -m1 SWIFT_ACTIVE_COMPILATION_CONDITIONS
/// done
/// ```
///
/// `strings` cannot see these key names because Swift stores strings of 15 UTF-8 bytes or fewer
/// inline in the String struct, so they are immediates rather than literals; and `nm` on a Debug
/// binary reads a small loader stub, because a Debug build is split and the code lives in
/// `Marine Nav.debug.dylib`.
///
/// Capture and tests both build Debug, so the media pipeline is unaffected.
enum LaunchOverride {

    /// The value following `-<key>` in the launch arguments — `nil` in Release.
    static func argument(_ key: String) -> String? {
#if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-\(key)"), i + 1 < args.count else { return nil }
        return args[i + 1]
#else
        return nil
#endif
    }

    /// An environment override — `nil` in Release.
    static func environment(_ key: String) -> String? {
#if DEBUG
        ProcessInfo.processInfo.environment[key]
#else
        nil
#endif
    }
}
