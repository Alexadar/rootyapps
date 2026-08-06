import Foundation

/// Where a field's value came from.
///
/// A new axis across every receiving tool: a number on screen is now either something the user typed
/// or something the app measured, and the difference has to be visible, speakable and reversible.
enum Provenance: Equatable, Codable, Sendable {
    case typed
    case measured(source: String, at: Date)

    var isMeasured: Bool { if case .measured = self { return true }; return false }
}

/// Which field a provenance belongs to.
///
/// Deliberately a string key rather than a property on the ViewModels: `DESIGN_GUIDELINES` §11 says
/// the ViewModels' `@Published` inputs and outputs stay identical, and routing a measured value only
/// *writes* an existing property. Nothing about provenance is allowed to change their surface.
struct FieldKey: Hashable, Codable, Sendable, CustomStringConvertible {
    let tool: String
    let field: String
    init(tool: String, field: String) { self.tool = tool; self.field = field }
    var description: String { "\(tool).\(field)" }
}

/// Provenance for every field that has been handed a measured value, plus the value that was there
/// **before** the handoff.
///
/// ## Two rules this type exists to enforce
///
/// 1. **Revert restores the pre-handoff value, not a default.** Storing only "was measured" would
///    leave revert guessing, and a tool's default is not the number the user had typed.
/// 2. **Editing clears provenance instantly.** There is no "measured but modified" — a value the user
///    changed is theirs, whatever it started as.
///
/// ## Lifetime — RAM for now, document-shaped for later
///
/// Everything here is `Codable` and `persist()`/`restore()` are real entry points, but the only
/// `SessionPersistence` implementation this round is in memory. A background kill loses the session;
/// switching that on is wiring a file-backed implementation, not a rewrite.
@MainActor
final class FieldProvenance: ObservableObject {

    struct Entry: Codable, Equatable, Sendable {
        var provenance: Provenance
        /// What the field held before the measured value landed. `nil` means it was never touched.
        var previousValue: Double?
    }

    @Published private(set) var entries: [FieldKey: Entry] = [:]

    init() {}

    func provenance(for key: FieldKey) -> Provenance { entries[key]?.provenance ?? .typed }
    func isMeasured(_ key: FieldKey) -> Bool { provenance(for: key).isMeasured }

    /// Record that `key` has just been handed a measured value, remembering what it displaced.
    func markMeasured(_ key: FieldKey, replacing previous: Double?, source: String, at: Date) {
        entries[key] = Entry(provenance: .measured(source: source, at: at), previousValue: previous)
    }

    /// The user typed. Provenance goes immediately — including the remembered value, because there is
    /// nothing left to revert to once they have made the field their own.
    func markTyped(_ key: FieldKey) { entries[key] = nil }

    /// The value to restore for *Revert to typed*, or nil if this field was never measured.
    func revertValue(for key: FieldKey) -> Double? { entries[key]?.previousValue }

    /// Revert and forget, in one step, so a caller cannot leave the marking behind.
    func revert(_ key: FieldKey) -> Double? {
        let value = entries[key]?.previousValue
        entries[key] = nil
        return value
    }

    func clearAll() { entries.removeAll() }
}
