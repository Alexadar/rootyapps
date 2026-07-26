import SwiftUI

struct RoomModesReferenceView: View {
    var body: some View {
        VStack(spacing: 16) {
            card("Room modes", "Standing waves at f = (c/2)·√((nx/L)² + (ny/W)² + (nz/H)²). Axial (one index) are strongest, then tangential (two), then oblique (three).")
            card("Even spacing wins", "Closely-spaced or coincident modes cause boomy peaks and nulls. Aim for even spacing; the Bonello criterion checks that mode counts rise smoothly by third-octave.")
            card("Good proportions", "Avoid cubes and integer-multiple dimensions. Sepmeyer and Louden published ratios (e.g. 1 : 1.4 : 1.9) that spread modes well.")
        }
    }
    private func card(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { CardHeader(title: t); Text(b).font(.callout).foregroundStyle(.secondary) }.glassCard()
    }
}
