import SwiftUI

/// Persisted favourite tools (offline, no account). Ids are `Tool.rawValue`, stored as a CSV string
/// in `UserDefaults`. `ids` is `@Published` so SwiftUI re-renders on toggle; the store is injectable
/// (`defaults:`) so the logic is unit-testable without touching the shared domain.
@MainActor
final class FavoritesStore: ObservableObject {
    static let key = "kerf.favorites"
    static let seed = "rafter,concrete,stairs"

    private let defaults: UserDefaults
    @Published private(set) var ids: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.key) ?? Self.seed
        self.ids = FavoritesStore.parse(stored)
    }

    static func parse(_ csv: String) -> [String] {
        csv.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    func isFavorite(_ tool: Tool) -> Bool { ids.contains(tool.rawValue) }

    func toggle(_ tool: Tool) {
        if let i = ids.firstIndex(of: tool.rawValue) { ids.remove(at: i) } else { ids.append(tool.rawValue) }
        defaults.set(ids.joined(separator: ","), forKey: Self.key)
    }

    /// Favourited tools, in the order they were starred; unknown ids are dropped.
    var favoriteTools: [Tool] { ids.compactMap(Tool.init(rawValue:)) }
}
