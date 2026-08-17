import Foundation

public enum SpaceMode: String, Sendable, Codable, CaseIterable, Hashable {
    case interior
    case exterior
}

/// A direction, as a prompt macro.
///
/// The design handoff's scope decision is explicit: presets **seed an editable prompt field**.
/// They are not filters and not styles applied after the fact — picking one writes words into a
/// text field the user can then change. Free text is optional and never required.
///
/// Swatches are hex integers rather than `Color` so this package stays Foundation-only; the app
/// maps hex to `Color` in exactly one place.
public struct StylePreset: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    /// The one-line palette description under the name on the card.
    public let sub: String
    public let swatchHexes: [UInt32]
    public let prompt: String
    public let mode: SpaceMode

    public init(id: String,
                name: String,
                sub: String,
                swatchHexes: [UInt32],
                prompt: String,
                mode: SpaceMode) {
        self.id = id
        self.name = name
        self.sub = sub
        self.swatchHexes = swatchHexes
        self.prompt = prompt
        self.mode = mode
    }
}

public enum PresetCatalog {

    /// Interior, exactly as the design handoff specifies.
    public static let interior: [StylePreset] = [
        StylePreset(id: "scandi", name: "Scandinavian", sub: "Pale oak, white, calm",
                    swatchHexes: [0xEFEAE2, 0xD8C6A6, 0xC7CBC6, 0x5E7357],
                    prompt: "Bright Scandinavian living room, pale oak floor, white walls, wool textiles",
                    mode: .interior),
        StylePreset(id: "midcentury", name: "Mid-century", sub: "Walnut, brass, olive",
                    swatchHexes: [0x8A5A34, 0xC98F4B, 0x3F5044, 0xE4D6BC],
                    prompt: "Mid-century modern living room, walnut furniture, brass accents, olive tones",
                    mode: .interior),
        StylePreset(id: "industrial", name: "Industrial", sub: "Concrete, steel, leather",
                    swatchHexes: [0x4A4A4C, 0x8C8C8E, 0x5C4632, 0xB7B3AC],
                    prompt: "Industrial loft interior, concrete walls, steel fixtures, leather seating",
                    mode: .interior),
        StylePreset(id: "japandi", name: "Japandi", sub: "Low, warm, unadorned",
                    swatchHexes: [0xE9E2D4, 0xB8A88C, 0x6B6A5E, 0x2E2C27],
                    prompt: "Japandi interior, low wooden furniture, warm neutral palette, uncluttered",
                    mode: .interior),
    ]

    /// Exterior. The design board specifies four — Modern farmhouse, Georgian, Mediterranean and a
    /// minimal render — but `DesignSystem.swift` only ever shipped two, because `DirectionView`
    /// hardcoded `mode = .interior` and the exterior list was unreachable.
    ///
    /// ⚠️ `georgian` and `minimalRender` are AUTHORED HERE: the board names them but specifies no
    /// palette and no prompt. Both follow the shape of the two that were specified — a facade, a
    /// material, an opening treatment — and both are flagged in the report for the owner's review.
    public static let exterior: [StylePreset] = [
        StylePreset(id: "farmhouse", name: "Modern farmhouse", sub: "Board & batten, black trim",
                    swatchHexes: [0xE8E4DA, 0x2E2C27, 0x8FA98F, 0xB99B78],
                    prompt: "Modern farmhouse facade, white board and batten siding, black window trim",
                    mode: .exterior),
        StylePreset(id: "georgian", name: "Georgian", sub: "Brick, sash windows, symmetry",
                    swatchHexes: [0x8E5B4A, 0xF2EDE4, 0x2C3A2E, 0xC9B79A],
                    prompt: "Georgian house facade, red brick, white sash windows, stone lintels, symmetrical proportions",
                    mode: .exterior),
        StylePreset(id: "mediterranean", name: "Mediterranean", sub: "Stucco, terracotta, arches",
                    swatchHexes: [0xF0E6D4, 0xB4552D, 0x7E9694, 0x5C4632],
                    prompt: "Mediterranean house facade, warm stucco, terracotta roof tiles, arched windows",
                    mode: .exterior),
        StylePreset(id: "minimalRender", name: "Minimal render", sub: "White, glass, clean lines",
                    swatchHexes: [0xF5F4F1, 0xD9D6CF, 0x3A3F42, 0x8FA3A8],
                    prompt: "Minimal contemporary house facade, smooth white render, large glass panes, flat roof, clean lines",
                    mode: .exterior),
    ]

    public static func presets(for mode: SpaceMode) -> [StylePreset] {
        switch mode {
        case .interior: return interior
        case .exterior: return exterior
        }
    }

    public static var all: [StylePreset] { interior + exterior }

    public static func preset(id: String) -> StylePreset? {
        all.first { $0.id == id }
    }

    /// What a project falls back to when its preset id is no longer in the catalog — a project
    /// synced from a newer build, or a preset renamed between versions. The prompt is stored on
    /// the project, so nothing is lost; only the card highlight is.
    public static func first(for mode: SpaceMode) -> StylePreset {
        presets(for: mode)[0]
    }
}
