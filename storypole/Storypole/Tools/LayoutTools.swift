import SwiftUI
import DimensionKit
import LayoutKit

/// The differentiator. Every other calculator returns a spacing number; these return **the marks**.

// MARK: - Equal spacing

struct EqualSpacingToolView: View {
    @State private var spanText = "62-1/4\""
    @State private var parts = 8
    @State private var denominator: Int64 = 16
    @State private var mode: Mode = .divide
    @State private var itemCount = 7
    @State private var itemWidthText = "1-1/2\""

    enum Mode: String, CaseIterable { case divide = "Divide", items = "Items" }

    private var span: FeetInch? { FeetInch.parse(spanText) }
    private var itemWidth: FeetInch? { FeetInch.parse(itemWidthText) }

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text(L.loc($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("spacing.mode")

            DimensionField(label: "Span", text: $spanText, identifier: "spacing.span")
            DenominatorPicker(denominator: $denominator)

            if mode == .divide {
                Stepper("Equal parts: \(parts)", value: $parts, in: 2...64)
                    .font(SPType.label)
                    .accessibilityIdentifier("spacing.parts")
                if let s = span { divideResults(s) }
            } else {
                Stepper("Items: \(itemCount)", value: $itemCount, in: 1...64)
                    .font(SPType.label)
                    .accessibilityIdentifier("spacing.count")
                DimensionField(label: "Item width", text: $itemWidthText, placeholder: "1-1/2\"",
                               identifier: "spacing.itemWidth")
                if let s = span, let w = itemWidth { itemResults(s, w) }
            }

            Text("Marks are exact: the bays add back to the span with nothing left over.")
                .font(SPType.footnote).foregroundStyle(SP.textTertiary)
        }
    }

    @ViewBuilder private func divideResults(_ s: FeetInch) -> some View {
        let bay = EqualSpacing.bay(span: s, parts: parts)
        let marks = EqualSpacing.marks(span: s, parts: parts)
        VStack(spacing: SP.s3) {
            ResultRow(label: "Each bay", value: bay.formatted(toDenominator: denominator),
                      emphasis: true, identifier: "spacing.bay")
            ResultRow(label: "Midpoint", value: EqualSpacing.half(s).formatted(toDenominator: denominator),
                      identifier: "spacing.half")
        }
        .spCard()
        MarkList(title: "Marks", marks: marks, denominator: denominator, identifier: "spacing.marks")
    }

    @ViewBuilder private func itemResults(_ s: FeetInch, _ w: FeetInch) -> some View {
        if let gap = EqualSpacing.itemGap(span: s, count: itemCount, itemWidth: w),
           let centres = EqualSpacing.itemCentres(span: s, count: itemCount, itemWidth: w) {
            VStack(spacing: SP.s3) {
                ResultRow(label: "Gap between items", value: gap.formatted(toDenominator: denominator),
                          emphasis: true, identifier: "spacing.gap")
                ResultRow(label: "Items", value: String(itemCount), identifier: "spacing.items")
            }
            .spCard()
            MarkList(title: "Item centres", marks: centres, denominator: denominator,
                     identifier: "spacing.centres")
        } else {
            Text("\(itemCount) items of that width do not fit in the span.")
                .font(SPType.label).foregroundStyle(SP.accent)
                .spCard()
                .accessibilityIdentifier("spacing.overfull")
        }
    }
}

// MARK: - On center

struct OnCenterToolView: View {
    @State private var spanText = "20' 7-1/2\""
    @State private var spacing: OnCenter.Spacing = .sixteen
    @State private var denominator: Int64 = 16

    private var span: FeetInch? { FeetInch.parse(spanText) }

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            DimensionField(label: "Span", text: $spanText, identifier: "oc.span")

            Picker("Spacing", selection: $spacing) {
                ForEach(OnCenter.Spacing.allCases, id: \.self) { s in
                    Text(L.loc(s.rawValue)).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("oc.spacing")

            if let s = span, !s.isNegative {
                let l = OnCenter.layout(span: s, spacing: spacing)
                VStack(spacing: SP.s3) {
                    ResultRow(label: "Members", value: String(l.memberCount), emphasis: true,
                              identifier: "oc.count")
                    ResultRow(label: "Last bay",
                              value: l.isEven ? "even" : l.lastBay.formatted(toDenominator: denominator),
                              identifier: "oc.lastBay")
                }
                .spCard()
                MarkList(title: "Marks", marks: l.marks, denominator: denominator, identifier: "oc.marks")
            }

            VStack(alignment: .leading, spacing: SP.s1) {
                Text(spacing.isPublished ? "Published spacing" : "Derived spacing")
                    .font(SPType.eyebrow)
                    .foregroundStyle(spacing.isPublished ? SP.textSecondary : SP.accent)
                Text(spacing.provenance)
                    .font(SPType.footnote).foregroundStyle(SP.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .spCard()
            .spProse("oc.provenance")
        }
    }
}

// MARK: - Shared

/// The list of marks — the thing nobody else prints.
///
/// Every other calculator in this category returns a spacing *number*. These are the marks you
/// pencil on the board, numbered in the order you make them, so the card can be read at arm's
/// length while the tape is still against the work.
struct MarkList: View {
    let title: String
    let marks: [FeetInch]
    let denominator: Int64
    var identifier: String = "marks"

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s3) {
            HStack {
                SectionEyebrow(title: title, accent: ToolSection.layout.accent)
                Spacer()
                Text("\(marks.count)")
                    .font(SPType.footnote.monospacedDigit())
                    .foregroundStyle(SP.textTertiary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: SP.s2)], spacing: SP.s2) {
                ForEach(Array(marks.enumerated()), id: \.offset) { i, m in
                    HStack(spacing: SP.s2) {
                        Text("\(i + 1)")
                            .font(SPType.footnote.monospacedDigit())
                            .foregroundStyle(SP.textTertiary)
                            .frame(minWidth: 16, alignment: .trailing)
                        Text(m.formatted(toDenominator: denominator))
                            .font(SPType.mark)
                            .foregroundStyle(SP.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, SP.s2).padding(.horizontal, SP.s2)
                    .background(SP.surfaceSunk,
                                in: RoundedRectangle(cornerRadius: SP.rChip - 2, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spCard()
        .accessibilityIdentifier(identifier)
    }
}

#Preview("Equal spacing") { ScrollView { EqualSpacingToolView().padding() }.background(SP.background) }
#Preview("On center")     { ScrollView { OnCenterToolView().padding() }.background(SP.background) }
