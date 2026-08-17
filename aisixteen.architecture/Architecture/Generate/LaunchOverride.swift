import Foundation

/// The ONE place this app reads the environment.
///
/// `uitests.md` §4b: every launch override goes through one accessor that compiles out of Release,
/// and `grep -rn "ProcessInfo.processInfo.environment" Architecture/` must return only this file.
/// There is a unit test that runs exactly that grep, because `strings | grep` and `nm -u` both lie
/// about whether a Debug-only branch survived into the binary.
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

    // ── the keys ─────────────────────────────────────────────────────────────────────────────

    /// Which generator to run. See `GeneratorFactory`.
    static let generator = "ARCH_GENERATOR"
    /// Seed a stale checkpoint on disk, to exercise the rejection path.
    static let checkpoint = "ARCH_CHECKPOINT"
    /// Force the storage location: `off` uses the local fallback, `ghost` fakes a not-yet-downloaded
    /// project.
    static let storage = "ARCH_ICLOUD"
    /// Force an accessibility mode: `rt` Reduce Transparency, `rm` Reduce Motion, `ax5` Dynamic Type.
    static let accessibility = "ARCH_AX"
    /// Open straight onto a screen, so a UI test does not pay for four navigations.
    static let screen = "ARCH_SCREEN"
    /// Seed the library with fixture projects rather than whatever is on the device.
    static let library = "ARCH_LIBRARY"
    /// Pin the language, belt and braces against a simulator that booted into another region.
    static let language = "ARCH_LANG"
}
