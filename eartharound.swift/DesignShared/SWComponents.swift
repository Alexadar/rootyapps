import SwiftUI

// Replaces Views/Components.swift. Same call sites; restyled, theme-aware internals.

/// A panel container: chamfered HUD card with a ticked header that always cites its
/// data source and shows how old the underlying observation is.
struct Panel<Content: View>: View {
    let title: String
    let source: String
    var observedAt: Date? = nil
    var highlighted: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(title: title, source: source)
            content
            if let observedAt {
                StaleBadge(observedAt: observedAt)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .swCard(highlighted: highlighted)
    }
}

/// Data-age line; turns caution-amber when the observation is stale.
struct StaleBadge: View {
    @Environment(\.sw) private var sw
    let observedAt: Date?
    var body: some View {
        let stale = Fmt.isStale(observedAt)
        HStack(spacing: 5) {
            Image(systemName: stale ? "exclamationmark.triangle.fill" : "clock")
                .font(.caption2)
            Text("UPDATED \(Fmt.age(observedAt).uppercased())")
                .font(.system(.caption2, design: .monospaced))
                .tracking(0.6)
        }
        .foregroundStyle(stale ? sw.caution : sw.textTertiary)
    }
}

/// A big scoreboard metric: mono tabular value + unit + label.
/// Default ink is `textPrimary`; pass a colour only when it is `sw.severity(…)`,
/// `sw.side(…)`, or `sw.brand` — never a per-metric hue.
struct MetricTile: View {
    @Environment(\.sw) private var sw
    let value: String
    var unit: String? = nil
    let caption: String
    var color: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(color ?? sw.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(sw.textSecondary)
                }
            }
            Text(caption.uppercased())
                .font(.system(size: 10, design: .monospaced).weight(.medium))
                .tracking(1.0)
                .foregroundStyle(sw.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption), \(value) \(unit ?? "")")
    }
}

/// A NOAA G/R/S scale chip. Level 0 is a neutral outlined chip — quiet is not an
/// event; levels 1+ fill with the severity ramp and dark ink.
struct ScaleChip: View {
    @Environment(\.sw) private var sw
    let label: String   // "G", "R", "S"
    let level: Int
    let name: String    // "Quiet", "Minor", …

    var body: some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(sw.textTertiary)
            Text(level > 0 ? "\(label)\(level)" : "0")
                .font(.system(.title3, design: .monospaced).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(level > 0 ? sw.onAccent : sw.textSecondary)
                .frame(width: 52, height: 40)
                .background {
                    if level > 0 {
                        ChamferBox(cut: 8, radius: SWM.rTile).fill(sw.severity(level))
                    } else {
                        ChamferBox(cut: 8, radius: SWM.rTile)
                            .strokeBorder(sw.hairline, lineWidth: 1)
                            .background(sw.chipFill, in: ChamferBox(cut: 8, radius: SWM.rTile))
                    }
                }
            Text(name.uppercased())
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(sw.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) scale, level \(level), \(name)")
    }
}

/// The "what this means" plain-language line under each panel. Prose is not a stat —
/// this stays SF Pro, sentence case.
struct MeaningLine: View {
    @Environment(\.sw) private var sw
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(sw.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small coupling/status flag. On-state fills with caution; off-state is outlined.
struct FlagPill: View {
    @Environment(\.sw) private var sw
    let text: String
    let on: Bool
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, design: .monospaced).weight(.semibold))
            .tracking(0.8)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .foregroundStyle(on ? sw.caution : sw.textTertiary)
            .background {
                if on {
                    ChamferBox(cut: 6, radius: SWM.rChip).fill(sw.caution.opacity(0.18))
                } else {
                    ChamferBox(cut: 6, radius: SWM.rChip).strokeBorder(sw.hairline, lineWidth: 1)
                }
            }
            .accessibilityLabel("\(text), \(on ? "active" : "inactive")")
    }
}
