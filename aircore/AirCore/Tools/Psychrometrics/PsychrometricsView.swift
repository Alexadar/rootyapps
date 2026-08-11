import SwiftUI
import PsychroKit
import UnitsKit

/// The anchor screen.
///
/// ## Layout, per platform
///
/// On a phone the chart sits above the results and the two known-value fields sit at the bottom,
/// in the half of the screen a thumb reaches. On an iPad or a Mac the same content splits
/// left-and-right, because there the chart deserves the width and the user is sitting down.
///
/// The layout switch is on **size class**, not on device and not on `ViewThatFits` — an iPad in a
/// narrow Split View is a phone-shaped space and gets the phone layout.
struct PsychrometricsView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppModels.self) private var models
    @Environment(\.dynamicTypeSize) private var typeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var showElevationSheet = false
    @State private var exportRows: [ResultGrid.Row] = []

    private var model: PsychrometricsModel { models.psychrometrics }

    var body: some View {
        layout
        .background(DS.breeze)
        .navigationTitle(Tool.psychrometrics.title)
        .onPreferenceChange(ResultRowsKey.self) { exportRows = $0 }
        .toolbar {
            ToolHeader(showElevationSheet: $showElevationSheet)
            ToolbarItem(placement: .secondaryAction) {
                ExportControls(tool: .psychrometrics, rows: exportRows)
            }
        }
        .sheet(isPresented: $showElevationSheet) { ElevationSheet() }
        .onAppear { settings.noteOpened(.psychrometrics) }
        .onChange(of: model.firstValue) { _, _ in publishToWatch() }
        .onChange(of: model.secondValue) { _, _ in publishToWatch() }
        .onAppear { publishToWatch() }
    }

    // MARK: - Layouts

    /// Chosen on **size class**, not with `ViewThatFits`.
    ///
    /// `ViewThatFits` takes the first child that fits, and the wide layout always "fits": its chart
    /// will compress to a few points wide rather than refuse. So an iPhone rendered the iPad
    /// layout — a 380-point inspector beside a chart about twenty pixels across, with the state
    /// point floating in a sliver. Every UI test passed, because the chart *existed*; a screenshot
    /// showed it in one glance.
    ///
    /// Size class asks the question that was actually meant: is this a phone-shaped space or a
    /// desk-shaped one.
    /// The width at which splitting left-and-right is actually better than stacking: a 380-point
    /// inspector plus a chart wide enough to read. Below it the chart becomes a tall strip and the
    /// stacked layout wins — which is exactly what an iPad in portrait is, once the sidebar has
    /// taken its 320 points.
    private static let splitLayoutMinimumWidth: CGFloat = 760

    /// Measured, not inferred.
    ///
    /// Size class is too coarse here: an iPad in portrait is `.regular` but leaves this view about
    /// 700 points, and the split put the chart in a sliver. `GeometryReader` reports the width this
    /// view actually has, after the sidebar, in every orientation and every Split View fraction.
    private var layout: some View {
        GeometryReader { proxy in
            if proxy.size.width >= Self.splitLayoutMinimumWidth {
                wideLayout
            } else {
                // The chart takes a share of the height rather than a fixed 190 points: that
                // number is right on a phone and leaves a dead band on a 13-inch iPad in portrait.
                narrowLayout(chartHeight: min(max(proxy.size.height * 0.26, 190), 430))
            }
        }
    }

    private func narrowLayout(chartHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: DS.s3) {
                    chart.frame(height: chartHeight)
                    results
                }
                .padding(.horizontal, DS.s4)
                .padding(.top, DS.s3)
            }
            inputs
        }
    }

    private var wideLayout: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.s3) {
                    inputFields
                    results
                }
                .padding(DS.s4)
            }
            .frame(width: 380)
            .background(DS.panel)

            chart.padding(DS.s4)
        }
    }

    // MARK: - Pieces

    private var chart: some View {
        PsychroChartView(points: chartPoints,
                         pressure: settings.pressure,
                         system: settings.unitSystem,
                         onDrag: { dryBulb, humidityRatio in
                             model.setFromChart(dryBulb: dryBulb, humidityRatio: humidityRatio)
                         })
    }

    private var chartPoints: [ChartPoint] {
        guard case .success(let state) = model.solved(pressure: settings.pressure) else { return [] }
        return [ChartPoint(role: .a, state: state)]
    }

    @ViewBuilder
    private var results: some View {
        switch model.solved(pressure: settings.pressure) {
        case .success(let state):
            resultGrid(state)
        case .failure(let error):
            StatusBanner(kind: .error, title: error.readableTitle, detail: error.readableDetail)
                .accessibilityIdentifier("psychro.error")
        }
    }

    private func resultGrid(_ state: MoistAir) -> some View {
        ResultGrid(tool: .psychrometrics, rows: rows(for: state))
    }

    private func rows(for state: MoistAir) -> [ResultGrid.Row] {
        var rows: [ResultGrid.Row] = [
            .init(title: "Dry bulb", value: state.dryBulb, quantity: .temperature),
            .init(title: "Wet bulb", value: state.wetBulb, quantity: .temperature,
                  emphasised: true),
        ]
        if let dewPoint = state.dewPoint {
            rows.append(.init(title: "Dew point", value: dewPoint, quantity: .temperature,
                              emphasised: true))
        }
        rows.append(contentsOf: [
            .init(title: "Relative humidity", value: state.relativeHumidity,
                  quantity: .relativeHumidity),
            .init(title: "Humidity ratio", value: state.humidityRatio, quantity: .humidityRatio),
            .init(title: "Enthalpy", value: state.enthalpy, quantity: .enthalpy),
            .init(title: "Specific volume", value: state.specificVolume,
                  quantity: .specificVolume),
            .init(title: "Density", value: state.density, quantity: .density),
            .init(title: "Degree of saturation", value: state.degreeOfSaturation,
                  quantity: .relativeHumidity),
        ])
        return rows
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            Text("KNOWN — ANY TWO")
                .font(DS.ui(10.5, .semibold)).tracking(1)
                .foregroundStyle(DS.ink2)
            inputFields
        }
        .padding(DS.s4)
        .background(DS.panel)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(DS.border), alignment: .top)
    }

    @ViewBuilder
    private var inputFields: some View {
        let fields = ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.s3) { firstField; secondField }
            VStack(spacing: DS.s3) { firstField; secondField }
        }
        fields
    }

    private var firstField: some View {
        KnownField(kind: model.firstKnown,
                   opposite: model.secondKnown,
                   value: Binding(get: { model.firstValue },
                                  set: { model.firstValue = $0 }),
                   isUnavailable: { model.isUnavailable($0, opposite: model.secondKnown) },
                   onKindChange: { model.changeFirst(to: $0, pressure: settings.pressure) },
                   system: settings.unitSystem,
                   slot: "first")
    }

    private var secondField: some View {
        KnownField(kind: model.secondKnown,
                   opposite: model.firstKnown,
                   value: Binding(get: { model.secondValue },
                                  set: { model.secondValue = $0 }),
                   isUnavailable: { model.isUnavailable($0, opposite: model.firstKnown) },
                   onKindChange: { model.changeSecond(to: $0, pressure: settings.pressure) },
                   system: settings.unitSystem,
                   slot: "second")
    }

    private func publishToWatch() {
        guard case .success(let state) = model.solved(pressure: settings.pressure) else { return }
        SessionTransport.shared.send(
            WristState(dryBulb: state.dryBulb,
                       relativeHumidity: state.relativeHumidity,
                       wetBulb: state.wetBulb,
                       dewPoint: state.dewPoint,
                       enthalpy: state.enthalpy,
                       pressure: state.pressure,
                       unitSystem: settings.unitSystem.rawValue,
                       capturedAt: Date()))
    }
}

