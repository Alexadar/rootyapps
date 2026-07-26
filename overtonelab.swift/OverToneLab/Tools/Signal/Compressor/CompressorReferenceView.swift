import SwiftUI

struct CompressorReferenceView: View {
    var body: some View {
        VStack(spacing: 16) {
            card("Gain computer", "Above the threshold the compressor pulls level down by (x−T)·(1−1/R). A soft knee eases that curve in over its width; the effective ratio rises smoothly from 1:1 to the set ratio through the knee.")
            card("Attack & release", "Envelope timing is a one-pole smoother. A stated 10–90% rise time t maps to a time constant τ = t/ln9, and a coefficient α = exp(−1/(fs·τ)) — reaching 63.2% in one τ.")
            card("Static model", "This is the static curve plus a first-order envelope, per Giannoulis, Massberg & Reiss (2012). A real unit's detector, look-ahead and program dependence will differ.")
        }
    }
    private func card(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { CardHeader(title: L.loc(t)); Text(b).font(.callout).foregroundStyle(.secondary) }.glassCard()
    }
}
