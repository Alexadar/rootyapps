import SwiftUI

/// Persisted favourite calculators (offline, no account). Ids are `Calculator.rawValue`.
/// Inject once: `@StateObject private var favorites = FavoritesStore()`.
@MainActor
final class FavoritesStore: ObservableObject {
    @AppStorage("tc.favorites") private var stored: String = "windTriangle,weightBalance"

    private var ids: [String] {
        stored.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    func isFavorite(_ calc: Calculator) -> Bool { ids.contains(calc.rawValue) }

    func toggle(_ calc: Calculator) {
        objectWillChange.send()
        var s = ids
        if let i = s.firstIndex(of: calc.rawValue) { s.remove(at: i) }
        else { s.append(calc.rawValue) }
        stored = s.joined(separator: ",")
    }

    /// Favourited calculators, in the order they were starred.
    var favoriteCalculators: [Calculator] { ids.compactMap(Calculator.init(rawValue:)) }
}

/// Persisted theme choice (Dark / Night). Bind to a toolbar toggle.
/// Read at the root: `.tcTheme(theme.selected)`.
@MainActor
final class ThemeStore: ObservableObject {
    @AppStorage("tc.theme") private var raw: String = TCTheme.dark.rawValue
    var selected: TCTheme {
        get { TCTheme(rawValue: raw) ?? .dark }
        set { objectWillChange.send(); raw = newValue.rawValue }
    }
    func toggle() { selected = (selected == .dark) ? .night : .dark }
}
