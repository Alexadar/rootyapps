import Foundation

/// One scope's state: what the model rendered, and where the dial is now.
///
/// The two numbers are genuinely different things, and collapsing them into one is the mistake this
/// type exists to prevent. `rendered` is history — the strength the pass actually ran at, which for
/// a real diffusion model is a denoise fraction and not an opacity. `strength` is the live dial,
/// which the user can move afterwards without paying for another pass, **downward**.
public struct ScopeEdit: Sendable, Codable, Hashable {

    public let scope: Scope

    /// Where the dial is. Starts at the default and is the value handed to the model when Enhance
    /// is pressed.
    public var strength: Strength

    /// The strength the completed pass ran at. `nil` before any pass, and after a revert.
    public var rendered: Strength?

    public init(scope: Scope, strength: Strength = .default, rendered: Strength? = nil) {
        self.scope = scope
        self.strength = strength
        self.rendered = rendered
    }

    public var mask: MaskRef? { MaskRef.forScope(scope) }

    /// A pass only counts if it ran above zero. A "pass at 0" is not a pass, it is the original.
    public var hasPass: Bool {
        guard let rendered else { return false }
        return !rendered.isZero
    }

    /// Records a completed pass. Rejects zero for the reason above, so a bad caller cannot create
    /// a state where the app believes it has an enhanced image it never rendered.
    public mutating func markRendered(at strength: Strength) {
        guard !strength.isZero else { return }
        rendered = strength
        self.strength = strength
    }

    /// Throws the pass away. The dial keeps its position so pressing Enhance again does the
    /// obvious thing.
    public mutating func revert() {
        rendered = nil
    }

    /// What the screen should do at the current dial position.
    public var outcome: BlendOutcome {
        guard let rendered, !rendered.isZero else { return .original }
        if strength.isZero { return .original }
        if strength > rendered { return .needsRerun(at: strength) }
        return .blend(strength.value / rendered.value)
    }
}

/// What a dial position means, given what was rendered.
public enum BlendOutcome: Sendable, Equatable {
    /// ⚠️ **The original pixels, not a blend at alpha 0.** See `Composite`.
    case original
    /// `0 < fraction <= 1` of the rendered pass.
    case blend(Double)
    /// The dial went above what was rendered. The model has to run again; the UI says so rather
    /// than silently showing the old pass at full strength, which would be a lie about the number
    /// under the user's thumb.
    case needsRerun(at: Strength)

    public var isOriginal: Bool { self == .original }

    public var fraction: Double? {
        if case .blend(let f) = self { return f }
        return nil
    }

    public var requiresRerun: Bool {
        if case .needsRerun = self { return true }
        return false
    }
}

/// What the renderer should put on screen for a whole recipe.
///
/// ### The one trap in this design
///
/// `.original` is a **separate case**, not `.blended` with a zero fraction. At zero the renderer
/// hands back the decoded original image itself; it does not composite the original with anything
/// at alpha 0. Those two are the same picture in theory and not always the same *bytes*: a
/// composite goes through a colour space, a blend and an encode, any of which can move a channel by
/// one. The product promise is "sliding to 0 **is** the original, bit for bit", and a promise about
/// bytes has to be kept by skipping the pipeline, not by trusting it to round well.
public enum Composite: Sendable, Equatable {
    case original
    case blended([Layer])

    /// One scope's contribution, broadest area first.
    public struct Layer: Sendable, Equatable {
        public let scope: Scope
        /// `nil` means the whole frame — the absence of masking, not an all-white mask.
        public let mask: MaskRef?
        /// `0 < fraction <= 1`.
        public let fraction: Double

        public init(scope: Scope, mask: MaskRef?, fraction: Double) {
            self.scope = scope
            self.mask = mask
            self.fraction = fraction
        }
    }

    public var isOriginal: Bool { self == .original }

    public var layers: [Layer] {
        if case .blended(let layers) = self { return layers }
        return []
    }
}

/// The whole edit, as stored beside the photo.
///
/// This — not the enhanced file — is the durable thing. The enhanced copy can always be rebuilt
/// from the original plus this recipe, which is what makes an edit revertible forever.
public struct EditRecipe: Sendable, Codable, Hashable {

    /// The name of the read-only original inside the edit folder, e.g. `original.heic`.
    public let sourceFilename: String
    /// SHA-256 of that file at import. Re-checked on every exit path; if it ever changes, something
    /// wrote to a file that is supposed to be immutable.
    public let sourceDigest: String
    /// Passed to the model so a pass can be reproduced exactly.
    public var seed: UInt32
    public var createdAt: Date
    public var appVersion: String

    /// One entry per scope the user has touched, in the order they were touched.
    public var edits: [ScopeEdit]

    public init(sourceFilename: String,
                sourceDigest: String,
                seed: UInt32,
                createdAt: Date,
                appVersion: String,
                edits: [ScopeEdit] = [ScopeEdit(scope: .whole)]) {
        self.sourceFilename = sourceFilename
        self.sourceDigest = sourceDigest
        self.seed = seed
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.edits = edits
    }

    /// Broadest area first, so a narrower scope painted afterwards lands on top of a wider one
    /// rather than under it. Fixed order, not insertion order: two recipes with the same content
    /// must render identically whatever sequence the user clicked in.
    static let compositingOrder: [Scope] = [.whole, .background, .subject, .brush]

    public func edit(for scope: Scope) -> ScopeEdit? {
        edits.first { $0.scope == scope }
    }

    /// Inserts or replaces one scope's state.
    public mutating func set(_ edit: ScopeEdit) {
        if let index = edits.firstIndex(where: { $0.scope == edit.scope }) {
            edits[index] = edit
        } else {
            edits.append(edit)
        }
    }

    public mutating func update(_ scope: Scope, _ body: (inout ScopeEdit) -> Void) {
        var edit = self.edit(for: scope) ?? ScopeEdit(scope: scope)
        body(&edit)
        set(edit)
    }

    /// True once at least one scope has a pass that is currently contributing.
    public var hasVisibleEnhancement: Bool { !composite().isOriginal }

    /// Any scope whose dial has been pushed above what was rendered.
    public var scopesNeedingRerun: [Scope] {
        Self.compositingOrder.compactMap { scope in
            guard let edit = edit(for: scope), edit.outcome.requiresRerun else { return nil }
            return scope
        }
    }

    /// **The rule.** No contributing layer ⇒ `.original`, always.
    public func composite() -> Composite {
        let layers: [Composite.Layer] = Self.compositingOrder.compactMap { scope in
            guard let edit = edit(for: scope),
                  let fraction = edit.outcome.fraction else { return nil }
            return Composite.Layer(scope: scope, mask: edit.mask, fraction: fraction)
        }
        return layers.isEmpty ? .original : .blended(layers)
    }

    /// Drops every pass. The original is what remains, and it never moved.
    public mutating func revertAll() {
        for index in edits.indices { edits[index].revert() }
    }
}
