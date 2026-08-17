import Foundation

/// DEBUG-only launch-environment accessor — the single test-hook seam. Release builds
/// compile every read to nil, so no hook ships (verify via SWIFT_ACTIVE_COMPILATION_CONDITIONS,
/// not `strings`/`nm` — both lie on Debug dylib splits and inline strings).
enum LaunchOverride {
    static func value(_ key: String) -> String? {
#if DEBUG
        ProcessInfo.processInfo.environment[key]
#else
        nil
#endif
    }
    static func isSet(_ key: String) -> Bool { value(key) != nil }
    static func flag(_ key: String) -> Bool { value(key) == "1" }
}
