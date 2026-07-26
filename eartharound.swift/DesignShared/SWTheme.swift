import SwiftUI

// Replaces DesignSystem/Theme.swift. Keeps every call site:
// `.swCard()`, `SpaceBackground()`, `PanelHeader(title:source:)`.

// MARK: - Chamfer shape (the identity)

/// Sharp card with a 45° chamfer on the top-trailing corner — the HUD signature.
struct ChamferBox: InsettableShape {
    var cut: CGFloat = SWM.chamfer
    var radius: CGFloat = SWM.rCard
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> ChamferBox {
        var s = self; s.insetAmount += amount; return s
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let c = min(cut, min(r.width, r.height) / 3)
        let rad = min(radius, c)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + rad, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))            // → chamfer start
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))            // 45° cut
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY),
                 tangent2End: CGPoint(x: r.maxX - rad, y: r.maxY), radius: rad)
        p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY),
                 tangent2End: CGPoint(x: r.minX, y: r.maxY - rad), radius: rad)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + rad))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY),
                 tangent2End: CGPoint(x: r.minX + rad, y: r.minY), radius: rad)
        p.closeSubpath()
        return p
    }
}

// MARK: - Card

extension View {
    /// Matte chamfered HUD card — the single card surface for every panel.
    /// Same signature as before; `cornerRadius` is kept for source compatibility and
    /// ignored (shape metrics live in `SWM`). `highlighted` uses the raised surface.
    func swCard(cornerRadius: CGFloat = 20, highlighted: Bool = false) -> some View {
        modifier(HudCard(highlighted: highlighted))
    }
}

private struct HudCard: ViewModifier {
    @Environment(\.sw) private var sw
    let highlighted: Bool
    func body(content: Content) -> some View {
        content
            .padding(SWM.cardPadding)
            .background(highlighted ? sw.surfaceRaised : sw.surface, in: ChamferBox())
            .overlay(ChamferBox().strokeBorder(sw.hairline, lineWidth: 1))
            .foregroundStyle(sw.textPrimary)
    }
}

// MARK: - Background

/// Flat matte arena background — no gradient wash, no stars, no glow… except an
/// optional faint side-accent bloom at the very top of a themed screen.
struct SpaceBackground: View {
    @Environment(\.sw) private var sw
    var accent: Color? = nil
    var body: some View {
        sw.background
            .overlay(alignment: .top) {
                if let accent {
                    RadialGradient(colors: [accent.opacity(0.08), .clear],
                                   center: .top, startRadius: 0, endRadius: 460)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
    }
}

// MARK: - Panel header

/// HUD panel header: `//` tick in the current tint, mono uppercased title, and the
/// mandatory data-source citation (the trust moat — never drop it).
struct PanelHeader: View {
    @Environment(\.sw) private var sw
    let title: String
    let source: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("//")
                .font(.system(.caption2, design: .monospaced).weight(.heavy))
                .foregroundStyle(.tint)   // set .tint(sw.side(panel.side)) at the panel
            Text(title.uppercased())
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(sw.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer()
            Text(source)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(sw.textTertiary)
                .lineLimit(1)
        }
    }
}

// MARK: - Section label

/// Mono, uppercased group header with a side-accent tick — for sidebars & grids.
struct SectionLabel: View {
    @Environment(\.sw) private var sw
    let title: String
    let accent: Color
    var body: some View {
        HStack(spacing: 8) {
            Text("//")
                .font(.system(.caption2, design: .monospaced).weight(.heavy))
                .foregroundStyle(accent)
            Text(title.uppercased())
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(sw.textSecondary)
        }
    }
}
