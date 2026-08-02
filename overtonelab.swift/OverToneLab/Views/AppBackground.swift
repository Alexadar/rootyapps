import SwiftUI

/// Flat near-black studio surface, with an optional faint top glow in the tool's accent.
struct AppBackground: View {
    var accent: Color? = nil
    var body: some View {
        OTL.background
            .overlay(alignment: .top) {
                if let accent {
                    RadialGradient(colors: [accent.opacity(0.10), .clear],
                                   center: .top, startRadius: 0, endRadius: 420)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
    }
}
