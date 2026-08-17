import SwiftUI
import AltitudeKit
import PsychroKit
import UnitsKit

/// The wrist.
///
/// ## The scope call, and why
///
/// A technician holding gauges in both hands has no free hand for a phone, and a glance at a dew
/// point is genuinely worth something. What is *not* worth anything is a psychrometric chart at
/// 41 mm, or text entry with a scroll wheel. So the watch does two things and stops:
///
/// 1. **One crown-driven conversion.** Dry bulb and relative humidity in, dew point and wet bulb
///    out. The crown is the primary input and the fastest path to a value — it drives whichever
///    field is selected, and tapping the other field moves it.
/// 2. **The last state the phone solved**, delivered one way over WatchConnectivity, so a value
///    worked out on the phone five minutes ago is on the wrist without being retyped.
///
/// There is no chart, no tool catalogue and no way to change the elevation from here. Anything
/// that needs a keyboard belongs on the phone, and a shrunken phone app is the one answer the
/// brief rules out.
struct WatchRootView: View {

    private enum Field: String { case dryBulb, relativeHumidity }

    @State private var dryBulb: Double
    @State private var relativeHumidity: Double
    @State private var focusedField: Field
    @State private var transport = SessionTransport.shared

    /// Capture seed — `AIRCORE_WRIST=<dry bulb °C>,<RH 0…1>,<dryBulb|relativeHumidity>,<0|1>`.
    ///
    /// The store screenshots need this screen in more than one state, and two of those states
    /// cannot be reached from a cold launch on a standalone simulator: focus moves only by tapping,
    /// and the "FROM PHONE" panel needs a `WristState` that a paired iPhone would have sent over
    /// WatchConnectivity — which does not happen when the watch app is launched by itself.
    ///
    /// The seed sets the *inputs* only. Everything shown is still solved by PsychroKit from them,
    /// so a screenshot cannot show a number the app would not compute. Like every other capture
    /// hook it goes through `LaunchOverride` and is `nil` in Release.
    private struct Seed {
        var dryBulb = 23.888888888888889                // 75 °F
        var relativeHumidity = 0.5
        var focus: Field = .relativeHumidity
        var phoneState = false

        /// The defaults above — what every real launch gets.
        init() {}

        init?(parsing raw: String?) {
            guard let parts = raw?.split(separator: ","), parts.count == 4,
                  let db = Double(parts[0]), let rh = Double(parts[1]),
                  let f = Field(rawValue: String(parts[2])) else { return nil }
            dryBulb = db; relativeHumidity = rh; focus = f; phoneState = parts[3] == "1"
        }
    }

    private static let seed = Seed(parsing: LaunchOverride.value("AIRCORE_WRIST"))

    init() {
        let seed = Self.seed ?? Seed()
        _dryBulb = State(initialValue: seed.dryBulb)
        _relativeHumidity = State(initialValue: seed.relativeHumidity)
        _focusedField = State(initialValue: seed.focus)
    }

    /// What the phone last sent — or, under a capture seed, a stand-in for it.
    private var phoneState: WristState? {
        if let received = transport.received { return received }
        guard Self.seed?.phoneState == true,
              let state = try? MoistAir(dryBulb: 30.5, relativeHumidity: 0.669,
                                        pressure: Elevation.seaLevelPressure) else { return nil }
        return WristState(dryBulb: state.dryBulb, relativeHumidity: state.relativeHumidity,
                          wetBulb: state.wetBulb, dewPoint: state.dewPoint,
                          enthalpy: state.enthalpy, pressure: state.pressure,
                          unitSystem: UnitSystem.ip.rawValue, capturedAt: Date())
    }

    /// The crown scrubs a plain 0…1 position, mapped onto whichever field has focus. Binding it
    /// straight to the value would give the crown a different sensitivity per field and a
    /// different feel every time focus moved.
    @State private var crown = 0.5

    private var pressure: Double {
        phoneState?.pressure ?? Elevation.seaLevelPressure
    }

    private var system: UnitSystem {
        UnitSystem(rawValue: phoneState?.unitSystem ?? UnitSystem.ip.rawValue) ?? .ip
    }

    private var state: MoistAir? {
        try? MoistAir(dryBulb: dryBulb, relativeHumidity: relativeHumidity, pressure: pressure)
    }

