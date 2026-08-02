import SwiftUI

// Replaces KCTheme.swift's card + CardHeader + AppBackground.
// Keeps every call site: `something.card()`, `CardHeader(...)`, `AppBackground(...)`.
// Adds one signature component: `HeroReadout` — the dark instrument panel that holds
// the single hero number per screen.

extension View {
    /// Matte "paper" card — light surface, 1px hairline, radius 20, whisper shadow.
    /// - Parameter raised: the slightly warmer surface for a nested/raised card.
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
/// Pass the current tool's accent for a faint top wash on a detail screen.
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
/// never as tinted text on a light card. Corner ticks nod to a real tool bezel.
struct HeroReadout: View {
    let label: String
    let value: String
    var unit: String = ""

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
    }
}
