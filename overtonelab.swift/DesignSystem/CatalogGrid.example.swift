import SwiftUI

// Reference implementation for restyling RootCatalogView.swift to direction 1b:
// a 2-column instrument grid, grouped under each section header, with a Favorites
// group pinned on top. Adapt into the real RootCatalogView (keep its NavigationStack
// + navigationDestination). Not wired to the app on its own.

struct CatalogGridExample: View {
    @StateObject private var favorites = FavoritesStore()

    private let columns = [GridItem(.flexible(), spacing: 9),
                           GridItem(.flexible(), spacing: 9)]

    /// Favorites first (if any), then the four sections in order.
    private var groups: [(title: String, accent: Color, tools: [Tool])] {
        var g: [(String, Color, [Tool])] = []
        let favs = favorites.favoriteTools
        if !favs.isEmpty { g.append(("Favorites", OTL.star, favs)) }
        for s in ToolSection.allCases { g.append((s.rawValue, s.accent, Tool.tools(in: s))) }
        return g.map { ($0.0, $0.1, $0.2) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: group.title, accent: group.accent)
                        LazyVGrid(columns: columns, spacing: 9) {
                            ForEach(group.tools) { tool in
                                NavigationLink(value: tool) {
                                    ToolTile(tool: tool,
                                             isFav: favorites.isFavorite(tool),
                                             onStar: { favorites.toggle(tool) })
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(AppBackground())
    }
}

private struct SectionLabel: View {
    let title: String
    let accent: Color
    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(accent).frame(width: 4, height: 12)
            Text(title.uppercased())
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(OTL.textSecondary)
        }
    }
}

private struct ToolTile: View {
    let tool: Tool
    let isFav: Bool
    let onStar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: tool.symbol)
                    .font(.title3)
                    .foregroundStyle(tool.accent)
                Spacer()
                Button(action: onStar) {
                    Image(systemName: isFav ? "star.fill" : "star")
                        .font(.footnote)
                        .foregroundStyle(isFav ? OTL.star : OTL.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 14)

            Text(tool.title).font(.headline)
            Text(tool.subtitle)
                .font(.caption)
                .foregroundStyle(OTL.textSecondary)
                .lineLimit(2)
                .frame(height: 30, alignment: .top)
            // Optional: a live sample readout per tile, in the section accent.
            // Text(tool.sample).font(.system(.callout, design: .monospaced).weight(.semibold))
            //     .foregroundStyle(tool.accent)
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
