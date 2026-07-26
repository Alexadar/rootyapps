import SwiftUI

// watchOS reference — the input-light tools. One input via the Digital Crown, one hero
// readout. Same tokens (Dark / Night), same monospaced tabular figures; only the density
// changes. Adapt into the watch target's views.

struct WatchReadoutExample: View {
    @Environment(\.tc) private var tc
    @State private var oat: Double = 24        // set by the Digital Crown
    private let accent = TCPalette.dark.accent(.altitude)

    var body: some View {
        VStack(spacing: 0) {
            // top status label
            HStack {
                Text("DENSITY ALT")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(tc.accent(.altitude))
                Spacer()
                Text("9:41")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(tc.textTertiary)
            }

            Spacer()

            // hero readout
            VStack(spacing: 2) {
                Text("3,180")
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(tc.textPrimary)
                    .minimumScaleFactor(0.5)
                Text("ft")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(tc.textSecondary)
            }

            Spacer()

            // two compact inputs; the primary one is Crown-driven
            HStack(spacing: 7) {
                WatchStat(label: "OAT", value: "+\(Int(oat))°")
                WatchStat(label: "PA", value: "2,100")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppBackground())
        .focusable()
        .digitalCrownRotation($oat, from: -40, through: 50, by: 1,
                              sensitivity: .medium, isContinuous: false)
        .accessibilityLabel("Density altitude 3,180 feet")
    }
}

private struct WatchStat: View {
    @Environment(\.tc) private var tc
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(tc.textTertiary)
            Text(value)
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tc.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(tc.surfaceRaised, in: .rect(cornerRadius: 11))
    }
}
