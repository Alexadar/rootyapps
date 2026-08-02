import SwiftUI

/// Pill segmented control for a tool's sub-screens — drop-in for `SubScreenPicker(titles:selection:)`.
/// Selected pill fills graphite (the "active" language of the tab bar and keypad), with a 2px
/// section-accent underline. Set `.tint(tool.accent)` at screen level.
struct SubScreenPicker: View {
    let titles: [String]
    @Binding var selection: Int
    /// Test handle prefix, e.g. `mode` → `mode.seg.0`. Identifiers go on the leaf segments, never on
    /// the enclosing HStack: one on the container would overwrite all of the children's, and then no
    /// individual segment is addressable by a test or by VoiceOver.
    var identifier: String? = nil
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 3) {
            ForEach(titles.indices, id: \.self) { i in
                let selected = i == selection
                // The pill lives in `.background` rather than a ZStack: a bare RoundedRectangle is
                // vertically greedy, so in a short column (iPad's side-by-side inputs pane) it
                // stretched the whole control to the proposed height. As a background it takes the
                // padded label's size instead, while matchedGeometryEffect still animates the slide.
                Text(titles[i])
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(KC.onInstrument)
                                              : AnyShapeStyle(KC.textSecondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: KC.rChip + 1)
                                .fill(KC.instrument)
                                .matchedGeometryEffect(id: "seg", in: ns)
                                .overlay(alignment: .bottom) {
                                    Capsule().fill(.tint).frame(height: 2).padding(.horizontal, 14).padding(.bottom, 3)
                                }
                        }
                    }
                    .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.snappy(duration: 0.22)) { selection = i }
                }
                // These segments are Text + onTapGesture, NOT Buttons, so XCUITest sees static
                // texts with no traits — an identifier is the only reliable way to tap segment i.
                .accessibilityIdentifier("\(identifier ?? "seg").seg.\(i)")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(KC.surface, in: .rect(cornerRadius: KC.rSegment))
        .overlay(RoundedRectangle(cornerRadius: KC.rSegment).strokeBorder(KC.hairline, lineWidth: 1))
    }
}
