import SwiftUI

/// Compact (iPhone) catalog: a 2-column instrument grid grouped by section, favourites pinned on
/// top. Lives inside `RootView`'s NavigationStack, which owns the shared `FavoritesStore`.
struct CatalogGrid: View {
    @ObservedObject var favorites: FavoritesStore

    private let columns = [GridItem(.adaptive(minimum: 168), spacing: 9)]

    private var groups: [(title: String, accent: Color, tools: [Tool])] {
        var g: [(String, Color, [Tool])] = []
        let favs = favorites.favoriteTools
        if !favs.isEmpty { g.append(("Favorites", OTL.star, favs)) }
        for s in ToolSection.allCases { g.append((s.rawValue, s.accent, Tool.tools(in: s))) }
        return g
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Sources first, and absent entirely when unavailable — `CatalogEntry.sources` is []
                // on a released SDK, so this is a missing array element rather than a disabled row.
                if !CatalogEntry.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "Sources", accent: OTL.measureAccent)
                        ForEach(CatalogEntry.sources) { entry in
                            NavigationLink(value: entry) { MeasureTile() }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("catalog.measure")
                        }
                    }
                }
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: group.title, accent: group.accent)
                        LazyVGrid(columns: columns, spacing: 9) {
                            ForEach(group.tools) { tool in
                                NavigationLink(value: CatalogEntry.tool(tool)) { ToolTile(tool: tool) }
                                    .buttonStyle(.plain)
                                    // Star lives ON TOP of the link (not inside its label) so it is
                                    // an independent tap target — tapping it toggles, not navigates.
                                    .overlay(alignment: .topTrailing) {
                                        FavStar(isFav: favorites.isFavorite(tool)) { favorites.toggle(tool) }
                                            .accessibilityIdentifier("fav.\(tool.rawValue)")
                                            .accessibilityValue(favorites.isFavorite(tool) ? "on" : "off")
                                            .padding(10)
                                    }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(AppBackground())
        .navigationTitle("Overtone Lab")
    }
}

private struct SectionLabel: View {
    let title: String
    let accent: Color
    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(accent).frame(width: 4, height: 12)
            Text(L.loc(title)).textCase(.uppercase)
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(OTL.textSecondary)
        }
    }
}

/// The favourite star — an independent control overlaid on the tool tile.
private struct FavStar: View {
    let isFav: Bool
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            Image(systemName: isFav ? "star.fill" : "star")
                .font(.footnote)
                .foregroundStyle(isFav ? OTL.star : OTL.textTertiary)
                .padding(6)                       // enlarge the tap target
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ToolTile: View {
    let tool: Tool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: tool.symbol)
                    .font(.title3)
                    .foregroundStyle(tool.accent)
                Spacer()
                Color.clear.frame(width: 16, height: 16)   // reserve the star's corner
            }
            .padding(.bottom, 14)

            Text(tool.title).font(.headline).foregroundStyle(OTL.textPrimary)
            Text(tool.subtitle)
                .font(.caption)
                .foregroundStyle(OTL.textSecondary)
                .lineLimit(2)
                .frame(height: 30, alignment: .top)
            Text(tool.sample)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(tool.accent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OTL.surface, in: .rect(cornerRadius: OTL.rTile))
        .overlay(alignment: .top) {                   // section-accent top bar
            Rectangle().fill(tool.accent).frame(height: 2).opacity(0.7)
                .clipShape(.rect(topLeadingRadius: OTL.rTile, topTrailingRadius: OTL.rTile))
        }
        .overlay(RoundedRectangle(cornerRadius: OTL.rTile).strokeBorder(OTL.hairline, lineWidth: 1))
    }
}

/// The Measure tile — full width, not a grid cell: a source is not one of 26 peers, and the catalog
/// should not read as "27 tools" the moment it appears.
private struct MeasureTile: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.badge.mic")
                .font(.title3)
                .foregroundStyle(OTL.measureAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Measure")
                    .font(.system(.body, design: .default).weight(.semibold))
                    .foregroundStyle(OTL.textPrimary)
                Text("Analyse audio, hand values over")
                    .font(.caption)
                    .foregroundStyle(OTL.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(OTL.textTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(OTL.surface, in: .rect(cornerRadius: OTL.rCard))
        .overlay(RoundedRectangle(cornerRadius: OTL.rCard).strokeBorder(OTL.hairline, lineWidth: 1))
    }
}
