import SwiftUI

/// One column on a phone, two on iPad/Mac. Without this the app is a phone column
/// stretched down the middle of a 13" iPad, leaving most of the screen empty.
///
/// Charts are the exception — they read better wide, so the geomagnetic view stays
/// single-column and simply gets more width.
struct PanelStack<Content: View>: View {
    #if os(macOS)
    private let wide = true
    #else
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var wide: Bool { sizeClass == .regular }
    #endif

    @ViewBuilder var content: Content

    var body: some View {
        if wide {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .top),
                                GridItem(.flexible(), spacing: 14, alignment: .top)],
                      spacing: 14) { content }
        } else {
            LazyVStack(spacing: 14) { content }
        }
    }
}

extension View {
    /// Content width: a comfortable reading column on a phone, wide enough for two
    /// panels side by side on iPad and Mac.
    func panelWidth(wide: Bool) -> some View {
        frame(maxWidth: wide ? 1180 : 640)
    }
}
