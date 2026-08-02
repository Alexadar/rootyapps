import SwiftUI
import SpaceWeatherFeed

// Replaces Views/Components.swift. Same call sites; restyled, theme-aware internals.

/// A panel container: chamfered HUD card with a ticked header that always cites its
/// data source and shows how old the underlying observation is.
struct Panel<Content: View>: View {
    /// Stable query handle — the `SWPanel` case, so it matches the scroll-target identity already
    /// used for deep links. Declared FIRST, like `MetricTile.id`, so every call site reads
    /// `Panel(id: "kp", title: …)`. Defaults to empty for the one panel that is not catalogued.
    var id: String = ""
    let title: String.LocalizationValue
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
        // `.contain`, NOT `.combine`: the panel must stay a container so the MetricTiles inside it
        // remain individually addressable. `.combine` here would fuse a whole card into one blob —
        // for VoiceOver as well as for tests. An identifier on a bare container with no
        // accessibilityElement modifier is a silent no-op on macOS, so the modifier is required.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id.isEmpty ? "panel" : "panel.\(id)")
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
            Text(SWText.str(label))
                .textCase(.uppercase)
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

    /// Uppercasing happens via `.textCase(.uppercase)` on the Text, not `.uppercased()` — the
    /// latter ignores the locale and turns a Turkish "i" into "İ".
    ///
    /// This reports the AGE OF THE DATA, not when we last polled. Our poll time is not the
    /// question a space-weather reading raises — how old the measurement is, is.
    private var label: String.LocalizationValue {
        let age = Fmt.age(observedAt)
        switch fetchOutcome {
        case .skippedOffline:  return "Offline · showing last known"
        case .skippedCellular: return "Paused on cellular · \(age)"
        case .failed, .empty:  return "Couldn't refresh · \(age)"
        case .ok, .none:       return "Observed \(age)"
        }
    }
}

/// A big scoreboard metric: mono tabular value + unit + label.
/// Default ink is `textPrimary`; pass a colour only when it is `sw.severity(…)`,
/// `sw.side(…)`, or `sw.brand` — never a per-metric hue.
struct MetricTile: View {
    @Environment(\.sw) private var sw
    /// Stable, NEVER-localized query handle, e.g. `kp.now`. Declared FIRST and required, not
    /// optional: this is the one component that renders every number in the app, and without an
    /// identifier not a single value is addressable by a test or reachable as a distinct element by
    /// VoiceOver. The caption is localized and uppercased, so it cannot serve as the handle.
    let id: String
    let value: String
    var unit: String? = nil
    let caption: String.LocalizationValue
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
            Text(SWText.str(caption))
                .textCase(.uppercase)
                .font(.system(size: 10, design: .monospaced).weight(.medium))
                .tracking(1.0)
                .foregroundStyle(sw.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // ONE `.combine`, then name the result. The modifier was applied twice — a copy-paste that
        // combined an already-combined element — and with no identifier `.combine` also means macOS
        // synthesises a joined identifier from the children, so the value was unaddressable on both
        // platforms. Combine + an explicit identifier is the sanctioned shape.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

/// A NOAA G/R/S scale chip. Level 0 is a neutral outlined chip — quiet is not an
/// event; levels 1+ fill with the severity ramp and dark ink.
struct ScaleChip: View {
    @Environment(\.sw) private var sw
    let label: String   // "G", "R", "S"
    let level: Int
    let name: String.LocalizationValue    // "Quiet", "Minor", …

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
            Text(SWText.str(name))
                .textCase(.uppercase)
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(sw.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(SWText.str("\(label) scale, level \(level)")))
        // The label above is a LOCALIZED sentence and it OVERRIDES the combined children, so the
        // code itself ("G1") was not exposed programmatically at all — unreadable in 18 of 19
        // languages by a test and by anything else reading the tree. The value carries the code
        // verbatim; the identifier is the locale-stable handle (scale.G / scale.R / scale.S).
        .accessibilityValue(Text(verbatim: level > 0 ? "\(label)\(level)" : "0"))
        .accessibilityIdentifier("scale.\(label)")
    }
}

/// The "what this means" plain-language line under each panel. Prose is not a stat —
/// this stays SF Pro, sentence case.
struct MeaningLine: View {
    @Environment(\.sw) private var sw
    let text: String.LocalizationValue
    init(_ text: String.LocalizationValue) { self.text = text }
    var body: some View {
        Text(SWText.str(text))
            .font(.footnote)
            .foregroundStyle(sw.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small coupling/status flag. On-state fills with caution; off-state is outlined.
struct FlagPill: View {
    @Environment(\.sw) private var sw
    /// Locale-stable handle; the visible text is localized and uppercased.
    let id: String
    let text: String.LocalizationValue
    let on: Bool
    var body: some View {
        Text(SWText.str(text))
            .textCase(.uppercase)
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
            .accessibilityValue(Text(on ? "active" : "inactive"))
            .accessibilityIdentifier(id)
    }
}
