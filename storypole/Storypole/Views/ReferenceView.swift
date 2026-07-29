import SwiftUI
import DimensionKit
import LumberKit

/// The moat, made visible.
///
/// Every number this app shows traces to a published authority; this screen is where the user can
/// see that. It is also where the board-foot CAUTION lives — the thing no other app states.
struct ReferenceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                entry(title: "Rounding — ties go to even",
                      body: """
                      A value exactly halfway between two marks rounds to the even neighbour, not \
                      always upward. NIST SP 811 §B.7.1: "the digit preceding the 5 is unchanged if \
                      it is even and increased by 1 if it is odd."

                      The lumber standard applies the same rule and proves it: a dressed 7-1/2" is \
                      190.5 mm exactly, and PS 20-20 Table 3 publishes 190 mm — not 191.

                      The trade's own convention, ties away from zero, is available in Settings and \
                      is labelled as such. It has no published authority.
                      """,
                      source: "NIST SP 811 §B.7.1 · NIST PS 20-20 App. B §B1")

                entry(title: "The inch is exact",
                      body: """
                      1 inch is exactly 25.4 mm, 1 foot exactly 0.3048 m, 1 yard exactly 0.9144 m. \
                      These are definitions, fixed in 1959, not measurements. Storypole holds them \
                      as exact fractions, so a conversion out and back returns the number you started \
                      with.
                      """,
                      source: "Federal Register doc. 59-5442, 24 FR 5348 (NBS, 1959)")

                entry(title: "Board feet use NOMINAL sizes",
                      body: """
                      A board foot is nominal thickness in inches × nominal width in feet × length in \
                      feet. A 2×4×8 is exactly 5⅓ board feet.

                      \(BoardFeet.cubicMetreCaution)

                      That is why Storypole will not convert board feet to cubic metres. It will \
                      compute a true volume from the dressed size instead, which is a real solid.
                      """,
                      source: "NIST PS 20-20 §2.2 and Appendix B")

                entry(title: "Why a 2×4 is 1½\" × 3½\"",
                      body: """
                      Lumber is named by its rough sawn size and sold after it is dressed. A nominal \
                      2×4 arrives at 1½" × 3½" dry — 65.6 % of the section you are billed for.

                      \(DressedSize.nominalDisclaimer)
                      """,
                      source: "NIST PS 20-20 Table 3 and §3.4.4")

                entry(title: "On-center spacing",
                      body: """
                      16" and 24" on center are published framing spacings. 19.2" is not — it is the \
                      8-foot sheet divided into five bays (96 ÷ 5), and Storypole labels it as \
                      derived rather than claiming a source it does not have.
                      """,
                      source: "USDA Agriculture Handbook 73, Wood-Frame House Construction")

                entry(title: "The US survey foot is deprecated",
                      body: """
                      The survey foot (1200/3937 m) differs from the international foot. It is \
                      offered only as a labelled legacy mode for historic survey data.

                      "Beginning on January 1, 2023, the U.S. survey foot should not be used."
                      """,
                      source: "85 FR 62698 (NIST / NOAA, 2020)")

                entry(title: "Wire gauge is a dimension, not a rating",
                      body: """
                      AWG diameters come from a defined geometric progression: No. 0000 is 0.4600" \
                      and No. 36 is 0.0050", with 38 sizes between, so each step is the 39th root of \
                      92 — 1.1229322.

                      Storypole gives the diameter and nothing else. Ampacity, conductor sizing, \
                      voltage drop and box fill are code questions with safety consequences, and \
                      this app deliberately does not answer them.
                      """,
                      source: "NBS Handbook 100 §2.1")

                entry(title: "What Storypole does not do",
                      body: """
                      It does not measure. Apple's Measure app does that. Storypole does the maths on \
                      a measurement you have already taken with a real tape.

                      It has no drill-size or pipe-schedule tables: the normative standards are \
                      copyrighted and purchase-only, so those numbers cannot be cited, and an \
                      uncitable number has no place here.
                      """,
                      source: "docs/storypole_oracle_gate_2026-07-29.md §5")
            }
            .padding(SP.s4)
        }
        .background(SP.background)
        .navigationTitle("Reference")
    }

    private func entry(title: LocalizedStringKey, body: String, source: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SPType.title)
                .foregroundStyle(SP.textPrimary)
            Text(body)
                .font(.callout)
                .foregroundStyle(SP.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(source)
                .font(SPType.footnote)
                .foregroundStyle(SP.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spCard()
    }
}

#Preview { NavigationStack { ReferenceView() } }
