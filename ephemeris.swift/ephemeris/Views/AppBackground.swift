import SwiftUI

/// Deep celestial backdrop that lets the Liquid Glass cards read clearly.
struct AppBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(rgbHex: 0x0B1020), Color(rgbHex: 0x1A1330)],
                       startPoint: .top, endPoint: .bottom)
            .overlay(
                RadialGradient(colors: [Color(rgbHex: 0x2A2D6B).opacity(0.45), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 600)
            )
            .ignoresSafeArea()
    }
}
