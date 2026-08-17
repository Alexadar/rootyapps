import Foundation

/// Where an enhancement applies.
///
/// Board `1i`. Four scopes, and each one holds **its own strength** — background at 55 while the
/// subject stays at 0 is a normal edit, not an edge case.
public enum Scope: String, CaseIterable, Sendable, Codable, Hashable {
    case whole
    case subject
    case background
    case brush

    /// The iPhone label (`1b`), which has room for the long form.
    public var displayName: String {
        switch self {
        case .whole:      return "Whole photo"
        case .subject:    return "Subject"
        case .background: return "Background"
        case .brush:      return "Brush"
        }
    }

    /// The iPad / Mac label (`1g`, `1h`), where the segment sits in a narrower column.
    public var compactDisplayName: String {
        self == .whole ? "Whole" : displayName
    }

    /// True for every scope except `whole`. A scope that needs a mask and has none cannot be
    /// enhanced — the UI must not offer Enhance in that state, and `EditRecipe` will not build a
    /// layer for it.
    public var requiresMask: Bool { self != .whole }

    /// `subject` and `background` are **one mask, read two ways**. Storing them as one file and a
    /// flag is not a space optimisation: it guarantees the two are exact complements, so a pixel
    /// can never be in both or in neither.
    public var invertsMask: Bool { self == .background }

    /// Which stored mask a scope reads. `brush` has its own; `whole` has none.
    public var maskSource: MaskSource? {
        switch self {
        case .whole:                  return nil
        case .subject, .background:   return .segmentation
        case .brush:                  return .brush
        }
    }

    public var accessibilityHint: String {
        switch self {
        case .whole:      return "Enhances the entire photo"
        case .subject:    return "Enhances the subject only, leaving the background alone"
        case .background: return "Enhances the background only, leaving the subject alone"
        case .brush:      return "Enhances only where you paint"
        }
    }
}

/// The two kinds of mask the app can hold for one photo.
public enum MaskSource: String, Sendable, Codable, Hashable, CaseIterable {
    /// Produced on device by Vision. One per photo, shared by `subject` and `background`.
    case segmentation
    /// Painted by finger, Pencil or cursor.
    case brush

    public var filename: String {
        switch self {
        case .segmentation: return "segmentation.png"
        case .brush:        return "brush.png"
        }
    }
}

/// A mask as the recipe records it: which file, and whether this scope reads it inverted.
///
/// Deliberately not the pixels. A recipe is a small, readable, durable description of an edit —
/// it survives being opened next year by a build that renders differently, and it can be inspected
/// in Files by a user who wants to know what the app did to their photo.
public struct MaskRef: Sendable, Codable, Hashable {
    public let source: MaskSource
    public let inverted: Bool

    public init(source: MaskSource, inverted: Bool) {
        self.source = source
        self.inverted = inverted
    }

    public var filename: String { source.filename }

    /// The mask a scope reads, or `nil` for `whole` — which is not "an all-white mask" but the
    /// absence of masking, so the renderer can skip a whole composite pass.
    public static func forScope(_ scope: Scope) -> MaskRef? {
        guard let source = scope.maskSource else { return nil }
        return MaskRef(source: source, inverted: scope.invertsMask)
    }

    /// Two refs are complements when they read the same file in opposite senses. The
    /// subject/background pair must satisfy this, and a test asserts it.
    public func isComplement(of other: MaskRef) -> Bool {
        source == other.source && inverted != other.inverted
    }
}
