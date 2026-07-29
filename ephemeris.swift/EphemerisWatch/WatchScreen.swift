import SwiftUI
import EphemerisKit

/// The screens, plus the list that reaches them.
///
/// Two states at a time — the list, or one screen. There is deliberately **no paging between
/// screens**, following what OverTone Lab learned on the wrist: a paging TabView drives itself
/// with the Digital Crown, so a turn meant to scrub time would leave the page instead. On the one
/// screen where the Crown is the entire point, that is fatal. Removing paging hands the Crown
/// back to the wheel, which is the only thing it should ever have driven here.
enum WatchScreen: String, CaseIterable, Identifiable {
    case wheel, now, positions, events
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .wheel:     "Chart"
        case .now:       "Now"
        case .positions: "Positions"
        case .events:    "Events"
        }
    }

    var symbol: String {
        switch self {
        case .wheel:     "circle.hexagongrid"
        case .now:       "sparkles"
        case .positions: "list.star"
        case .events:    "calendar"
        }
    }

    var accent: Color {
        switch self {
        case .wheel:     Color(rgbHex: 0xFF4D9D)
        case .now:       Color(rgbHex: 0x35E7FF)
        case .positions: Color(rgbHex: 0xC061FF)
        case .events:    Color(rgbHex: 0x4DF0A0)
        }
    }
}

/// The catalog. One tap from anywhere, because from the Events screen the alternative is swiping
/// past everything else to get home.
struct WatchScreenList: View {
    @Binding var screen: WatchScreen?

    var body: some View {
        NavigationStack {
            List(WatchScreen.allCases) { s in
                Button { withAnimation(.snappy) { screen = s } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: s.symbol)
                            .foregroundStyle(s.accent)
                            .frame(width: 22)
                        Text(s.title)
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Ephemeris")
        }
    }
}

/// The header every screen wears. It *is* the way back — a plain title with a chevron reads as
/// decoration, so the exit is an obvious tinted disc at the size of a real tap target.
struct WatchScreenHeader: View {
    let screen: WatchScreen
    let onBack: () -> Void
    /// Optional trailing control, used by the wheel for its Crown-step badge.
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                HStack(spacing: 5) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(screen.accent)
                        .frame(width: 26, height: 26)
                        .background(screen.accent.opacity(0.18), in: .circle)
                    Text(screen.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("All screens"))

            Spacer(minLength: 2)
            if let trailing { trailing }
        }
    }
}
