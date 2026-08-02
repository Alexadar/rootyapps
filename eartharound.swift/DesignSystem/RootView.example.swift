import SwiftUI

// REFERENCE ONLY — how SpaceWeatherRootView adopts the HUD system. Apply these ideas to
// the real root (keep the store, refresh, offline, and settings logic exactly as is):
//
//   1. `.swTheme(theme.selected)` once, at the top of the body.
//   2. Header → wordmark + status line + Night toggle (moon) next to refresh/gear.
//   3. Tab `Picker` → `SWSegmented` via a tiny index Binding.
//   4. Optional matchup strip under the header: the live scoreline at a glance.

struct RootViewExample: View {
    @StateObject private var theme = ThemeStore()
    @State private var tab = 0
    @Environment(\.sw) private var sw

    var body: some View {
        ZStack {
            SpaceBackground(accent: sw.brand)
            VStack(spacing: 12) {
                header
                matchupStrip          // optional — the scoreline at a glance
                SWSegmented(titles: ["Dashboard", "Geomagnetic"], selection: $tab)
                    .padding(.horizontal, SWM.screenMargin)
                // ScrollView { DashboardView(…) / GeomagView(…) }  — unchanged
                Spacer()
            }
        }
        .tint(sw.brand)
        .swTheme(theme.selected)
    }

    // MARK: Header — wordmark, status, controls

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("//")
                        .font(.system(.headline, design: .monospaced).weight(.heavy))
                        .foregroundStyle(sw.brand)
                    Text("SPACE WEATHER")
                        .font(.system(size: 22, weight: .heavy))
                        .tracking(-0.4)
                        .foregroundStyle(sw.textPrimary)
                    Text("LIVE")
                        .font(.system(size: 9, design: .monospaced).weight(.bold))
                        .tracking(1.2)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .foregroundStyle(sw.onAccent)
                        .background(sw.brand, in: ChamferBox(cut: 5, radius: 3))
                }
                Text("UPDATED 4M AGO · NOAA + GFZ, VALIDATED")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(sw.textTertiary)
            }
            Spacer()
            HStack(spacing: 16) {
                Button { theme.toggle() } label: {
                    Image(systemName: theme.selected == .night ? "moon.stars.fill" : "moon.stars")
                        .foregroundStyle(theme.selected == .night ? sw.brand : sw.textSecondary)
                }
                .accessibilityLabel("Night mode")
                Button {} label: {           // store.refresh() in the real root
                    Image(systemName: "arrow.clockwise").foregroundStyle(sw.brand)
                }
                Button {} label: {           // showSettings in the real root
                    Image(systemName: "gearshape").foregroundStyle(sw.textSecondary)
                }
            }
            .font(.body.weight(.semibold))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SWM.screenMargin)
        .padding(.top, 8)
    }

    // MARK: Matchup strip — SUN vs EARTH scoreline (values from snapshot.scales / kp)

    private var matchupStrip: some View {
        HStack(spacing: 10) {
            sideChip(side: .solar, label: "SUN", score: "R1")
            Text("VS")
                .font(.system(size: 10, design: .monospaced).weight(.heavy))
                .foregroundStyle(sw.textTertiary)
            sideChip(side: .terra, label: "EARTH", score: "G1")
            Spacer()
            Text("WIND 620 KM/S")
                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(sw.side(.link))
        }
        .padding(.horizontal, SWM.screenMargin)
    }

    private func sideChip(side: SWSide, label: String, score: String) -> some View {
        HStack(spacing: 6) {
            Text("//")
                .font(.system(size: 10, design: .monospaced).weight(.heavy))
                .foregroundStyle(sw.side(side))
            Text(label)
                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                .tracking(1.0)
                .foregroundStyle(sw.textSecondary)
            Text(score)
                .font(.system(size: 11, design: .monospaced).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(sw.textPrimary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(sw.surface, in: ChamferBox(cut: 6, radius: SWM.rChip))
        .overlay(ChamferBox(cut: 6, radius: SWM.rChip).strokeBorder(sw.hairline, lineWidth: 1))
    }
}

// MARK: Enum-picker adapter (root Tab / HpoRange keep their enums)

extension Binding where Value == Int {
    /// Bridge an enum selection to SWSegmented's Int API.
    static func index<T: CaseIterable & Equatable>(of selection: Binding<T>) -> Binding<Int>
    where T.AllCases: RandomAccessCollection, T.AllCases.Index == Int {
        Binding<Int>(
            get: { T.allCases.firstIndex(of: selection.wrappedValue) ?? 0 },
            set: { selection.wrappedValue = T.allCases[$0] }
        )
    }
}
