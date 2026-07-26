import SwiftUI
import SpaceWeatherFeed

// Replaces Views/Components.swift. Same call sites; restyled, theme-aware internals.

/// A panel container: chamfered HUD card with a ticked header that always cites its
/// data source and shows how old the underlying observation is.
struct Panel<Content: View>: View {
    let title: String
    let source: String
    var observedAt: Date? = nil
    /// Which feed this panel came from, so the badge can separate "the source publishes slowly"
    /// from "our fetch of THIS source failed" — they looked identical before.
    var feed: FeedSource? = nil
    var status: FeedStatus? = nil
    var highlighted: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelHeader(title: title, source: source)
            content
            if observedAt != nil || feed != nil {
                StaleBadge(observedAt: observedAt, feed: feed, status: status)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .swCard(highlighted: highlighted)
    }
}

/// Data-age line. Shows how old the OBSERVATION is, judged against that source's own publishing
/// cadence — a flat threshold marked F10.7 stale permanently and Hp30 never. When our last fetch
/// of the source failed or was skipped it says so instead, because a panel frozen by a dead feed
/// used to be indistinguishable from one whose publisher is simply slow.
struct StaleBadge: View {
    @Environment(\.sw) private var sw
    let observedAt: Date?
    var feed: FeedSource? = nil
    var status: FeedStatus? = nil

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption2)
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .tracking(0.6)
        }
        .foregroundStyle(warn ? sw.caution : sw.textTertiary)
    }

    private var fetchOutcome: FetchOutcome? {
        guard let feed, let status, status.didFail(feed) else { return nil }
        return status[feed].outcome
    }

    private var stale: Bool {
        guard let feed, let status else { return Fmt.isStale(observedAt) }
        return status.isStale(feed)
    }

    private var warn: Bool { fetchOutcome != nil || stale }

    private var icon: String {
        switch fetchOutcome {
        case .skippedOffline:  return "wifi.slash"
        case .skippedCellular: return "antenna.radiowaves.left.and.right.slash"
        case .failed, .empty:  return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .ok, .none:       return stale ? "exclamationmark.triangle.fill" : "clock"
        }
    }

    private var label: String {
        switch fetchOutcome {
        case .skippedOffline:  return "OFFLINE · SHOWING LAST KNOWN"
        case .skippedCellular: return "PAUSED ON CELLULAR · \(Fmt.age(observedAt).uppercased())"
        case .failed, .empty:  return "COULDN'T REFRESH · \(Fmt.age(observedAt).uppercased())"
        case .ok, .none:       return "UPDATED \(Fmt.age(observedAt).uppercased())"
        }
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
