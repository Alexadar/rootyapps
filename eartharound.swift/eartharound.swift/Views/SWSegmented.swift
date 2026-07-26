import SwiftUI

/// Chamfer-track segmented control — replaces every `.pickerStyle(.segmented)`.
/// The selected pill fills with the current `.tint` (set `.tint(sw.side(…))` or leave
/// the root's brand tint). Int-selection API, matching the skeleton contract:
///
///     SWSegmented(titles: ["Dashboard", "Geomagnetic"], selection: $tabIndex)
///
/// Enum adapters (root tabs, Hp30 range) are one computed Binding away — see
/// `RootView.example.swift`.
struct SWSegmented: View {
    @Environment(\.sw) private var sw
    let titles: [String]
    @Binding var selection: Int
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 3) {
            ForEach(titles.indices, id: \.self) { i in
                let selected = i == selection
                Text(titles[i].uppercased())
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(selected ? AnyShapeStyle(sw.onAccent)
                                              : AnyShapeStyle(sw.textSecondary))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: SWM.minHit - 16)
                    .padding(.vertical, 6)
                    .background {
                        if selected {
                            ChamferBox(cut: 7, radius: SWM.rSegment - 1)
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
        .background(sw.surface, in: ChamferBox(cut: 9, radius: SWM.rSegment))
        .overlay(ChamferBox(cut: 9, radius: SWM.rSegment).strokeBorder(sw.hairline, lineWidth: 1))
    }
}

// MARK: - Enum-picker adapter (root Tab / HpoRange keep their enums)

extension Binding where Value == Int {
    /// Bridge an enum selection to SWSegmented's Int API.
    static func index<T: CaseIterable & Equatable>(of selection: Binding<T>) -> Binding<Int>
    where T.AllCases: RandomAccessCollection, T.AllCases.Index == Int {
        Binding<Int>(
            get: { T.allCases.firstIndex(of: selection.wrappedValue) ?? 0 },
            set: { selection.wrappedValue = T.allCases[$0] }
        )
    }
}
