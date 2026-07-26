import SwiftUI

// Reference implementation for the catalog front door: a 2-column instrument grid, grouped
// under each section header, with a Favorites group pinned on top. Adapt into the real
// RootCatalogView (keep its NavigationStack + navigationDestination). Not wired on its own.

struct CatalogGridExample: View {
    @Environment(\.tc) private var tc
    @StateObject private var favorites = FavoritesStore()

    private let columns = [GridItem(.flexible(), spacing: TC.gridGap),
                           GridItem(.flexible(), spacing: TC.gridGap)]

    /// Favorites first (if any), then the eight sections in order.
    private var groups: [(title: String, accent: Color, calcs: [Calculator])] {
        var g: [(String, Color, [Calculator])] = []
        let favs = favorites.favoriteCalculators
        if !favs.isEmpty { g.append(("Favorites", tc.star, favs)) }
        for s in CalcSection.allCases {
            g.append((s.rawValue, tc.accent(s), Calculator.calculators(in: s)))
        }
        return g
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: group.title, accent: group.accent)
                        LazyVGrid(columns: columns, spacing: TC.gridGap) {
                            ForEach(group.calcs) { calc in
                                NavigationLink(value: calc) {
                                    CatalogTile(calc: calc,
                                                isFav: favorites.isFavorite(calc),
                                                onStar: { favorites.toggle(calc) })
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(TC.screenMargin)
        }
        .background(AppBackground())
        .navigationTitle("Flight Computer")
    }
}

struct CatalogTile: View {
    @Environment(\.tc) private var tc
    let calc: Calculator
    let isFav: Bool
    let onStar: () -> Void
    private var accent: Color { tc.accent(calc.section) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: calc.symbol)
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    .background(accent.opacity(0.16), in: .rect(cornerRadius: 11))
                Spacer()
                Button(action: onStar) {
                    Image(systemName: isFav ? "star.fill" : "star")
                        .font(.footnote)
                        .foregroundStyle(isFav ? tc.star : tc.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 22)

            Text(calc.title).font(.headline).foregroundStyle(tc.textPrimary)
            Text(calc.subtitle)
                .font(.caption).foregroundStyle(tc.textSecondary)
                .lineLimit(2).frame(height: 30, alignment: .top)
        }
        .padding(TC.cardPadding - 3)
        .frame(maxWidth: .infinity, minHeight: TC.minHit, alignment: .leading)
        .background(tc.surface, in: .rect(cornerRadius: TC.rTile))
        .overlay(RoundedRectangle(cornerRadius: TC.rTile).strokeBorder(tc.hairline, lineWidth: 1))
    }
}
