import Foundation

/// Launch-argument / environment overrides, used by capture tooling and headless runs.
///
/// Same shape as `storypole/DesignShared/LaunchOverride.swift`. Reading both `-KEY value` launch
/// arguments and the process environment means a simulator run, an `xcodebuild` run and a plain
/// `open -a` can all be driven the same way.
enum LaunchOverride {
    static func value(_ key: String) -> String? {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-\(key)"), i + 1 < args.count {
            return args[i + 1]
        }
        return ProcessInfo.processInfo.environment[key]
    }

    static func flag(_ key: String) -> Bool {
        guard let v = value(key)?.lowercased() else { return false }
        return v == "1" || v == "true" || v == "yes"
    }
}
