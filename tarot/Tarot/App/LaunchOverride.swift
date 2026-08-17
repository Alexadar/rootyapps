import Foundation

/// The ONE door debug input comes through (the monorepo's standing pattern — storypole,
/// marinenav, aircore and the rest each have this file). The invariant it exists to make
/// checkable:
///
///     grep -rn "ProcessInfo.processInfo" Tarot/     →  this file, and nothing else
///
/// A test pins that. The reason is not tidiness: a launch hook read inline somewhere in the
/// app is a hook nobody can prove is absent from a Release build, and this app's debug hooks
/// now include one that forces the cards and supplies pre-written text. Every accessor here
/// returns nothing at all in Release, so the call sites can stay honest without `#if` walls
/// scattered through them.
///
/// Three delivery channels, because the tools use different ones:
///   • `present(_:)`  — a bare `-FLAG` argument (`app.launchArguments`, `open -n --args`)
///   • `argument(_:)` — `-KEY value` pairs, which land in UserDefaults' NSArgumentDomain
///   • `value(_:)`    — the environment (`SIMCTL_CHILD_*`, `TEST_RUNNER_*`, xcodebuild env)
enum LaunchOverride {

    /// A bare flag: `-TAROT_AUTOPILOT`.
    static func present(_ flag: String) -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains(flag)
        #else
        return false
        #endif
    }

    /// A `-KEY value` pair. Foundation parses these into the argument domain, so no manual
    /// scanning is needed — and the same key works from an XCUITest, `simctl launch`, and
    /// `open -n --args`.
    static func argument(_ key: String) -> String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: key)
        #else
        return nil
        #endif
    }

    /// An environment variable — the channel `simctl launch` uses via `SIMCTL_CHILD_<KEY>`
    /// and xcodebuild uses via `TEST_RUNNER_<KEY>`.
    static func value(_ key: String) -> String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment[key]
        #else
        return nil
        #endif
    }

    /// An environment variable set to "1".
    static func flag(_ key: String) -> Bool {
        value(key) == "1"
    }
}
