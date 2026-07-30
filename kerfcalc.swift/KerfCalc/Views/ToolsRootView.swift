import SwiftUI

/// Formulas tab: a searchable, trade-grouped grid with a pinned Favorites row. Each tile is a glove
/// target — a mono trade "code" badge, name, subtitle, live sample readout, and a star.
struct ToolsRootView: View {
    @ObservedObject var favorites: FavoritesStore
    @EnvironmentObject private var router: Router
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var query = ""
    @State private var chipSection: ToolSection?

    /// Compact uses the chip row under the search field; regular is driven by the category sidebar.
    private var activeSection: ToolSection? { hSize == .regular ? router.category : chipSection }

    private let columns = [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)]

    private func matches(_ tool: Tool) -> Bool {
        query.isEmpty ||
        tool.title.localizedCaseInsensitiveContains(query) ||
        tool.subtitle.localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        NavigationStack(path: $router.formulasPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if query.isEmpty && activeSection == nil && !favorites.favoriteTools.isEmpty {
                        SectionLabel(title: "Favorites", accent: KC.star)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 9) {
                                ForEach(favorites.favoriteTools) { tool in
                                    NavigationLink(value: tool) { FavChip(tool: tool) }.buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    ForEach(ToolSection.allCases.filter { activeSection == nil || $0 == activeSection }) { section in
                        let tools = Tool.tools(in: section).filter(matches)
                        if !tools.isEmpty {
                            VStack(alignment: .leading, spacing: 11) {
                                SectionLabel(title: section.rawValue, accent: section.accent,
                                             count: "\(tools.count) calc\(tools.count == 1 ? "" : "s")")
                                LazyVGrid(columns: columns, spacing: 11) {
                                    ForEach(tools) { tool in
                                        NavigationLink(value: tool) {
                                            ToolTile(tool: tool,
                                                     isFav: favorites.isFavorite(tool),
                                                     onStar: { favorites.toggle(tool) })
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(AppBackground())
            .safeAreaInset(edge: .top, spacing: 0) {
                KCGlassTopBar {
                    if hSize != .regular {
                        Text("Formulas").font(.system(size: 30, weight: .heavy)).kerning(-0.4)
                    }
                    searchField
                    if hSize != .regular {
                        CategoryChips(items: CategoryChips<ToolSection>.formulaItems(), selection: $chipSection)
                    }
                }
            }
            .navigationDestination(for: Tool.self) { ToolDetailView(tool: $0) }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(KC.textTertiary)
            TextField("Search formulas", text: $query)
                .textFieldStyle(.plain).font(.system(size: 15))
        }
        .padding(.horizontal, 13).padding(.vertical, 12)
        .background(KC.surface, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(KC.hairline, lineWidth: 1))
    }
}

/// The mono "element" badge — trade-tint fill, trade-colour code.
struct CodeBadge: View {
    let tool: Tool
    var size: CGFloat = 40
    var body: some View {
        Text(tool.code)
            .font(.system(size: size * 0.31, weight: .heavy, design: .monospaced))
            .foregroundStyle(tool.accent)
            .frame(width: size, height: size)
            .background(tool.tint, in: .rect(cornerRadius: size * 0.30))
    }
}

private struct SectionLabel: View {
    let title: String
    let accent: Color
    var count: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(accent).frame(width: 9, height: 9)
            Text(title.uppercased())
                .font(.system(.caption2, design: .monospaced).weight(.bold)).tracking(1.4)
                .foregroundStyle(KC.textPrimary)
            if let count {
                Text(count).font(.system(.caption2, design: .monospaced)).foregroundStyle(KC.textTertiary)
            }
        }
    }
}

private struct FavChip: View {
    let tool: Tool
    var body: some View {
        HStack(spacing: 9) {
            CodeBadge(tool: tool, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.title).font(.system(size: 13, weight: .bold)).foregroundStyle(KC.onInstrument)
                Text(tool.sample).font(.system(size: 10, design: .monospaced)).foregroundStyle(KC.instrumentDim)
            }
        }
        .padding(.leading, 11).padding(.trailing, 14).padding(.vertical, 11)
        .background(KC.instrument, in: .rect(cornerRadius: 14))
    }
}

private struct ToolTile: View {
    let tool: Tool
    let isFav: Bool
    let onStar: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                CodeBadge(tool: tool)
                Spacer()
                Button(action: onStar) {
                    Image(systemName: isFav ? "star.fill" : "star")
                        .font(.footnote).foregroundStyle(isFav ? KC.star : KC.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fav." + tool.rawValue)
                .accessibilityLabel(isFav ? "Remove \(tool.title) from favourites"
                                          : "Add \(tool.title) to favourites")
            }
            // Both ids sit on LEAVES. An identifier on the enclosing NavigationLink would overwrite
            // every child's — including the star above — so nothing could address one of them.
            // Tapping this title activates the link, which is what a test wants anyway.
            Text(tool.title).font(.system(size: 16, weight: .bold)).foregroundStyle(KC.textPrimary)
                .accessibilityIdentifier("tool." + tool.rawValue)
            Text(tool.subtitle)
                .font(.caption).foregroundStyle(KC.textSecondary)
                .lineLimit(2).frame(maxHeight: .infinity, alignment: .top)
            Text(tool.sample)
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundStyle(KC.textSecondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(KC.chipFill, in: .rect(cornerRadius: 7))
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(KC.surface, in: .rect(cornerRadius: KC.rTile))
        .overlay(RoundedRectangle(cornerRadius: KC.rTile).strokeBorder(KC.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.03), radius: 1, y: 1)
    }
}
