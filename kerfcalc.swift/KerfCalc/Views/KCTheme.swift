import SwiftUI

// Card + CardHeader + AppBackground + HeroReadout.
// Keeps every call site: `something.card()`, `CardHeader(...)`, `AppBackground(...)`.
// The KC token set lives in KCColors.swift.

extension View {
    /// Matte "paper" card — light surface, 1px hairline, radius 20, whisper shadow.
    func card(cornerRadius: CGFloat = KC.rCard, raised: Bool = false) -> some View {
        self.padding(16)
            .background(raised ? KC.surfaceRaised : KC.surface,
                        in: .rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(KC.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
    }
}

/// Small monospaced, uppercased section label inside a card.
struct CardHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .tracking(1)
                .foregroundStyle(KC.textSecondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.tint)   // set .tint(tool.accent) at the screen level
            }
        }
    }
}

/// Flat "concrete paper" background — replaces the old near-black + amber glow.
struct AppBackground: View {
    var accent: Color? = nil
    var body: some View {
        KC.background
            .overlay(alignment: .top) {
                if let accent {
                    RadialGradient(colors: [accent.opacity(0.10), .clear],
                                   center: .top, startRadius: 0, endRadius: 420)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
    }
}

/// The one hero readout per screen: a dark graphite instrument panel with the
/// result in `signal`. This is where the hero number lives in the light theme —
/// never as tinted text on a light card.
struct HeroReadout: View {
    let label: String
    let value: String
    var unit: String = ""
    /// Test handle for the answer, e.g. `rafter.hero`. Goes on the value LEAF, never on the card:
    /// an identifier on a container overwrites its children's, and `.combine` makes macOS synthesise
    /// a joined identifier so the one you asked for does not exist at all.
    var identifier: String? = nil

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(label.uppercased())
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(KC.instrumentDim)
                Text(value)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .foregroundStyle(KC.signal)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .accessibilityIdentifier(identifier ?? "hero")
            }
            Spacer(minLength: 8)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundStyle(KC.instrumentDim)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KC.instrument, in: .rect(cornerRadius: KC.rCard))
        // `.contain`, NOT `.combine`: combining fuses label+value+unit into one element and macOS
        // then joins their identifiers, so the id above stops existing. `.contain` keeps each line
        // addressable on both platforms — and a VoiceOver user wants the number, not the tracking-
        // spaced caption, read first.
        .accessibilityElement(children: .contain)
    }
}
