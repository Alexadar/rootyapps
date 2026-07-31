import SwiftUI
import DepKit

/// Depreciation, with the year-by-year table and — for MACRS — the published percentage beside each
/// dollar figure, because that is the number a preparer reconciles against the IRS table.
public struct DepreciationScreen: View {
    @StateObject private var model = DepreciationViewModel()
    @Binding private var document: TapeDocument

    public init(document: Binding<TapeDocument>) {
        self._document = document
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                methodPicker
                inputs
                hero
                totals
                if model.method == .macrsGDS { conventionPicker }
                table
                AppendToTapeBar(label: $model.rowLabel, canAppend: model.tapeRow() != nil,
                                identifier: "dep.tape") { append() }
                ProvenanceStrip(authorities: model.authorities, conventions: model.conventions,
                                identifier: "dep.provenance")
            }
            .padding(.horizontal, Par.Metrics.gutter)
            .padding(.bottom, 12)
        }
        .background(Par.Palette.base)
        .navigationTitle("Depreciation")
    }

    private var methodPicker: some View {
        Picker("Method", selection: $model.method) {
            ForEach(Depreciation.Method.allCases, id: \.self) { method in
                Text(method.displayName).tag(method)
            }
        }
        .pickerStyle(.menu)
        .tint(Par.Palette.accent)
        .frame(maxWidth: .infinity, minHeight: Par.Metrics.minHitTarget, alignment: .leading)
        .accessibilityIdentifier("dep.method")
    }

    private var conventionPicker: some View {
        Picker("Placed in service", selection: $model.convention) {
            ForEach(Depreciation.Convention.allCases, id: \.self) { convention in
                Text(convention.displayName).tag(convention)
            }
        }
        .pickerStyle(.menu)
        .tint(Par.Palette.accent)
        .frame(maxWidth: .infinity, minHeight: Par.Metrics.minHitTarget, alignment: .leading)
        .accessibilityIdentifier("dep.convention")
    }

    private var inputs: some View {
        VStack(spacing: 0) {
            NumberField("CST", caption: "cost basis", unit: "USD",
                        value: $model.cost, range: DepreciationViewModel.costRange, digits: 2,
                        identifier: "dep.input.cost")
            Divider().overlay(Par.Palette.separator)
            NumberField("SAL", caption: "salvage value", unit: "USD",
                        value: $model.salvage, range: DepreciationViewModel.salvageRange, digits: 2,
                        identifier: "dep.input.salvage")
            Divider().overlay(Par.Palette.separator)
            if model.method == .macrsGDS {
                // MACRS is a statutory schedule, not a free choice of life: only these six classes
                // have a published GDS column, and offering the others invited the app to cite a
                // table that does not exist.
                SettingCard("LIF · recovery period",
                            value: "\(Int(model.recoveryYears))-year",
                            identifier: "dep.input.recoveryYears.macrs",
                            spoken: "recovery period, \(Int(model.recoveryYears)) year property") {
                    Picker("recovery period", selection: Binding(
                        get: { Int(model.recoveryYears) },
                        set: { model.recoveryYears = Double($0) }
                    )) {
                        ForEach(DepreciationViewModel.macrsClasses, id: \.self) { years in
                            Text("\(years)-year property").tag(years)
                        }
                    }
                    .pickerStyle(.inline)
                }
            } else {
                NumberField("LIF", caption: "recovery period", unit: "years",
                            value: $model.recoveryYears, range: DepreciationViewModel.recoveryRange,
                            digits: 0, identifier: "dep.input.recoveryYears.free")
            }
            if model.method == .decliningBalance || model.method == .decliningBalanceWithCrossover {
                Divider().overlay(Par.Palette.separator)
                NumberField("FAC", caption: "declining-balance factor", unit: "×",
                            value: $model.factor, range: DepreciationViewModel.factorRange,
                            digits: 2, identifier: "dep.input.factor")
            }
        }
        .glassCard()
        .overlay(alignment: .bottom) {
            if model.salvageIsIgnored {
                Text("MACRS ignores salvage value by statute — this figure is not used.")
                    .font(.caption)
                    .foregroundStyle(Par.Palette.warning)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("dep.salvageIgnored")
            }
        }
    }

    private var hero: some View {
        HeroResult(caption: "first-year deduction",
                   value: Fmt.money(model.firstYear),
                   footnote: model.method == .macrsGDS
                       ? "\(model.convention.displayName) · \(Int(model.recoveryYears))-year property"
                       : model.method.displayName,
                   identifier: "dep.hero",
                   spoken: Fmt.spokenMoney(model.firstYear, label: "first year deduction"))
    }

    private var totals: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { totalCards }
            VStack(spacing: 8) { totalCards }
        }
    }

    @ViewBuilder
    private var totalCards: some View {
        ResultRow("total recovered", value: Fmt.money(model.totalDepreciation), unit: "USD",
                  emphasis: .strong, identifier: "dep.total",
                  spoken: Fmt.spokenMoney(model.totalDepreciation, label: "total recovered"))
        if let crossover = model.crossoverYear {
            ResultRow("crossover to straight line", value: "year \(crossover)",
                      identifier: "dep.crossover",
                      spoken: "switches to straight line in year \(crossover)")
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("year").frame(width: 44, alignment: .leading)
                if model.macrsPercentages != nil {
                    Text("table %").frame(maxWidth: .infinity, alignment: .trailing)
                }
                Text("deduction").frame(maxWidth: .infinity, alignment: .trailing)
                Text("book value").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.caption2)
            .foregroundStyle(Par.Palette.labelTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .accessibilityHidden(true)
            Divider().overlay(Par.Palette.separator)

            ForEach(model.schedule, id: \.year) { year in
                HStack(spacing: 10) {
                    Text("\(year.year)")
                        .frame(width: 44, alignment: .leading)
                        .foregroundStyle(Par.Palette.labelSecondary)
                    if let percentages = model.macrsPercentages,
                       year.year <= percentages.count {
                        Text(Fmt.percent(percentages[year.year - 1], digits: 2))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .foregroundStyle(Par.Palette.labelSecondary)
                    }
                    Text(Fmt.money(year.depreciation))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundStyle(Par.Palette.label)
                    Text(Fmt.money(year.bookValue))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundStyle(Par.Palette.labelSecondary)
                }
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("dep.year.\(year.year)")
                Divider().overlay(Par.Palette.separator)
            }
        }
        .glassCard()
    }

    private func append() {
        if let row = model.tapeRow() { document.append(row) }
    }
}

#Preview("Depreciation — dark") {
    NavigationStack { DepreciationScreen(document: .constant(TapeDocument())) }.parAppearance()
}

#Preview("Depreciation — AX5") {
    NavigationStack { DepreciationScreen(document: .constant(TapeDocument())) }
        .environment(\.dynamicTypeSize, .accessibility5)
        .parAppearance()
}
