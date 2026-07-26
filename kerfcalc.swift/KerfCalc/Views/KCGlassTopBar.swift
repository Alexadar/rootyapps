import SwiftUI

/// A floating **Liquid Glass** top bar (iOS/macOS 26). Pinned via `.safeAreaInset(edge: .top)`, its
/// translucent `.glassEffect` chrome lets the scrolled content refract through it — the modern 2026
/// transparent app bar — while the HUD cards below stay flat/matte. A hairline seats it on the paper.
/// The screens with a *custom* header (Spec · Formulas) use this; Reference and the tool detail ride
/// the system navigation bar, which is already Liquid Glass in 26.
struct KCGlassTopBar<Content: View>: View {
    var spacing: CGFloat = 11
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .background {
                Color.clear
                    .glassEffect(.regular, in: Rectangle())
                    .ignoresSafeArea(edges: .top)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(KC.hairline).frame(height: 1) }
    }
}
