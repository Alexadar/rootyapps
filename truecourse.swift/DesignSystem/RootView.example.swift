import SwiftUI

// Cross-platform root: iPhone (compact) → grouped grid + push nav;
// iPad landscape / Mac / wide multitasking (regular) → NavigationSplitView.
// Same tokens & components everywhere — only the container adapts.
// A single toolbar toggle flips Dark ↔ Night for the whole app.
// Adapt into RootCatalogView.swift / ContentView.swift.

struct RootViewExample: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var theme = ThemeStore()
    @State private var selection: Calculator? = nil

    var body: some View {
        content
            .tcTheme(theme.selected)          // ← one line themes everything (Dark / Night)
            .toolbar { nightToggle }
    }

    @ViewBuilder private var content: some View {
        #if os(macOS)
        splitView                             // Mac is always regular width
        #else
        if hSize == .regular {
            splitView                         // iPad landscape / multitasking
        } else {
            NavigationStack {                 // iPhone / compact iPad
                CatalogGridExample()
                    .navigationDestination(for: Calculator.self) { CalculatorDetailView(calc: $0) }
            }
        }
        #endif
    }

    private var splitView: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if !favorites.favoriteCalculators.isEmpty {
                    CalcGroup(title: "Favorites", accent: .yellow,
                              calcs: favorites.favoriteCalculators, favorites: favorites)
                }
                ForEach(CalcSection.allCases) { section in
                    CalcGroup(title: section.rawValue, accent: nil, section: section,
                              calcs: Calculator.calculators(in: section), favorites: favorites)
                }
            }
            .navigationTitle("TrueCourse")
            #if os(iOS)
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
            #endif
        } detail: {
            if let calc = selection {
                CalculatorDetailView(calc: calc)
                    .tint(currentAccent(calc))                 // accent flows to ResultRow + picker
                    .background(AppBackground(accent: currentAccent(calc)))
            } else {
                ContentUnavailableView("Select a calculator", systemImage: "wind")
            }
        }
    }

    // Accent is palette-resolved; read the env palette here.
    @Environment(\.tc) private var tc
    private func currentAccent(_ c: Calculator) -> Color { tc.accent(c.section) }

    private var nightToggle: some ToolbarContent {
        ToolbarItem {
            Button {
                withAnimation(.smooth) { theme.toggle() }
            } label: {
                Image(systemName: theme.selected == .night ? "moon.stars.fill" : "sun.max.fill")
            }
            .accessibilityLabel(theme.selected == .night ? "Night mode on" : "Day mode on")
        }
    }
}

/// One sidebar section: a coloured label + tappable rows with a favourite swipe.
private struct CalcGroup: View {
    @Environment(\.tc) private var tc
    let title: String
    var accent: Color? = nil
    var section: CalcSection? = nil
    let calcs: [Calculator]
    @ObservedObject var favorites: FavoritesStore

    private func rowAccent(_ c: Calculator) -> Color { accent ?? tc.accent(c.section) }

    var body: some View {
        Section {
            ForEach(calcs) { calc in
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(calc.title).font(.body.weight(.semibold))
                        Text(calc.subtitle).font(.caption).foregroundStyle(tc.textSecondary)
                    }
                } icon: {
                    Image(systemName: calc.symbol).foregroundStyle(rowAccent(calc))
                }
                .tag(calc)
                .swipeActions(edge: .leading) {
                    Button { favorites.toggle(calc) } label: {
                        Image(systemName: favorites.isFavorite(calc) ? "star.slash" : "star")
                    }.tint(tc.star)
                }
            }
        } header: {
            SectionLabel(title: title, accent: accent ?? (section.map { tc.accent($0) } ?? tc.brand))
        }
    }
}

// MARK: - Detail (sketch — the real screen lives in the app, using the shared components)

/// Illustrates how a calculator screen composes the primitives. On regular width, inputs
/// and the readout sit side by side; on compact they stack. The real per-tool screens keep
/// their existing ViewModels & the exact set of inputs/outputs.
struct CalculatorDetailView: View {
    @Environment(\.tc) private var tc
    @Environment(\.horizontalSizeClass) private var hSize
    let calc: Calculator
    @State private var ias = 115.0, pa = 3000.0, oat = 18.0, cal = -2.0

    var body: some View {
        ScrollView {
            let stack = (hSize == .regular)
            AdaptiveStack(horizontal: stack, spacing: 20) {
                VStack(spacing: 12) {
                    NumberField(title: "Indicated Airspeed", value: $ias, unit: "kt", range: 40...250)
                    NumberField(title: "Pressure Altitude", value: $pa, unit: "ft", range: 0...20000)
                    NumberField(title: "OAT", value: $oat, unit: "°C", range: -40...50)
                    NumberField(title: "Calibration", value: $cal, unit: "kt", range: -10...10)
                }
                .frame(maxWidth: stack ? 360 : .infinity)

                ResultCard(accent: tc.accent(calc.section)) {
                    VStack(alignment: .leading, spacing: 10) {
                        CardHeader(title: "Result")
                        ResultRow(label: "True Airspeed", value: "124.6", unit: "kt", emphasis: true)
                        ResultRow(label: "Density Altitude", value: "3,180", unit: "ft")
                        ResultRow(label: "Mach", value: "0.19")
                    }
                }
                .frame(maxWidth: stack ? .infinity : .infinity)
            }
            .padding(TC.screenMargin)
        }
        .background(AppBackground(accent: tc.accent(calc.section)))
        .tint(tc.accent(calc.section))
        .navigationTitle(calc.title)
    }
}

/// HStack on regular width, VStack on compact.
private struct AdaptiveStack<Content: View>: View {
    let horizontal: Bool
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        if horizontal { HStack(alignment: .top, spacing: spacing) { content } }
        else { VStack(spacing: spacing) { content } }
    }
}
