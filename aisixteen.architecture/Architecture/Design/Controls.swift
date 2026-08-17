import SwiftUI

/// The filled capsule button, once.
///
/// The handoff spells this out at eight call sites with slightly different metrics each time —
/// the Direction CTA at 30/15, Result's Save at maxWidth/13, PauseCard's two buttons at 14/6, the
/// prompt chips at 11/5. Extracted so the 44 pt hit target is guaranteed rather than accidental:
/// the chips as written computed to about 26 pt tall.
struct PillButton: View {

    enum Role {
        /// The one action on the screen. Accent capsule, white label — and it drains during a run.
        case primary
        /// A committing action that is not the primary one. Ink capsule.
        case ink
        /// Low emphasis. A barely-there fill.
        case quiet
        /// Sits over a photo, so it needs the glass to stay legible.
        case glass
    }

    let title: String
    var role: Role = .primary
    var fillWidth: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(\.accentDrained) private var drained

    var body: some View {
        Button(action: action) {
            Text(title)
                .arcText(.cta)
                .foregroundStyle(labelColor)
                .frame(maxWidth: fillWidth ? .infinity : nil)
                .padding(.horizontal, fillWidth ? ARC.Space.grid : ARC.Space.wide)
                // The board gives the PRIMARY capsule its own height (52), taller than the 44 pt
                // accessibility floor the other roles sit at. The token existed and nothing read
                // it, so every button was the floor height and the primary action did not read as
                // primary.
                .frame(minHeight: role == .primary ? ARC.primaryCapsuleHeight : ARC.minimumHitTarget)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(background)
        .opacity(isEnabled ? 1 : 0.45)
        .disabled(!isEnabled)
        .animation(.easeInOut(duration: 0.45), value: drained)
    }

    private var labelColor: Color {
        switch role {
        case .primary, .ink: return .white
        case .quiet, .glass: return ARC.ink
        }
    }

    @ViewBuilder private var background: some View {
        switch role {
        case .primary: Capsule().fill(ARC.accent(drained: drained))
        case .ink: Capsule().fill(ARC.ink)
        case .quiet: Capsule().fill(Color.black.opacity(0.07))
        case .glass: Color.clear.arcGlassCapsule(.interactive)
        }
    }
}

/// A one-tap prompt addition. Reads as a chip, but is a real 44 pt target.
struct PromptChipButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .arcText(.caption)
                .foregroundStyle(ARC.ink.opacity(0.85))
                .padding(.horizontal, ARC.Space.gap)
                // The visible pill stays small; the tappable area does not.
                .frame(minHeight: 30)
                .background(Capsule().fill(Color.black.opacity(0.06)))
                .frame(minHeight: ARC.minimumHitTarget)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The floating glass segment. `RootView.segment` and `CaptureView.modePicker` are the same code
/// twice in the handoff, differing only in their labels; the Mac and iPad shells want a third.
struct GlassSegment<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    /// `<area>.<thing>`, applied to each option's leaf — never to the container. On macOS an
    /// identifier on a bare container is a silent no-op, and one on a container that DOES have an
    /// accessibility element overwrites its children's.
    let identifier: (Value) -> String
    var accessibilityLabel: String

    @Namespace private var pill
    @Environment(\.arcAccessibility) private var accessibility

    var body: some View {
        HStack(spacing: ARC.Space.hair) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(ARCMotion.morph(reduceMotion: accessibility.reduceMotion)) {
                        selection = option
                    }
                } label: {
                    Text(title(option))
                        .arcText(.subheading)
                        .foregroundStyle(option == selection ? Color.white : ARC.ink)
                        .padding(.horizontal, ARC.Space.grid)
                        .frame(minHeight: ARC.minimumHitTarget)
                        .background {
                            if option == selection {
                                Capsule()
                                    .fill(ARC.ink)
                                    .matchedGeometryEffect(id: "segmentPill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(identifier(option))
                .accessibilityAddTraits(option == selection ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(ARC.Space.hair)
        .arcGlassCapsule()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// A glass capsule with a status dot: the capture coach line, the depth badge, the Mac queue rows.
struct StatusCapsule: View {
    enum Tone { case good, caution, neutral }

    let tone: Tone
    let text: String
    var identifier: String?

    var body: some View {
        HStack(spacing: ARC.Space.tight) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(text)
                .arcText(.secondary)
                .foregroundStyle(ARC.ink)
        }
        .padding(.horizontal, ARC.Space.grid)
        .frame(minHeight: 34)
        .arcGlassCapsule(shadow: false)
        // `.combine` makes the dot and the words one utterance — which they are — but on macOS
        // `.combine` destroys the children's identifiers and synthesises a joined one, so the
        // result must be named explicitly.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier ?? "status.capsule")
        .accessibilityLabel(text)
    }

    private var dotColor: Color {
        switch tone {
        case .good: return ARC.good
        case .caution: return ARC.caution
        case .neutral: return ARC.neutral
        }
    }
}

/// The accent-or-hairline selection border: preset cards, variant strip, library tiles, Mac rows.
struct SelectionBorder: View {
    let isSelected: Bool
    var radius: CGFloat = ARC.Radius.preset

    @Environment(\.accentDrained) private var drained

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(isSelected ? ARC.accent(drained: drained) : Color.black.opacity(0.12),
                          lineWidth: isSelected ? 2.5 : 1)
            .allowsHitTesting(false)
    }
}

/// The dashed "+" tile: "New variation", "New variation for Living room".
struct AddTile: View {
    let label: String
    var width: CGFloat?
    var height: CGFloat
    var identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: ARC.Radius.tile, style: .continuous)
                .strokeBorder(ARC.ink.opacity(0.22),
                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(ARC.ink.opacity(0.5))
                }
                .frame(width: width, height: height)
                .frame(minWidth: ARC.minimumHitTarget, minHeight: ARC.minimumHitTarget)
                .contentShape(RoundedRectangle(cornerRadius: ARC.Radius.tile))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }
}
