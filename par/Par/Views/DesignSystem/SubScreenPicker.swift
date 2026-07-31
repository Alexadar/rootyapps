import SwiftUI

/// Segmented picker for sub-screens and for conventions.
///
/// Selected state is carried on TWO channels — an amber ring and amber ink —
/// rather than a brighter grey fill. Amber *fill* stays reserved for actions
/// (primary buttons, the Solve key) so a toggle never reads as a button.
public struct SubScreenPicker<Value: Hashable>: View {
    private let options: [(value: Value, title: String)]
    @Binding private var selection: Value
    private let identifier: String

    public init(options: [(value: Value, title: String)], selection: Binding<Value>, identifier: String) {
        self.options = options
        self._selection = selection
        self.identifier = identifier
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options, id: \.value) { option in
                    let isSelected = option.value == selection
                    Button { selection = option.value } label: {
                        Text(option.title)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Par.Palette.accent : Par.Palette.label)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .frame(minHeight: Par.Metrics.minHitTarget)
                            .background(
                                RoundedRectangle(cornerRadius: Par.Metrics.controlRadius, style: .continuous)
                                    .fill(isSelected ? Par.Palette.accentTint : Par.Palette.surfaceRaised.opacity(0.55))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Par.Metrics.controlRadius, style: .continuous)
                                    .strokeBorder(isSelected ? Par.Palette.accent : .clear, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(identifier).\(option.title)")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, Par.Metrics.gutter)
        }
        // `.contain`, not bare. An identifier on a container with no `accessibilityElement` is a
        // silent no-op on macOS, while on iOS it overwrites the identifiers of the segment Buttons
        // beneath it — so `tool.picker.Bond` and its nine siblings become unaddressable on one
        // platform and `tool.picker.strip` does not exist on the other. `.contain` publishes the
        // strip without swallowing its children. Both are needed: the segments for taps, the strip
        // because ten tools do not fit across a phone and a tour has to scroll it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifier).strip")
    }
}