/// One of the two knowns: which property it is, and its value.
private struct KnownField: View {
    let kind: PsychroInput.Kind
    let opposite: PsychroInput.Kind
    @Binding var value: Double
    let isUnavailable: (PsychroInput.Kind) -> Bool
    let onKindChange: (PsychroInput.Kind) -> Void
    let system: UnitSystem
    let slot: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s1) {
            Picker(selection: Binding(get: { kind }, set: onKindChange)) {
                ForEach(PsychroInput.Kind.allCases, id: \.self) { candidate in
                    Text(candidate.title)
                        .tag(candidate)
                }
            } label: {
                Text(kind.title)
            }
            .pickerStyle(.menu)
            // macOS draws a Picker's label beside its value, so the row read "Dry bulb ⌄ Dry bulb".
            // iOS shows only the menu, which is why this survived until the Mac was captured.
            .labelsHidden()
            .tint(DS.water)
            .accessibilityLabel("\(slot == "first" ? "First" : "Second") known property")
            .accessibilityValue(kind.plainTitle)
            .accessibilityIdentifier("psychro.known.\(slot)")

            NumericField(title: kind.title,
                         spokenTitle: kind.plainTitle,
                         quantity: kind.quantity,
                         system: system,
                         siValue: $value,
                         step: step,
                         isActive: true,
                         identifier: "psychro.value.\(slot)")
        }
    }

    /// One press should move the number by something a technician would actually type.
    private var step: Double {
        switch kind.quantity {
        case .temperature:      return 0.5
        case .relativeHumidity: return 1
        case .humidityRatio:    return system == .ip ? 1 : 0.1
        case .enthalpy:         return 0.5
        case .specificVolume:   return system == .ip ? 0.05 : 0.005
        default:                return 1
        }
    }
}
