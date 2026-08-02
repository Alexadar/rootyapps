import SwiftUI

// Cross-platform root — Kerf Calc. Three surfaces: Spec · Formulas · Reference.
// Driven by horizontal size class, never by device:
//
//   • Compact (iPhone portrait)      → TabView; Formulas filters with CategoryChips.
//   • Regular (iPad, iPhone landscape, Mac) → rail + category sidebar + content:
//       ┌────┬─────────────┬──────────────────────────┐
//       │rail│  sidebar    │  content                 │
//       │ 78 │  ~300       │  grid / side-by-side     │
//       └────┴─────────────┴──────────────────────────┘
//     The rail owns the three surfaces (⌘1–3 on Mac); the sidebar owns the
//     category (Formulas: All + trades + Favorites · Reference: sections);
//     an open formula lays inputs LEFT and results RIGHT — never a stretched phone.
//
// Adapt into ContentView.swift; keep Router as the single navigation source.

struct RootViewExampleV2: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @StateObject private var favorites = FavoritesStore()
    @State private var surface: Surface = .formulas
    @State private var toolSection: ToolSection? = .framing   // nil = All
    @State private var openTool: Tool? = .rafter

    enum Surface: String, CaseIterable { case spec = "Spec", formulas = "Formulas", reference = "Reference" }

    var body: some View {
        if hSize == .regular {
            regular
        } else {
            compactTabs
        }
    }

    // MARK: compact — tabs + chips (see ToolsRootView restyle notes below)
    private var compactTabs: some View {
        TabView {
            SpecCalcExample()
                .tabItem { Label("Spec", systemImage: "square.grid.2x2") }
            NavigationStack {
                CatalogGridExample()   // + CategoryChips(items: .formulaItems(), selection:) under search
            }
            .tabItem { Label("Formulas", systemImage: "function") }
            ReferenceViewExample()
                .tabItem { Label("Reference", systemImage: "book") }
        }
        .tint(KC.textPrimary)
        .preferredColorScheme(.light)
    }

    // MARK: regular — rail + sidebar + content
    private var regular: some View {
        HStack(spacing: 0) {
            rail
            Divider().overlay(KC.hairline)
            sidebar
            Divider().overlay(KC.hairline)
            content
        }
        .background(AppBackground())
        .preferredColorScheme(.light)
    }

    // The 78pt icon rail — the three surfaces. Active = graphite block, signal glyph.
    private var rail: some View {
        VStack(spacing: 10) {
            // app mark
            Text("K.").font(.system(size: 15, weight: .black))
                .foregroundStyle(KC.signal)
                .frame(width: 40, height: 40)
                .background(KC.instrument, in: .rect(cornerRadius: 12))
                .padding(.bottom, 14)

            railItem(.spec, icon: "square.grid.2x2", key: "1")
            railItem(.formulas, icon: "function", key: "2")
            railItem(.reference, icon: "book", key: "3")
            Spacer()
            Image(systemName: "gearshape").foregroundStyle(KC.textSecondary)
        }
        .padding(.vertical, 18)
        .frame(width: 78)
        .background(Color(rgbHex: 0xE7E3D9))
    }

    private func railItem(_ s: Surface, icon: String, key: String) -> some View {
        let active = surface == s
        return Button { surface = s } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(active ? KC.signal : KC.textSecondary)
                Text(s.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(active ? KC.onInstrument : KC.textSecondary)
            }
            .frame(width: 52, height: 52)
            .background(active ? KC.instrument : .clear, in: .rect(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character(key)), modifiers: .command)  // ⌘1–3 (Mac/iPad kb)
    }

    // The category sidebar — owns "which slice of this surface".
    @ViewBuilder
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(surface.rawValue)
                .font(.system(size: 26, weight: .heavy)).kerning(-0.4)
                .padding(.horizontal, 4).padding(.bottom, 8)

            switch surface {
            case .formulas:
                categoryRow(nil, name: "All formulas", count: Tool.allCases.count)
                ForEach(ToolSection.allCases) { s in
                    categoryRow(s, name: s.rawValue, count: Tool.tools(in: s).count)
                }
                Divider().overlay(KC.hairline).padding(.vertical, 8)
                Text("FAVORITES")
                    .font(.system(.caption2, design: .monospaced).weight(.bold)).tracking(1.4)
                    .foregroundStyle(KC.textTertiary).padding(.horizontal, 4)
                ForEach(favorites.favoriteTools) { tool in
                    Button { openTool = tool; toolSection = tool.section } label: {
                        HStack(spacing: 10) {
                            CodeBadge(tool: tool, size: 28)
                            Text(tool.title).font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Image(systemName: "star.fill").font(.caption2).foregroundStyle(KC.star)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                    }.buttonStyle(.plain)
                }
            case .reference, .spec:
                EmptyView()   // Reference: section list · Spec: recents/tape — same row pattern
            }
            Spacer()
        }
        .padding(14)
        .frame(width: 296)
        .background(Color(rgbHex: 0xEAE6DC))
    }

    private func categoryRow(_ s: ToolSection?, name: String, count: Int) -> some View {
        let active = toolSection == s
        return Button { withAnimation(.snappy(duration: 0.2)) { toolSection = s } } label: {
            HStack(spacing: 10) {
                if let s {
                    RoundedRectangle(cornerRadius: 3).fill(s.accent).frame(width: 9, height: 9)
                } else {
                    Text("∗").font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(KC.textSecondary).frame(width: 9)
                }
                Text(name)
                    .font(.system(size: 15, weight: active ? .bold : .semibold))
                    .foregroundStyle(active ? KC.onInstrument : KC.textPrimary)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(active ? KC.signal : KC.textTertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(active ? KC.instrument : .clear, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // Content: the filtered grid, and the open formula side by side (see ToolDetail example).
    @ViewBuilder
    private var content: some View {
        switch surface {
        case .formulas:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // grid of tiles for `toolSection` (3-up), then the open tool's
                    // regular detail — ToolDetailRegularExample lays inputs | results.
                    if openTool != nil { ToolDetailRegularExample() }
                }
                .padding(22)
            }
        case .reference:
            ReferenceViewExample()
        case .spec:
            SpecCalcExample()   // landscape Pro: pad | tape | quick formulas (see turn-1 canvas)
        }
    }
}
