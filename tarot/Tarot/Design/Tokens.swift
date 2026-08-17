import SwiftUI

/// Design tokens. Dark, candle-lit, restrained — the chrome frames the game and stays out of
/// the cards' way (the one unrestrained thing on screen is a Major Arcana landing).
enum Tokens {
    // The void behind everything (matches the renderer's table).
    static let background = Color(red: 0.07, green: 0.06, blue: 0.09)
    static let gold = Color(red: 0.88, green: 0.72, blue: 0.35)
    static let ink = Color(red: 0.93, green: 0.90, blue: 0.84)
    static let inkDim = Color(red: 0.68, green: 0.65, blue: 0.62)
    static let glassTint = Color(red: 0.16, green: 0.13, blue: 0.22)

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    static func body(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }
    static func label(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .rounded) }
}
