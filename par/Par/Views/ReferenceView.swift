import SwiftUI

/// What Par computes from, and where it is known to disagree with a published table.
///
/// `ProvenanceStrip` already names the authority on every screen. This is where the things that do
/// not fit on a strip live — the sign convention, and the two places where Par's arithmetic and a
/// printed IRS column differ. Those are stated here rather than buried in a repository file,
/// because the whole claim of the app is that its numbers can be checked; an app that hid its own
/// known discrepancies would be making a weaker claim than it prints on every screen.
struct ReferenceView: View {
    private let onClose: (() -> Void)?

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Reference")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Par.Palette.label)
                    Text("Sources, conventions, and known discrepancies")
                        .font(.caption)
                        .foregroundStyle(Par.Palette.labelSecondary)
                }
                Spacer()
                if let onClose {
                    Button("Done", action: onClose)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Par.Palette.accent)
                        .accessibilityIdentifier("reference.done")
                }
            }
            .padding(.horizontal, Par.Metrics.gutter)
            .padding(.vertical, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Sign convention", [
                        Item("Money out is negative", "A payment you make is a negative number; money you receive is positive. A mortgage entered as a positive present value therefore solves to a negative payment."),
                    ])

                    section("What each screen computes from", [
                        Item("Time value of money", "31 CFR 356 Appendix B §II.A · 12 CFR 1030 Appendix A"),
                        Item("Amortization", "Interest accrues on the balance outstanding at the start of the period."),
                        Item("Cash flow", "NPV and IRR over grouped flows. Where no rate balances the flows, or where more than one does, Par says so rather than returning the first root it finds."),
                        Item("Bond", "31 CFR 356 Appendix B — price, accrued interest and invoice price, including the simple stub factor for an irregular first period."),
                        Item("Rate and APR", "12 CFR 1026 Appendix J (APR) · 12 CFR 1030 Appendix A (APY)"),
                        Item("Depreciation", "IRS Publication 946 Appendix A. Each year is rounded and the rounded figure reduces the basis, which is how the published tables are built."),
                        Item("Dates and day count", "2006 ISDA Definitions §4.16"),
                        Item("Statistics", "NIST/ITL Statistical Reference Datasets"),
                        Item("Real estate", "NOI, cap rate, and loan sizing by the binding constraint of DSCR and LTV."),
                    ])

                    section("Known discrepancies", [
                        Item("MACRS tables — 28 of 30 columns match digit for digit",
                             "Two columns of Publication 946 Appendix A differ from Par by one unit in the last published place, with the difference carried to a later year so the column still totals 100.00%.\n\n• Table A-2 (mid-quarter, Q1), 20-year: year 2 published 7.000, Par 7.008; year 21 published 0.565, Par 0.557.\n• Table A-3 (mid-quarter, Q2), 7-year: year 1 published 17.85, Par 17.86; year 8 published 3.34, Par 3.33.\n\nThe A-3 case is the clearer one: 2/7 × 0.625 = 17.857142…, which rounds to 17.86 by any ordinary rule, and the same table's 3-year column (41.666… → 41.67) shows the IRS rounds rather than truncates. Par prints its own arithmetic and records the difference here rather than reproducing a figure it cannot derive."),
                        Item("Real estate loan sizing has no published oracle",
                             "Maximum loan by debt service coverage is checked for internal consistency, not against a published worked example. A HUD MAP guide or agency multifamily term sheet would settle it; one was sought on 2026-07-27 and not obtained."),
                    ])

                    section("What Par does not do", [
                        Item("No network, no account, no analytics", "Nothing is sent anywhere. There is no sign-in and no telemetry."),
                        Item("One purchase", "No subscription, no advertising, no in-app purchases, and no tools withheld behind a tier."),
                    ])
                }
                .padding(.horizontal, Par.Metrics.gutter)
                .padding(.bottom, 28)
            }
        }
        .background(Par.Palette.base)
    }

    private struct Item: Identifiable {
        let id = UUID()
        let title: String
        let body: String
        init(_ title: String, _ body: String) {
            self.title = title
            self.body = body
        }
    }

    private func section(_ heading: String, _ items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(Par.Palette.accent)
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Par.Palette.label)
                    Text(item.body)
                        .font(.footnote)
                        .foregroundStyle(Par.Palette.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Par.Palette.surface,
                            in: RoundedRectangle(cornerRadius: Par.Metrics.rowRadius, style: .continuous))
            }
        }
    }
}

#Preview("Reference — dark") {
    ReferenceView(onClose: {}).parAppearance()
}

#Preview("Reference — AX5") {
    ReferenceView(onClose: {})
        .environment(\.dynamicTypeSize, .accessibility5)
        .parAppearance()
}
