import SwiftUI

struct ThieleReferenceView: View {
    var body: some View {
        VStack(spacing: 16) {
            card("Thiele-Small", "Fs, Qts and Vas describe a driver's low-frequency behaviour. Every box calculation starts from them — take them from the datasheet or measure your own.")
            card("Sealed box", "Qtc = Qts·√(α+1), Fc = Fs·√(α+1), α = Vas/Vb. Smaller box → higher Qtc, tighter but shallower. 0.707 is maximally flat.")
            card("Vented box", "A tuned port (Helmholtz resonator) extends the low end. Port length sets the tuning Fb; longer/narrower lowers it. Length here includes the end correction.")
            card("Model caveat", "Idealised lumped-parameter theory. Real drivers, leakage, damping and port compression shift results — confirm a serious design in WinISD or by measurement.")
        }
    }
    private func card(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { CardHeader(title: t); Text(b).font(.callout).foregroundStyle(.secondary) }.glassCard()
    }
}
