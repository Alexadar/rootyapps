import SwiftUI

// Replaces Theme.swift + AppBackground.swift. Keeps every call site: `something.instrumentCard()`.
// (If the app's shared component is named `.glassCard()`, keep that name — just swap the body.)

extension View {
    /// Matte "instrument" card — flat surface, hairline stroke, no glass.
    /// - Parameter raised: use the slightly lighter readout surface for the result card.
    func instrumentCard(cornerRadius: CGFloat = TC.rCard, raised: Bool = false) -> some View {
        modifier(InstrumentCard(cornerRadius: cornerRadius, raised: raised))
    }
}

private struct InstrumentCard: ViewModifier {
    @Environment(\.tc) private var tc
    let cornerRadius: CGFloat
    let raised: Bool
    func body(content: Content) -> some View {
        content
            .padding(TC.cardPadding)
            .background(raised ? tc.surfaceRaised : tc.surface,
                        in: .rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(tc.hairline, lineWidth: 1)
            )
    }
}

/// A result card with the section-accent rule down its leading edge.
/// Wrap the hero `ResultRow(emphasis:)` in this.
struct ResultCard<Content: View>: View {
    @Environment(\.tc) private var tc
    var accent: Color? = nil
    @ViewBuilder var content: Content
    var body: some View {
        content
            .instrumentCard(raised: true)
            .overlay(alignment: .leading) {
                if let accent {
                    Rectangle().fill(accent).frame(width: 3)
                        .clipShape(.rect(topLeadingRadius: TC.rCard, bottomLeadingRadius: TC.rCard))
                }
            }
    }
}

/// Small monospaced, uppercased section label inside a card.
struct CardHeader: View {
    @Environment(\.tc) private var tc
    let title: String
    var trailing: String? = nil
    /// Optional stable id for the trailing text (e.g. a pass/fail verdict) so a test can read it by
    /// identifier instead of its (screen-varying) string. Invisible — no layout/pixels change.
    var trailingID: String? = nil
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(tc.textTertiary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.tint)   // set .tint(calc.accent) at the screen level
                    .accessibilityIdentifier(trailingID ?? "")
            }
        }
    }
}

/// Flat cockpit background — matte, sunlight-legible.
/// Pass the current calculator's accent for a faint top glow on a detail screen.
struct AppBackground: View {
    @Environment(\.tc) private var tc
    var accent: Color? = nil
    var body: some View {
        tc.background
            .overlay(alignment: .top) {
                if let accent {
                    RadialGradient(colors: [accent.opacity(0.09), .clear],
                                   center: .top, startRadius: 0, endRadius: 460)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
    }
}

/// Monospaced, uppercased group header with an accent tick — for catalog & sidebars.
struct SectionLabel: View {
    @Environment(\.tc) private var tc
    let title: String
    let accent: Color
    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(accent).frame(width: 4, height: 12)
            Text(title.uppercased())
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(tc.textSecondary)
        }
    }
}
