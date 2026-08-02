import SwiftUI

// REFERENCE ONLY — the watchOS readout for a future watch target, and the layout the
// widget family should follow (small widget ≈ the same composition, static).
//
// One hero value, its severity, two compact stats — same tokens, same mono figures.
// The Night theme follows the phone's ThemeStore choice via the shared app group.

struct WatchReadoutExample: View {
    @Environment(\.sw) private var sw

    // Live values come from the shared snapshot; hardcoded here for reference.
    private let kp = 5.3
    private let gScale = 1
    private let auroraPct = 45
    private let windKms = 620

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("//")
                    .font(.system(.caption2, design: .monospaced).weight(.heavy))
                    .foregroundStyle(sw.brand)
                Text("KP NOW")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(sw.textSecondary)
                Spacer()
                Text("G\(gScale)")
                    .font(.system(.caption2, design: .monospaced).weight(.heavy))
                    .foregroundStyle(sw.onAccent)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(sw.severity(gScale), in: ChamferBox(cut: 4, radius: 2))
            }

            Text(String(format: "%.1f", kp))
                .font(.system(size: 54, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(sw.severity(gScale))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityLabel("Planetary Kp, \(String(format: "%.1f", kp)), level G\(gScale)")

            HStack(spacing: 12) {
                stat(label: "AURORA", value: "\(auroraPct)%")
                stat(label: "WIND", value: "\(windKms)", unit: "KM/S")
            }
        }
        .padding(12)
        .background(sw.background)
    }

    private func stat(label: String, value: String, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, design: .monospaced).weight(.medium))
                .tracking(1.0)
                .foregroundStyle(sw.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.footnote, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(sw.textPrimary)
                if let unit {
                    Text(unit)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(sw.textTertiary)
                }
            }
        }
    }
}
