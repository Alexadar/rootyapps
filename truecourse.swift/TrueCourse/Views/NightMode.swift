import SwiftUI

/// Persisted theme choice (Dark / Night). Bind to a toolbar toggle.
/// Read at the root: `.tcTheme(theme.selected)`. The `TCTheme` enum lives in TCColors.swift.
@MainActor
final class ThemeStore: ObservableObject {
    @AppStorage("tc.theme") private var raw: String = TCTheme.dark.rawValue
    var selected: TCTheme {
        get { TCTheme(rawValue: raw) ?? .dark }
        set { objectWillChange.send(); raw = newValue.rawValue }
    }
    func toggle() { selected = (selected == .dark) ? .night : .dark }
}
