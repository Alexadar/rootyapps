import DirectionKit
import SwiftUI

/// Direction — presets seed an editable prompt, and the CTA is priced in minutes.
///
/// The most production-shaped screen in the handoff: the composition, the metrics and the copy are
/// kept. What changed is that the data is real — `mode` comes from the shot, the photo header is
/// the photo, and the CTA does something.
struct DirectionView: View {

    @Bindable var model: DirectionModel
    var layout: SheetSurface<AnyView>.Layout = .sheet
    let onRetake: () -> Void
    let onStart: () -> Void

    var body: some View {
        switch layout {
        case .sheet:
            VStack(spacing: 0) {
                photoHeader
                    .frame(height: 190)
                SheetSurface(layout: .sheet) { AnyView(controls) }
            }
            .background(ARC.canvas)
        case .rail:
            // iPad and Mac: the photo fills and the controls sit beside it, so the thing being
            // redesigned is never covered by the controls that redesign it.
            HStack(spacing: 0) {
                photoHeader
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                SheetSurface(layout: .rail) { AnyView(ScrollView { controls }) }
            }
            .background(ARC.canvas)
        }
    }

    // ── the photo ────────────────────────────────────────────────────────────────────────────

    private var photoHeader: some View {
        ShotImage(shot: model.shot)
            .accessibilityIdentifier("direction.photo")
            .accessibilityLabel("The photo you took")
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: ARC.Space.gap) {
                    StatusCapsule(tone: model.depthIsMeasured ? .good : .neutral,
                                  text: model.depthBadge,
                                  identifier: "direction.depth")
                    Spacer()
                    Button("Retake", action: onRetake)
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("direction.retake")
                }
                .padding(ARC.Space.grid)
                .padding(.bottom, layout == .sheet ? ARC.Radius.sheet - 8 : 0)
            }
    }

    // ── the controls ─────────────────────────────────────────────────────────────────────────

    @ViewBuilder private var controls: some View {
        VStack(spacing: ARC.Space.grid) {
            presetGrid
            promptField
            variationRow
            cta
        }
    }

    private var presetGrid: some View {
        ReflowingGrid(spacing: ARC.Space.gap) {
            ForEach(model.presets) { preset in
                PresetCard(preset: preset,
                           isSelected: preset.id == model.selectedPresetID) {
                    model.select(preset)
                }
            }
        }
    }

    private var promptField: some View {
        SheetCard {
            VStack(alignment: .leading, spacing: ARC.Space.tight) {
                HStack {
                    Text("IN YOUR WORDS — OPTIONAL")
                        .arcText(.label)
                        .foregroundStyle(ARC.ink.opacity(0.5))
                    Spacer()
                    // The one line of undo a destructive re-pick earns. Silently discarding what
                    // somebody typed is not acceptable; neither is keeping stale words under a new
                    // preset name.
                    if model.undo != nil {
                        Button("Undo") { model.undoRepick() }
                            .arcText(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(ARC.accent)
                            .accessibilityIdentifier("direction.undo")
                    }
                }

                TextField("Describe the redesign",
                          text: Binding(get: { model.prompt }, set: { model.edit($0) }),
                          axis: .vertical)
                    .textFieldStyle(.plain)
                    .arcText(.body)
                    .lineLimit(1...4)
                    .accessibilityIdentifier("direction.prompt")

                if !model.availableChips.isEmpty {
                    HStack(spacing: ARC.Space.tight) {
                        ForEach(Array(model.availableChips.enumerated()), id: \.element) { index, chip in
                            PromptChipButton(label: chip.label) { model.append(chip) }
                                .accessibilityIdentifier("direction.chip.\(index)")
                        }
                    }
                }
            }
        }
    }

    private var variationRow: some View {
        SheetCard(fill: 0.85) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.variationLine)
                        .arcText(.subheading)
                        .accessibilityIdentifier("direction.variations.value")
                    Text(model.eachLine)
                        .arcText(.caption)
                        .foregroundStyle(ARC.ink.opacity(0.55))
                }
                Spacer()
                Stepper("", value: $model.variations, in: 1...5)
                    .labelsHidden()
                    .accessibilityIdentifier("direction.variations.stepper")
                    .accessibilityLabel("Number of variations")
            }
        }
    }

    private var cta: some View {
        VStack(spacing: ARC.Space.tight) {
            PillButton(title: model.ctaTitle,
                       role: .primary,
                       fillWidth: true,
                       isEnabled: model.canStart,
                       action: onStart)
                .accessibilityIdentifier("direction.cta")
                .accessibilityHint("Starts \(model.variationLine), \(model.eachLine). You can leave the app while it works.")
        }
    }
}

/// A preset card: swatch strip, name, palette line.
private struct PresetCard: View {
    let preset: StylePreset
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.arcAccessibility) private var accessibility

    var body: some View {
        Button {
            withAnimation(ARCMotion.morph(reduceMotion: accessibility.reduceMotion)) { action() }
        } label: {
            VStack(alignment: .leading, spacing: ARC.Space.tight) {
                swatches
                Text(preset.name)
                    .arcText(.subheading)
                    .foregroundStyle(ARC.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(preset.sub)
                    .arcText(.micro)
                    .foregroundStyle(ARC.ink.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background {
                RoundedRectangle(cornerRadius: ARC.Radius.preset, style: .continuous)
                    .fill(.white)
            }
            .overlay { SelectionBorder(isSelected: isSelected) }
            .contentShape(RoundedRectangle(cornerRadius: ARC.Radius.preset))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("direction.preset.\(preset.id)")
        .accessibilityLabel("\(preset.name). \(preset.sub)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var swatches: some View {
        HStack(spacing: 3) {
            ForEach(Array(preset.swatchHexes.enumerated()), id: \.offset) { index, hex in
                Color(hex: hex)
                    .frame(maxWidth: index == 0 ? .infinity : 24)
            }
        }
        .frame(height: 30)
        .clipShape(RoundedRectangle(cornerRadius: ARC.Radius.swatch, style: .continuous))
    }
}

/// The source photo, decoded at a sane size.
struct ShotImage: View {
    let shot: SourceShot

    var body: some View {
        Group {
            if let image = decoded {
                Image(platform: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Color(hex: 0xB3A288), Color(hex: 0x75604A)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .fillAndClip()
    }

    private var decoded: PlatformImage? {
        #if os(iOS)
        UIImage(data: shot.imageData)
        #else
        NSImage(data: shot.imageData)
        #endif
    }
}
