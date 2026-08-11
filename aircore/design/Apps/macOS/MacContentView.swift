import SwiftUI
import AirsideKit
import AirsideUI

/// macOS — desk work and reporting. Keyboard entry, tab between fields, copy a value
/// (⌘C) or the table (⌘⇧C), export CSV, drag a state set out to Finder / Numbers.
@main struct AirsideMacApp: App {
    var body: some Scene {
        WindowGroup { MacContentView() }
            .commands {
                CommandGroup(after: .pasteboard) {
                    Button("Copy Table") {}.keyboardShortcut("c", modifiers: [.command, .shift])
                }
            }
    }
}

struct MacContentView: View {
    @State private var db = 75.0
    @State private var rh = 50.0
    @State private var altitude = Altitude.denver
    private var s: PsychroState { Psychrometrics.solve(dryBulbF: db, relHumidityPercent: rh, altitude: altitude) }

    var body: some View {
        NavigationSplitView {
            List {
                Section("Tools") {
                    Label("Psychrometrics", systemImage: "wind")
                    Label("Air-side heat", systemImage: "flame")
                    Label("Duct — friction", systemImage: "rectangle.split.3x1")
                    Label("Air mixing", systemImage: "arrow.triangle.merge")
                }
                Section("State set — drag out ⤴") {
                    Text("State A · 75/50 · WB 60.3 · h 30.4")
                        .font(DS.number(11)).foregroundColor(DS.ink2)
                        .onDrag { NSItemProvider(object: csvLine() as NSString) }
                }
            }.frame(minWidth: 220)
        } detail: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        Text("Psychrometrics").font(DS.ui(18, .bold)).foregroundColor(DS.ink)
                        Spacer(); AltitudeChip(altitude: altitude) {}
                    }
                    Text("Tab between fields · ⌘C copies the value · ⌘⇧C copies the table")
                        .font(DS.ui(10.5, .medium)).foregroundColor(DS.ink2)
                    HStack(spacing: 9) {
                        LabeledField("Dry bulb", value: $db)
                        LabeledField("RH", value: $rh)
                    }
                    resultRow("Wet bulb", "\(s.wetBulb.formatted(.number.precision(.fractionLength(1)))) °F")
                    resultRow("Dew point", "\(s.dewPoint.formatted(.number.precision(.fractionLength(1)))) °F")
                    resultRow("Enthalpy", "\(s.enthalpy.formatted(.number.precision(.fractionLength(1)))) Btu/lb", highlight: true)
                    resultRow("Sp. volume", "\(s.specificVolume.formatted(.number.precision(.fractionLength(2)))) ft³/lb")
                    Spacer()
                    HStack {
                        Button("Copy table") { copyTable() }.buttonStyle(.borderedProminent).tint(DS.water)
                        Button("Export CSV") {}
                    }
                }
                .padding(16).frame(width: 320)
                .background(Color(hex: 0xF5F8FB))
                .overlay(Rectangle().frame(width: 1).foregroundColor(DS.border), alignment: .trailing)

                PsychroChart(dryBulb: $db, relHumidity: $rh, altitude: altitude, showEnthalpy: true)
                    .padding(14)
            }
        }
        .background(DS.breeze)
    }

    func csvLine() -> String {
        "label,value,unit\nDry bulb,\(db),°F\nRH,\(rh),%\nWet bulb,\(s.wetBulb),°F\nDew point,\(s.dewPoint),°F\nEnthalpy,\(s.enthalpy),Btu/lb"
    }
    func copyTable() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csvLine(), forType: .string)
        #endif
    }
    func resultRow(_ l: String, _ v: String, highlight: Bool = false) -> some View {
        HStack { Text(l).font(DS.ui(12, .semibold)).foregroundColor(highlight ? DS.water : DS.ink2)
            Spacer(); Text(v).font(DS.number(12)).foregroundColor(DS.ink) }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(highlight ? Color(hex: 0xEEF4FB) : DS.card)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(highlight ? Color(hex: 0xCBDDF1) : Color(hex: 0xE0E9F1), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct LabeledField: View {
    var title: String
    @Binding var value: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(DS.ui(10, .semibold)).foregroundColor(DS.water)
            TextField("", value: $value, format: .number)
                .textFieldStyle(.plain).font(DS.number(22)).foregroundColor(DS.ink)
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(DS.card)
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(DS.water, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }
}
