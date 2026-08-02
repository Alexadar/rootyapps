import SwiftUI

/// Failure states are designed, not incidental. No solution, multiple IRRs and a
/// damaged tape line all take the hero's place rather than hiding in an alert.
public struct FailureNotice: View {
    private let title: String
    private let detail: String
    private let technical: String
    private let identifier: String
    private let isWarning: Bool

    public init(title: String, detail: String, technical: String,
                identifier: String, isWarning: Bool = false) {
        self.title = title
        self.detail = detail
        self.technical = technical
        self.identifier = identifier
        self.isWarning = isWarning
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: isWarning ? "exclamationmark.triangle" : "exclamationmark.circle")
                .font(.title3)
                .foregroundStyle(isWarning ? Par.Palette.warning : Par.Palette.label)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(Par.Palette.label)
                Text(detail).font(.subheadline).foregroundStyle(Par.Palette.labelSecondary)
                Text(technical).font(.caption2.monospaced()).foregroundStyle(Par.Palette.labelTertiary)
                    .padding(.top, 6)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// The multiple-IRR case gets its own presentation: both roots, side by side,
/// with the reason and a route forward. Neither root is "the" IRR.
public struct MultipleIRRNotice: View {
    private let roots: [Double]
    private let signChanges: Int

    public init(roots: [Double], signChanges: Int) {
        self.roots = roots
        self.signChanges = signChanges
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This loan has \(roots.count) internal rates of return")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Par.Palette.label)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) { rootCards }
                VStack(spacing: 9) { rootCards }
            }

            Text("\(signChanges) sign changes in the flows. Every root satisfies NPV = 0, so none of them is “the” IRR — use MIRR, or NPV at your own discount rate, to rank this deal.")
                .font(.subheadline)
                .foregroundStyle(Par.Palette.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("CashFlow.irr → .multiple · every root written to the tape line")
                .font(.caption2.monospaced())
                .foregroundStyle(Par.Palette.labelTertiary)
        }
        .padding(16)
        .glassCard()
        .accessibilityIdentifier("cashflow.hero.multipleIRR")
    }

    @ViewBuilder
    private var rootCards: some View {
        ForEach(Array(roots.enumerated()), id: \.offset) { index, root in
            VStack(alignment: .leading, spacing: 2) {
                Text("root \(index + 1)").font(.caption).foregroundStyle(Par.Palette.labelSecondary)
                Text(Fmt.percent(root * 100, digits: 3))
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Par.Palette.label)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassCard(radius: 16)
            .accessibilityIdentifier("cashflow.irr.root.\(index + 1)")
            .accessibilityLabel("Internal rate of return, root \(index + 1), \(Fmt.percent(root * 100))")
        }
    }
}

#Preview("Failure states") {
    ScrollView {
        VStack(spacing: 16) {
            FailureNotice(
                title: "No rate balances these cash flows",
                detail: "PV, PMT and FV are all the same sign, so the flows never change direction and no interest rate can make them balance. Give one of them the opposite sign — a loan is money in, its payments are money out.",
                technical: "TVM.SolveError.noSignChange · nothing was appended to the tape",
                identifier: "preview.noSignChange"
            )
            MultipleIRRNotice(roots: [0.04082, 0.31594], signChanges: 3)
            FailureNotice(
                title: "This line can’t be read back",
                detail: "Its stored inputs failed to decode — periods must be finite and ≥ 0. The rest of the tape is intact. Par will not guess a value, and it will not delete your line.",
                technical: "DecodingError surfaced, never trapped · nothing rewritten",
                identifier: "preview.damagedLine",
                isWarning: true
            )
        }
        .padding()
    }
    .background(Par.Palette.base)
    .parAppearance()
}
