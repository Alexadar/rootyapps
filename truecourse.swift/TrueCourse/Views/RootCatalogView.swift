import SwiftUI

/// Compact (iPhone) catalog: a 2-column instrument grid grouped by section, favourites pinned on
/// top. Lives inside `RootView`'s NavigationStack, which owns the shared `FavoritesStore`.
struct CatalogGrid: View {
    @Environment(\.tc) private var tc
    @ObservedObject var favorites: FavoritesStore

    private let columns = [GridItem(.flexible(), spacing: TC.gridGap),
                           GridItem(.flexible(), spacing: TC.gridGap)]

    private var groups: [(title: String, accent: Color, tools: [Tool])] {
        var g: [(String, Color, [Tool])] = []
        let favs = favorites.favoriteTools
        if !favs.isEmpty { g.append(("Favorites", tc.star, favs)) }
        for s in CalcGroup.allCases { g.append((s.rawValue, tc.accent(s), Tool.tools(in: s))) }
        return g
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: group.title, accent: group.accent)
                        LazyVGrid(columns: columns, spacing: TC.gridGap) {
                            ForEach(group.tools) { tool in
                                NavigationLink(value: tool) { ToolTile(tool: tool) }
                                    .buttonStyle(.plain)
                                    // Star sits ON TOP of the link so it is an independent tap
                                    // target — tapping it toggles, not navigates.
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
            .padding(TC.screenMargin)
        }
        #if os(iOS)
        .scrollEdgeEffectStyle(.soft, for: .all)
        #endif
        .background(AppBackground())
        .navigationTitle("TrueCourse")
    }
}

/// The favourite star — an independent control overlaid on the tool tile.
private struct FavStar: View {
    @Environment(\.tc) private var tc
    let isFav: Bool
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            Image(systemName: isFav ? "star.fill" : "star")
                .font(.footnote)
                .foregroundStyle(isFav ? tc.star : tc.textTertiary)
                .padding(6)                       // enlarge the tap target
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ToolTile: View {
    @Environment(\.tc) private var tc
    let tool: Tool
    private var accent: Color { tc.accent(tool.group) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: tool.symbol)
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    .background(accent.opacity(0.16), in: .rect(cornerRadius: 11))
                Spacer()
                Color.clear.frame(width: 20, height: 20)   // reserve the star's corner
            }
            .padding(.bottom, 20)

            Text(tool.title).font(.headline).foregroundStyle(tc.textPrimary)
            Text(tool.subtitle)
                .font(.caption).foregroundStyle(tc.textSecondary)
                .lineLimit(2).frame(height: 30, alignment: .top)
        }
        .padding(TC.cardPadding - 3)
        .frame(maxWidth: .infinity, minHeight: TC.minHit, alignment: .leading)
        .background(tc.surface, in: .rect(cornerRadius: TC.rTile))
        .overlay(RoundedRectangle(cornerRadius: TC.rTile).strokeBorder(tc.hairline, lineWidth: 1))
    }
}
