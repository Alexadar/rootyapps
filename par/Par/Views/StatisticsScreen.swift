import SwiftUI
import StatKit

/// One- and two-variable statistics. The data list is the screen: a fit is only as good as the
/// points behind it, so they stay visible and editable instead of living in hidden registers.
public struct StatisticsScreen: View {
    @StateObject private var model = StatisticsViewModel()
    @Binding private var document: TapeDocument

    public init(document: Binding<TapeDocument>) {
        self._document = document
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                modelPicker
                hero
                fitDetail
                summary
                dataList
                AppendToTapeBar(label: $model.rowLabel, canAppend: model.tapeRow() != nil,
                                identifier: "stat.tape") { append() }
                ProvenanceStrip(authorities: model.authorities, conventions: model.conventions,
                                identifier: "stat.provenance")
            }
            .padding(.horizontal, Par.Metrics.gutter)
            .padding(.bottom, 12)
        }
        .background(Par.Palette.base)
        .navigationTitle("Statistics")
    }

    private var modelPicker: some View {
        SubScreenPicker(
            options: Stat.Model.allCases.map { ($0, $0.displayName) },
            selection: $model.model,
            identifier: "stat.model"
        )
    }

    @ViewBuilder
    private var hero: some View {
        switch model.outcome {
        case .fitted:
            VStack(spacing: 0) {
                NumberField("x′", caption: "forecast at", unit: "x",
                            value: $model.forecastX, range: StatisticsViewModel.valueRange,
                            digits: 3, identifier: "stat.input.forecastX")
            }
            .glassCard()
            if let forecast = model.forecast {
                HeroResult(caption: "ŷ · forecast at x′ = \(Fmt.count(model.forecastX))",
                           value: Fmt.money(forecast),
                           footnote: model.model.displayName + " fit",
                           identifier: "stat.hero",
                           spoken: Fmt.spokenMoney(forecast, label: "forecast"))
            } else {
                FailureNotice(
                    title: "This model cannot be evaluated there",
                    detail: "The \(model.model.displayName.lowercased()) model needs a positive x. "
                        + "Move the forecast point, or change the model.",
                    technical: "requiresPositive.x · nothing was appended to the tape",
                    identifier: "stat.hero.domain",
                    isWarning: true
                )
            }
        case .failed(let message):
            FailureNotice(
                title: "These points do not support a fit",
                detail: message,
                technical: "Stat.FitError · nothing was appended to the tape",
                identifier: "stat.hero.failure"
            )
        }
    }

    @ViewBuilder
    private var fitDetail: some View {
        if case .fitted(let fit) = model.outcome {
            VStack(spacing: 0) {
                ResultRow("a · intercept", value: Fmt.money(fit.intercept, digits: 6),
                          emphasis: .strong, identifier: "stat.intercept",
                          spoken: "intercept \(Fmt.money(fit.intercept, digits: 4))")
                Divider().overlay(Par.Palette.separator)
                ResultRow("b · slope", value: Fmt.money(fit.slope, digits: 6),
                          identifier: "stat.slope",
                          spoken: "slope \(Fmt.money(fit.slope, digits: 4))")
                Divider().overlay(Par.Palette.separator)
                ResultRow("r · correlation", value: Fmt.money(fit.correlation, digits: 6),
                          identifier: "stat.correlation",
                          spoken: "correlation \(Fmt.money(fit.correlation, digits: 4))")
                Divider().overlay(Par.Palette.separator)
                ResultRow("R²", value: Fmt.money(fit.rSquared, digits: 6),
                          identifier: "stat.rSquared",
                          spoken: "r squared \(Fmt.money(fit.rSquared, digits: 4))")
                Divider().overlay(Par.Palette.separator)
                ResultRow("residual s.d.", value: Fmt.money(fit.residualStandardDeviation, digits: 6),
                          identifier: "stat.residualSD",
                          spoken: "residual standard deviation "
                              + Fmt.money(fit.residualStandardDeviation, digits: 4))
            }
            .glassCard()
        }
    }

    @ViewBuilder
    private var summary: some View {
        if let x = model.summaryX, let y = model.summaryY {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { summaryCards(x: x, y: y) }
                VStack(spacing: 8) { summaryCards(x: x, y: y) }
            }
        }
    }

    @ViewBuilder
    private func summaryCards(x: Stat.Summary, y: Stat.Summary) -> some View {
        ResultRow("x̄", value: Fmt.money(x.mean, digits: 4), identifier: "stat.meanX",
                  spoken: "mean of x, \(Fmt.money(x.mean, digits: 2))")
        ResultRow("ȳ", value: Fmt.money(y.mean, digits: 4), identifier: "stat.meanY",
                  spoken: "mean of y, \(Fmt.money(y.mean, digits: 2))")
        ResultRow("sy", value: Fmt.money(y.sampleStandardDeviation, digits: 4),
                  identifier: "stat.sdY",
                  spoken: "sample standard deviation of y, "
                      + Fmt.money(y.sampleStandardDeviation, digits: 2))
    }

    private var dataList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(model.points.count) points")
                    .font(.caption2).foregroundStyle(Par.Palette.labelTertiary)
                Spacer()
                Button { model.addPoint() } label: {
                    Label("Add point", systemImage: "plus").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Par.Palette.accent)
                .accessibilityIdentifier("stat.addPoint")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider().overlay(Par.Palette.separator)

            ForEach(Array(model.points.enumerated()), id: \.element.id) { index, point in
                VStack(spacing: 0) {
                    NumberField("x\(index + 1)", caption: "x", unit: nil,
                                value: Binding(get: { model.points[index].x },
                                               set: { model.points[index].x = $0 }),
                                range: StatisticsViewModel.valueRange, digits: 4,
                                identifier: "stat.input.x.\(index)")
                    Divider().overlay(Par.Palette.separator)
                    HStack {
                        NumberField("y\(index + 1)", caption: "y", unit: nil,
                                    value: Binding(get: { model.points[index].y },
                                                   set: { model.points[index].y = $0 }),
                                    range: StatisticsViewModel.valueRange, digits: 4,
                                    identifier: "stat.input.y.\(index)")
                        if model.points.count > 3 {
                            Button(role: .destructive) {
                                model.removePoints(at: IndexSet(integer: index))
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Par.Palette.labelTertiary)
                            .padding(.trailing, 12)
                            .accessibilityLabel("Remove point \(index + 1)")
                            .accessibilityIdentifier("stat.removePoint.\(index)")
                        }
                    }
                    Divider().overlay(Par.Palette.separator)
                }
                .id(point.id)
            }
        }
        .glassCard()
    }

    private func append() {
        if let row = model.tapeRow() { document.append(row) }
    }
}

#Preview("Statistics — dark") {
    NavigationStack { StatisticsScreen(document: .constant(TapeDocument())) }.parAppearance()
}

#Preview("Statistics — AX5") {
    NavigationStack { StatisticsScreen(document: .constant(TapeDocument())) }
        .environment(\.dynamicTypeSize, .accessibility5)
        .parAppearance()
}
