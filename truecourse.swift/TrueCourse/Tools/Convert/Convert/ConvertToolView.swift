import SwiftUI
import ConvertKit

/// A unit within a conversion category, expressed via a common base value.
struct ConvUnit {
    let name: String
    let toBase: (Double) -> Double
    let fromBase: (Double) -> Double
}

struct ConvCategory: Identifiable {
    let id = UUID()
    let name: String
    let units: [ConvUnit]
    let decimals: Int
}

let categories: [ConvCategory] = [
    ConvCategory(name: "Temperature", units: [
        ConvUnit(name: "°C", toBase: { $0 }, fromBase: { $0 }),
        ConvUnit(name: "°F", toBase: Convert.fToC, fromBase: Convert.cToF),
    ], decimals: 1),
    ConvCategory(name: "Distance", units: [
        ConvUnit(name: "nm", toBase: { $0 }, fromBase: { $0 }),
        ConvUnit(name: "sm", toBase: Convert.smToNm, fromBase: Convert.nmToSm),
        ConvUnit(name: "km", toBase: Convert.kmToNm, fromBase: Convert.nmToKm),
    ], decimals: 2),
    ConvCategory(name: "Altitude", units: [
        ConvUnit(name: "ft", toBase: { $0 }, fromBase: { $0 }),
        ConvUnit(name: "m", toBase: Convert.mToFt, fromBase: Convert.ftToM),
    ], decimals: 1),
    ConvCategory(name: "Speed", units: [
        ConvUnit(name: "kt", toBase: { $0 }, fromBase: { $0 }),
        ConvUnit(name: "mph", toBase: Convert.mphToKt, fromBase: Convert.ktToMph),
    ], decimals: 1),
    ConvCategory(name: "Weight", units: [
        ConvUnit(name: "lb", toBase: { $0 }, fromBase: { $0 }),
        ConvUnit(name: "kg", toBase: Convert.kgToLb, fromBase: Convert.lbToKg),
    ], decimals: 1),
    ConvCategory(name: "Fuel", units: [
        ConvUnit(name: "gal", toBase: { $0 }, fromBase: { $0 }),
        ConvUnit(name: "L", toBase: Convert.litreToGal, fromBase: Convert.galToLitre),
        ConvUnit(name: "lb avgas", toBase: Convert.avgasLbToGal, fromBase: Convert.avgasGalToLb),
    ], decimals: 1),
    ConvCategory(name: "Climb", units: [
        ConvUnit(name: "ft/nm", toBase: { $0 }, fromBase: { $0 }),
        ConvUnit(name: "%", toBase: Convert.percentToFtPerNm, fromBase: Convert.ftPerNmToPercent),
        ConvUnit(name: "°", toBase: Convert.degreesToFtPerNm, fromBase: Convert.ftPerNmToDegrees),
    ], decimals: 2),
]

@MainActor
final class ConvertViewModel: ObservableObject {
    @Published var categoryIndex = 0
    @Published var fromIndex = 0
    @Published var input = 100.0

    private var demoTimer: Timer?
    private var demoTick = 0

    /// Reel demo: sweep the input so the converted values roll (0…100 °C → 32…212 °F).
    /// Held still during a warm-up so the scene settles first, then the numbers move.
    init() {
        guard DemoSweep.isOn else { return }
        demoTimer = Timer.scheduledTimer(withTimeInterval: DemoSweep.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.demoTick += 1
                if let v = DemoSweep.value(tick: self.demoTick, a: 0, b: 100) {
                    self.input = v                          // 0…100 °C → 32…212 °F
                }
            }
        }
    }

    var category: ConvCategory { categories[categoryIndex] }

    func selectCategory(_ i: Int) {
        categoryIndex = i
        fromIndex = 0
    }

    /// Converted outputs for every unit other than the input unit.
    var outputs: [(name: String, value: String)] {
        let cat = category
        guard fromIndex < cat.units.count else { return [] }
        let base = cat.units[fromIndex].toBase(input)
        return cat.units.enumerated().compactMap { i, u in
            i == fromIndex ? nil : (u.name, Fmt.f(u.fromBase(base), cat.decimals))
        }
    }
}

struct ConvertToolView: View {
    @Environment(\.tc) private var tc
    @StateObject private var vm = ConvertViewModel()

    var body: some View {
        AdaptiveStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Category")
                Picker("Category", selection: Binding(get: { vm.categoryIndex },
                                                      set: { vm.selectCategory($0) })) {
                    ForEach(categories.indices, id: \.self) { i in
                        Text(categories[i].name).tag(i)
                    }
                }
                .pickerStyle(.menu)
                .tint(tc.accent(.tools))

                Picker("From", selection: $vm.fromIndex) {
                    ForEach(vm.category.units.indices, id: \.self) { i in
                        Text(vm.category.units[i].name).tag(i)
                    }
                }
                .pickerStyle(.segmented)

                NumberField(title: "Value", value: $vm.input)
            }
            .instrumentCard()
            .inputColumn()

            ResultCard(accent: tc.accent(.tools)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Converted")
                    let outs = vm.outputs
                    ForEach(Array(outs.enumerated()), id: \.offset) { idx, o in
                        ResultRow(label: o.name, value: o.value, emphasis: idx == 0)
                    }
                }
            }
        }
    }
}
