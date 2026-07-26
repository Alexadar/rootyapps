import SwiftUI

/// Pill segmented control for a tool's sub-screens — replaces `.pickerStyle(.segmented)`.
/// The selected pill fills with the current `.tint` (set to the tool's section accent).
/// Drop-in for the existing `SubScreenPicker(titles:selection:)` API.
struct SubScreenPicker: View {
    /// `LocalizedStringKey`, so `SubScreenPicker(titles: ["Note", "Tempo", …])` puts each literal
    /// in the catalog. Sub-screen names are the tightest text in the app — check German and
    /// Turkish on an iPhone before adding a fifth segment.
    let titles: [LocalizedStringKey]
    @Binding var selection: Int
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 3) {
            ForEach(titles.indices, id: \.self) { i in
                let selected = i == selection
                Text(titles[i])
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(OTL.onAccent)
                                              : AnyShapeStyle(OTL.textSecondary))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: OTL.rChip + 1)
                                .fill(.tint)
                                .matchedGeometryEffect(id: "seg", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.22)) { selection = i }
                    }
            }
        }
        .padding(3)
        .background(OTL.surface, in: .rect(cornerRadius: OTL.rSegment))
        .overlay(
            RoundedRectangle(cornerRadius: OTL.rSegment)
                .strokeBorder(OTL.hairline, lineWidth: 1)
        )
    }
}
