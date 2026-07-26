import SwiftUI

/// Pill segmented control for a calculator's sub-screens — replaces `.pickerStyle(.segmented)`.
/// The selected pill fills with the current `.tint` (set to the calculator's section accent).
/// Drop-in for the existing `SubScreenPicker(titles:selection:)` API.
struct SubScreenPicker: View {
    @Environment(\.tc) private var tc
    let titles: [String]
    @Binding var selection: Int
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 3) {
            ForEach(titles.indices, id: \.self) { i in
                let selected = i == selection
                Text(titles[i])
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(tc.onAccent)
                                              : AnyShapeStyle(tc.textSecondary))
                    .frame(maxWidth: .infinity, minHeight: TC.minHit - 16)
                    .padding(.vertical, 8)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: TC.rChip + 2)
                                .fill(.tint)
                                .matchedGeometryEffect(id: "seg", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.22)) { selection = i }
                    }
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(tc.surface, in: .rect(cornerRadius: TC.rSegment))
        .overlay(
            RoundedRectangle(cornerRadius: TC.rSegment)
                .strokeBorder(tc.hairline, lineWidth: 1)
        )
    }
}
