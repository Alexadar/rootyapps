import SwiftUI

struct TimerToolView: View {
    var body: some View {
        AdaptiveStack(spacing: 16) {
            ClockCard().inputColumn()
            CountdownCard()
        }
    }
}

/// Live Zulu (UTC) and local clock.
private struct ClockCard: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Clock")
                ResultRow(label: "Zulu (UTC)", value: Self.z.string(from: now), emphasis: true)
                ResultRow(label: "Local", value: Self.l.string(from: now))
            }
            .instrumentCard()
        }
    }
    static let z: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss'Z'"; f.timeZone = TimeZone(identifier: "UTC"); return f
    }()
    static let l: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()
}

/// Count-down timer with alert-style zero.
private struct CountdownCard: View {
    @Environment(\.tc) private var tc
    @State private var durationMin = 5.0
    @State private var endDate: Date? = nil
    @State private var frozenRemaining: TimeInterval = 5 * 60

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = remainingSeconds(at: context.date)
            ResultCard(accent: tc.accent(.tools)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Count-down")
                    ResultRow(label: "Remaining",
                              value: format(remaining),
                              emphasis: true)
                        .foregroundStyle(remaining <= 0 && endDate != nil ? tc.warning : tc.textPrimary)
                    if endDate == nil {
                        NumberField(title: "Duration", value: $durationMin, unit: "min", range: Bounds.durationMin)
                    }
                    HStack(spacing: 10) {
                        Button(endDate == nil ? "Start" : "Stop") { toggle() }
                            .buttonStyle(.borderedProminent)
                        Button("Reset") { reset() }
                            .buttonStyle(.bordered)
                    }
                    .tint(tc.accent(.tools))
                }
            }
        }
    }

    private func remainingSeconds(at now: Date) -> TimeInterval {
        if let end = endDate { return max(0, end.timeIntervalSince(now)) }
        return frozenRemaining
    }
    private func toggle() {
        if endDate == nil {
            endDate = Date().addingTimeInterval(durationMin * 60)
        } else {
            frozenRemaining = max(0, endDate!.timeIntervalSinceNow)
            endDate = nil
        }
    }
    private func reset() {
        endDate = nil
        frozenRemaining = durationMin * 60
    }
    private func format(_ s: TimeInterval) -> String {
        let t = Int(s.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
