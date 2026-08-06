import Foundation

/// The catalog holds tools **and** sources.
///
/// `Tool` is a closed enum where every case implies a Kit and a detail view, so Measure cannot be a
/// case of it — it computes nothing and owns no math. This sibling enum is the one structural change
/// Audio Analysis requires, and it touches the grid and the sidebar only.
enum CatalogEntry: Hashable, Identifiable, Sendable {
    case source(Source)
    case tool(Tool)

    enum Source: String, Hashable, Sendable { case measure }

    var id: String {
        switch self {
        case .source(let s): return "source." + s.rawValue
        case .tool(let t):   return t.rawValue
        }
    }

    /// **A missing array element, never a disabled row.**
    ///
    /// On a released SDK this returns `[]`, so there is no tab, no greyed row, no "coming soon", and
    /// nothing reflows — the catalog is simply the catalog. That is the whole availability strategy:
    /// absent rather than present-and-dead.
    static var sources: [CatalogEntry] {
        AnalysisAvailability.isAvailable ? [.source(.measure)] : []
    }
}

/// Is Audio Analysis available in this build, on this OS?
enum AnalysisAvailability {
    /// True only where the framework exists **or** a launch override asks for it.
    ///
    /// The override is not a convenience: `MusicUnderstanding` is absent from the released SDK, so
    /// without it the entire feature is unreachable and therefore untestable — every provenance path,
    /// every routing row and every screen would ship unexercised. `LaunchOverride` compiles the flag
    /// out of Release builds, so this cannot be switched on by a customer.
    static var isAvailable: Bool {
        if LaunchOverride.flag("OVERTONELAB_MEASURE") { return true }
        #if canImport(MusicUnderstanding)
        if #available(iOS 27, macOS 27, *) { return true }
        #endif
        return false
    }
}
