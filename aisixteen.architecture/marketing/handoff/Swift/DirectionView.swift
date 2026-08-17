import SwiftUI

// Direction — presets are prompt macros: picking one writes a full prompt into
// the editable field. Photo check is folded into the header (depth badge + Retake).
// The CTA prices the wait in minutes before commitment.
struct DirectionView: View {
    let mode: SpaceMode = .interior
    @State private var selected: StylePreset = StylePreset.interior[0]
    @State private var prompt: String = StylePreset.interior[0].prompt
    @State private var variations = 3
    private let minutesPerVariation = 2

    var presets: [StylePreset] { mode == .interior ? StylePreset.interior : StylePreset.exterior }

    var body: some View {
        VStack(spacing: 0) {
            photoHeader
            GlassSheet {
                VStack(spacing: 14) {
                    presetGrid
                    promptField
                    variationRow
                    Button("Redesign · ~\(variations * minutesPerVariation) min total") {}
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 30).padding(.vertical, 15)
                        .background(Capsule().fill(DS.accent))
                        .accessibilityHint("Starts \(variations) variations, about \(minutesPerVariation) minutes each. You can leave the app while it works.")
                }
            }
            .offset(y: -DS.rSheet + 8)
        }
        .background(DS.canvas)
    }

    private var photoHeader: some View {
        ZStack(alignment: .bottomLeading) {
            CameraPreviewPlaceholder().frame(height: 190).clipped()
            HStack {
                HStack(spacing: 7) {
                    Circle().fill(DS.good).frame(width: 7, height: 7)
                    Text("Depth read — geometry will hold").font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .glassEffect(in: .capsule)
                Spacer()
                Button("Retake") {}.font(.caption.weight(.semibold)).buttonStyle(.glass)
            }
            .padding(16).padding(.bottom, DS.rSheet - 8)
        }
    }

    private var presetGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(presets) { p in
                Button {
                    withAnimation(DS.morph) { selected = p; prompt = p.prompt }
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 3) {
                            ForEach(Array(p.swatches.enumerated()), id: \.offset) { i, c in
                                Rectangle().fill(c).frame(maxWidth: i == 0 ? .infinity : nil)
                                    .frame(width: i == 0 ? nil : 24)
                            }
                        }
                        .frame(height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        Text(p.name).font(.subheadline.weight(.semibold)).foregroundStyle(DS.ink)
                        Text(p.sub).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(11)
                    .background(RoundedRectangle(cornerRadius: DS.rPreset).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: DS.rPreset)
                        .strokeBorder(selected == p ? DS.accent : Color.black.opacity(0.12),
                                      lineWidth: selected == p ? 2.5 : 1))
                }
                .accessibilityLabel("\(p.name). \(p.sub)")
                .accessibilityAddTraits(selected == p ? .isSelected : [])
            }
        }
    }

    private var promptField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("IN YOUR WORDS — OPTIONAL").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            TextField("Describe the redesign", text: $prompt, axis: .vertical)
                .font(.subheadline)
            HStack(spacing: 6) {
                ForEach(["+ warmer light", "+ more plants", "+ darker floor"], id: \.self) { chip in
                    Button(chip) { prompt += ", " + chip.dropFirst(2) }
                        .font(.caption).foregroundStyle(DS.ink)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.06)))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: DS.rPreset).fill(.white.opacity(0.9)))
    }

    private var variationRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(variations) variations").font(.subheadline.weight(.semibold))
                Text("about \(minutesPerVariation) min each · run one after another")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Stepper("", value: $variations, in: 1...5).labelsHidden()
                .accessibilityLabel("Number of variations")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: DS.rPreset).fill(.white.opacity(0.85)))
    }
}
