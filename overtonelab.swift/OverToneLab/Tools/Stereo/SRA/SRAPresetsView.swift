import SwiftUI
import StereoKit

struct SRAPresetsView: View {
    @ObservedObject var vm: SRAViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Standard techniques")
                ForEach(Stereo.presets, id: \.name) { preset in
                    Button { vm.apply(preset) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.name).foregroundStyle(OTL.textPrimary)
                                Text("\(preset.pattern.label) · \(Fmt.f(preset.micAngleDeg, 0))° · \(Fmt.f(preset.spacingCm, 0)) cm")
                                    .font(.caption).foregroundStyle(OTL.textSecondary)
                            }
                            Spacer()
                            Text("\(Fmt.f(vm.sra(for: preset), 0))°")
                                .font(.system(.callout, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }.glassCard()
            Text("Tap a technique to load it into the Array screen.")
                .font(.caption).foregroundStyle(OTL.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
