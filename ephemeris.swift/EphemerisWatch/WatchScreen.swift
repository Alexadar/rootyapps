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

/// Puts the way back into the top bar, beside the system clock.
///
/// watchOS keeps the clock top-right and leaves the left of that bar empty; every screen here
/// used to spend a row of its own height on a header instead. Moving it up reclaims that space —
/// which on a 176pt screen is the difference between a list showing four rows and five, and the
/// difference between the chart being centred and being pushed down.
///
/// A modifier rather than three copies: the screens differ only in tint, and a copied chrome is
/// how they start disagreeing about size and placement.
struct WatchScreenChrome: ViewModifier {
    let screen: WatchScreen
    let onBack: () -> Void

    func body(content: Content) -> some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(screen.title).font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(screen.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(L.loc("All screens")))
                    }
                }
        }
    }
}

extension View {
    func watchScreenChrome(_ screen: WatchScreen, onBack: @escaping () -> Void) -> some View {
        modifier(WatchScreenChrome(screen: screen, onBack: onBack))
    }
}
