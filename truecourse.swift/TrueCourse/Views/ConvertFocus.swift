import Foundation

/// The Convert screen's crown-focus policy, factored out of the SwiftUI view so the load-bearing
/// rule is unit-testable off the wrist (watchOS ships no XCUITest — the repo convention is
/// install-and-look, but the *policy* is plain model logic and belongs under test).
///
/// **The rule (the regression this guards):** the Digital Crown drives exactly one control at a
/// time, and the target changes ONLY when the user taps a control — `focus(_:)`. The crown-driven
/// setters (`setCategory` / `setUnit` / `setValue`) mutate their value but MUST NEVER move `field`.
/// The previous version called `crownFocus.reclaim()` inside the pickers' `.onChange`, which fired
/// on every crown tick and yanked focus back to the value field after a single step.
///
/// The watch view mirrors `field` into a SwiftUI `@FocusState`; this type carries no SwiftUI or
/// watchOS dependency, so it also compiles into the iOS app module and is exercised by
/// `truecourseModelTests`.
enum ConvertField: Hashable, CaseIterable { case category, unit, value }

@MainActor
final class ConvertFocus: ObservableObject {
    /// Which control the crown drives. Moves only via `focus(_:)` (a tap).
    @Published private(set) var field: ConvertField = .value
    @Published var catIdx: Int = 0
    @Published var unitIdx: Int = 0
    @Published var value: Double = 100

    init() {}

    /// The ONLY thing that moves the crown between controls — an explicit user tap.
    func focus(_ f: ConvertField) { field = f }

    /// Crown-driven category change: reset the unit (a new category has a different unit set), but
    /// never touch `field`. No-op when the category is unchanged, so idle re-renders don't reset the
    /// unit the user just picked.
    func setCategory(_ i: Int) {
        guard i != catIdx else { return }
        catIdx = i
        unitIdx = 0
    }

    /// Crown-driven unit change; focus untouched.
    func setUnit(_ i: Int) { unitIdx = i }

    /// Crown-driven value change; focus untouched.
    func setValue(_ v: Double) { value = v }
}