    var body: some View {
        // **Not a ScrollView.** A `ScrollView` on watchOS claims the Digital Crown for scrolling,
        // and a `.digitalCrownRotation` attached anywhere inside it silently never fires — the app
        // looks right, the crown turns, and nothing moves. That failure is invisible in a
        // screenshot and was caught here only because the crown has a regression test.
        //
        // The screen is a glance, so it does not need to scroll: a readout, two fields and one
        // line from the phone.
        VStack(alignment: .leading, spacing: DS.s2) {
            readout
            fields
            if let received = phoneState {
                phonePanel(received)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.s2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .focusable()
        .digitalCrownRotation($crown, from: 0, through: 1, by: 0.005,
                              sensitivity: .medium, isContinuous: false)
        .onChange(of: crown) { _, position in apply(position) }
        .onAppear { crown = position(of: focusedField) }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var readout: some View {
        if let state {
            VStack(alignment: .leading, spacing: 0) {
                Text("Dew point")
                    .font(DS.ui(11, .semibold))
                    .foregroundStyle(DS.ink2)
                Text(state.dewPoint.map { Fmt.value(si: $0, .temperature, system) } ?? "—")
                    .font(DS.number(38))
                    .foregroundStyle(DS.ink)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .accessibilityLabel("Dew point")
                    .accessibilityValue(state.dewPoint.map {
                        Fmt.spoken(si: $0, .temperature, system) } ?? "none, the air is dry")
                    .accessibilityIdentifier("watch.dewPoint")
                Text("WB \(Fmt.valueWithUnit(si: state.wetBulb, .temperature, system))"
                     + " · h \(Fmt.valueWithUnit(si: state.enthalpy, .enthalpy, system))")
                    .font(DS.number(11, .regular))
                    .foregroundStyle(DS.ink2)
                    .accessibilityLabel("Wet bulb")
                    .accessibilityValue(Fmt.spoken(si: state.wetBulb, .temperature, system))
            }
        } else {
            Text("Out of range")
                .font(DS.ui(13, .semibold))
                .foregroundStyle(DS.warn)
                .accessibilityIdentifier("watch.outOfRange")
        }
    }

    private var fields: some View {
        HStack(spacing: DS.s1) {
            field(.dryBulb, title: "DB", value: Fmt.value(si: dryBulb, .temperature, system))
            field(.relativeHumidity, title: "RH",
                  value: Fmt.value(si: relativeHumidity, .relativeHumidity, system))
        }
    }

    private func field(_ which: Field, title: String, value: String) -> some View {
        let focused = focusedField == which
        return Button {
            focusedField = which
            crown = position(of: which)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DS.ui(9, .semibold))
                    .foregroundStyle(focused ? DS.water : DS.ink2)
                Text(value)
                    .font(DS.number(15))
                    .foregroundStyle(DS.ink)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(focused ? DS.waterTint : DS.panel)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(focused ? DS.water : Color.clear, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(which == .dryBulb ? "Dry bulb" : "Relative humidity")
        .accessibilityValue(value)
        .accessibilityAddTraits(focused ? [.isSelected] : [])
        .accessibilityIdentifier("watch.field.\(which.rawValue)")
    }

    private func phonePanel(_ received: WristState) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("FROM PHONE")
                .font(DS.ui(9, .semibold)).tracking(0.8)
                .foregroundStyle(DS.ink2)
            Text("\(Fmt.valueWithUnit(si: received.dryBulb, .temperature, system))"
                 + " · \(Fmt.valueWithUnit(si: received.relativeHumidity, .relativeHumidity, system))")
                .font(DS.number(12))
                .foregroundStyle(DS.ink)
            Text("WB \(Fmt.valueWithUnit(si: received.wetBulb, .temperature, system))")
                .font(DS.number(11, .regular))
                .foregroundStyle(DS.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.s2)
        .background(DS.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("watch.phoneState")
    }

    // MARK: - Crown

    /// Ranges the crown scrubs across: everything an air-side technician will meet, and no more —
    /// a crown that covers −100 °C to 200 °C would need a full turn per degree.
    private static let dryBulbRange = -30.0 ... 60.0
    private static let relativeHumidityRange = 0.0 ... 1.0

    private func position(of field: Field) -> Double {
        switch field {
        case .dryBulb:
            return (dryBulb - Self.dryBulbRange.lowerBound)
                / (Self.dryBulbRange.upperBound - Self.dryBulbRange.lowerBound)
        case .relativeHumidity:
            return relativeHumidity
        }
    }

    private func apply(_ position: Double) {
        switch focusedField {
        case .dryBulb:
            dryBulb = Self.dryBulbRange.lowerBound
                + position * (Self.dryBulbRange.upperBound - Self.dryBulbRange.lowerBound)
        case .relativeHumidity:
            relativeHumidity = min(max(position, Self.relativeHumidityRange.lowerBound),
                                   Self.relativeHumidityRange.upperBound)
        }
    }
}
