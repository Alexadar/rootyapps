import SwiftUI

/// Regular-size root (iPad · Mac · iPhone landscape): a 78pt icon rail (the three surfaces, ⌘1–3),
/// a 296pt category sidebar (owns "which slice of this surface"), and the content pane. Replaces the
/// old 2-column `NavigationSplitView`. Compact stays on `TabView` in `ContentView`. Presentation only.
struct RegularRoot: View {
    @ObservedObject var favorites: FavoritesStore
    @EnvironmentObject private var router: Router

    var body: some View {
        HStack(spacing: 0) {
            RailView()
            Divider().overlay(KC.hairline)
            switch router.surface {
            case .spec:
                content
            case .formulas:
                CategorySidebar(favorites: favorites)
                Divider().overlay(KC.hairline)
                content
            case .reference:
                ReferenceSidebar()
                Divider().overlay(KC.hairline)
                content
            }
        }
        .background(AppBackground())
    }

    @ViewBuilder private var content: some View {
        switch router.surface {
        case .spec:      CalcView()
        case .formulas:  ToolsRootView(favorites: favorites)
        case .reference: ReferenceView()
        }
    }
}

// MARK: - 78pt icon rail
private struct RailView: View {
    @EnvironmentObject private var router: Router
    var body: some View {
        VStack(spacing: 10) {
            Text("K.").font(.system(size: 15, weight: .black))
                .foregroundStyle(KC.signal)
                .frame(width: 40, height: 40)
                .background(KC.instrument, in: .rect(cornerRadius: 12))
                .padding(.bottom, 14)
            item(.spec, "square.grid.2x2", "Spec", "1")
            item(.formulas, "function", "Formulas", "2")
            item(.reference, "book", "Reference", "3")
            Spacer()
        }
        .padding(.vertical, 18)
        .frame(width: 78)
        .background(Color(rgbHex: 0xE7E3D9))
    }

    private func item(_ s: Router.Surface, _ icon: String, _ label: String, _ key: String) -> some View {
        let active = router.surface == s
        return Button { router.surface = s } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(active ? KC.signal : KC.textSecondary)
                Text(label).font(.system(size: 9, weight: .bold))
                    .foregroundStyle(active ? KC.onInstrument : KC.textSecondary)
            }
            .frame(width: 52, height: 52)
            .background(active ? KC.instrument : .clear, in: .rect(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character(key)), modifiers: .command)   // ⌘1–3
    }
}

// MARK: - 296pt category sidebar (Formulas)
private struct CategorySidebar: View {
    @ObservedObject var favorites: FavoritesStore
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Formulas").font(.system(size: 26, weight: .heavy)).kerning(-0.4)
                    .padding(.horizontal, 4).padding(.bottom, 8)

                row(nil, "All formulas", Tool.allCases.count)
                ForEach(ToolSection.allCases) { s in
                    row(s, s.rawValue, Tool.tools(in: s).count)
                }

                if !favorites.favoriteTools.isEmpty {
                    Divider().overlay(KC.hairline).padding(.vertical, 8)
                    Text("FAVORITES")
                        .font(.system(.caption2, design: .monospaced).weight(.bold)).tracking(1.4)
                        .foregroundStyle(KC.textTertiary).padding(.horizontal, 4)
                    ForEach(favorites.favoriteTools) { tool in
                        Button { router.open(tool) } label: {
                            HStack(spacing: 10) {
                                CodeBadge(tool: tool, size: 28)
                                Text(tool.title).font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(KC.textPrimary)
                                Spacer()
                                Image(systemName: "star.fill").font(.caption2).foregroundStyle(KC.star)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 296)
        .background(Color(rgbHex: 0xEAE6DC))
    }

    private func row(_ s: ToolSection?, _ name: String, _ count: Int) -> some View {
        let active = router.category == s
        return Button {
            withAnimation(.snappy(duration: 0.2)) { router.category = s; router.formulasPath = [] }
        } label: {
            HStack(spacing: 10) {
                if let s {
                    RoundedRectangle(cornerRadius: 3).fill(s.accent).frame(width: 9, height: 9)
                } else {
                    Text("∗").font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(KC.textSecondary).frame(width: 9)
                }
                Text(name).font(.system(size: 15, weight: active ? .bold : .semibold))
                    .foregroundStyle(active ? KC.onInstrument : KC.textPrimary)
                Spacer()
                Text("\(count)").font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(active ? KC.signal : KC.textTertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(active ? KC.instrument : .clear, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        // `category.all` / `category.<section>` — the reel and the iPad tests need to clear the trade
        // filter, and matching the visible words would break the moment the copy changes.
        .accessibilityIdentifier("category." + (s?.rawValue ?? "all"))
    }
}

// MARK: - 296pt section sidebar (Reference)
private struct ReferenceSidebar: View {
    @EnvironmentObject private var router: Router
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Reference").font(.system(size: 26, weight: .heavy)).kerning(-0.4)
                    .padding(.horizontal, 4).padding(.bottom, 8)
                row(nil, "All")
                ForEach(ReferenceSection.allCases) { row($0, $0.rawValue) }
            }
            .padding(14)
        }
        .frame(width: 296)
        .background(Color(rgbHex: 0xEAE6DC))
    }

    private func row(_ s: ReferenceSection?, _ name: String) -> some View {
        let active = router.refSection == s
        return Button {
            withAnimation(.snappy(duration: 0.2)) { router.refSection = s }
        } label: {
            HStack {
                Text(name).font(.system(size: 15, weight: active ? .bold : .semibold))
                    .foregroundStyle(active ? KC.onInstrument : KC.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(active ? KC.instrument : .clear, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        // `category.all` / `category.<section>` — the reel and the iPad tests need to clear the trade
        // filter, and matching the visible words would break the moment the copy changes.
        .accessibilityIdentifier("category." + (s?.rawValue ?? "all"))
    }
}
