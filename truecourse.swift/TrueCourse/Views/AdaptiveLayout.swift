import SwiftUI

/// Whether the current size class should lay a tool's inputs and readout **side by side**.
/// True on regular width (iPad landscape, Mac, wide multitasking) and on landscape iPhone
/// (compact *height*); false on compact-portrait, where they stack. (DESIGN_GUIDELINES §7.)
private func layoutIsHorizontal(_ h: UserInterfaceSizeClass?, _ v: UserInterfaceSizeClass?) -> Bool {
    #if os(macOS)
    return true
    #else
    return h == .regular || v == .compact
    #endif
}

/// Lays its children horizontally when there's room (regular width / landscape), else vertically.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        if layoutIsHorizontal(hSize, vSize) {
            HStack(alignment: .top, spacing: spacing) { content }
        } else {
            VStack(spacing: spacing) { content }
        }
    }
}

extension View {
    /// Caps a card to the inputs-column width (~380 pt) when it sits beside the readout;
    /// full-width when the layout is stacked.
    func inputColumn() -> some View { modifier(InputColumn()) }
}

private struct InputColumn: ViewModifier {
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize
    func body(content: Content) -> some View {
        content.frame(maxWidth: layoutIsHorizontal(hSize, vSize) ? 380 : .infinity)
    }
}
