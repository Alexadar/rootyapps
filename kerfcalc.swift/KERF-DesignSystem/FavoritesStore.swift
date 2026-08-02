import SwiftUI

/// Persisted favourite tools (offline, no account). Ids are `Tool.rawValue`.
/// Inject once: `@StateObject private var favorites = FavoritesStore()`.
@MainActor
final class FavoritesStore: ObservableObject {
    @AppStorage("kerf.favorites") private var stored: String = "rafter,concrete,stairs"

    private var ids: [String] {
        stored.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    func isFavorite(_ tool: Tool) -> Bool { ids.contains(tool.rawValue) }

    func toggle(_ tool: Tool) {
        objectWillChange.send()
        var s = ids
        if let i = s.firstIndex(of: tool.rawValue) { s.remove(at: i) }
        else { s.append(tool.rawValue) }
        stored = s.joined(separator: ",")
    }

    /// Favourited tools, in the order they were starred.
    var favoriteTools: [Tool] { ids.compactMap(Tool.init(rawValue:)) }
}
