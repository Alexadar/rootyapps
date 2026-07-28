import SwiftUI
import CoreLocation
import GeodesyKit
import TidesKit

// ─────────────────────────────────────────────────────────────────────────────
// F2 · STATION PICKER
//
// ⚠ NEW CAPABILITY, NOT IN THE PHONE APP. The phone/Mac app ships with no
// location and no networking by design. "Nearest stations" needs CoreLocation —
// a system framework, not a package, and no network — but it DOES change the
// app's privacy posture and needs an Info.plist purpose string. See README
// "Deviations". If the product would rather not take it: delete
// `WatchLocationProvider`, keep `.recents` and `.browse`, and the screen still
// works. That is why permission-denied is the FIRST-CLASS path below, not an
// error state.
//
// ZERO math: distance and bearing come from GeodesyKit's Vincenty.inverse — the
// same Kit the phone's Distance & Bearing tool uses. No haversine in a view.
// ─────────────────────────────────────────────────────────────────────────────

/// Persists the chosen station and unit. No pairing-time transfer from the phone:
/// the watch app runs independently, so it owns its own selection.
@MainActor
final class WatchStationStore: ObservableObject {
    static let shared = WatchStationStore()

    @AppStorage("watch.tideStation") var selectedTideStationID: String
        = StationCatalog.tideStations.first!.id
    @AppStorage("watch.currentStation") var selectedCurrentStationKey: String
        = StationCatalog.currentStations.first!.stationKey
    @AppStorage("watch.unit") private var unitRaw: String = "feet"
    /// Most-recent-first, capped. The only "favourites" mechanism on the watch —
    /// a starring UI is not worth the taps at this screen size.
    @AppStorage("watch.recentStations") private var recentsRaw: String = ""

    var unit: TideUnit {
        get { unitRaw == "meters" ? .meters : .feet }
        set { unitRaw = newValue == .meters ? "meters" : "feet" }
    }

    var recents: [String] {
        recentsRaw.split(separator: ",").map(String.init)
    }

    func remember(_ id: String) {
        var list = recents.filter { $0 != id }
        list.insert(id, at: 0)
        recentsRaw = list.prefix(6).joined(separator: ",")
    }
}

/// Location, optional by construction. Never blocks a value from appearing.
@MainActor
final class WatchLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum State: Equatable {
        case notDetermined, denied, restricted, unavailable, located(CLLocation)
    }

    @Published private(set) var state: State = .notDetermined
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        sync()
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: manager.requestLocation()
        }
    }

    private func sync() {
        switch manager.authorizationStatus {
        case .notDetermined:  state = .notDetermined
        case .denied:         state = .denied
        case .restricted:     state = .restricted
        default:              manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) { sync() }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        if let l = locs.last { state = .located(l) }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        state = .unavailable
    }
}

struct WatchStationPickerView: View {
    @Binding var selection: String
    @Environment(\.watchTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var location = WatchLocationProvider()
    @ObservedObject private var store = WatchStationStore.shared

    /// Distance and initial bearing to a station — GeodesyKit, not arithmetic here.
    private func fix(_ from: CLLocation, _ r: TideStationRecord)
        -> (nm: Double, bearing: Double)? {
        let v = Vincenty.inverse(lat1: from.coordinate.latitude,
                                lon1: from.coordinate.longitude,
                                lat2: r.latitude, lon2: r.longitude)
        guard v.converged else { return nil }
        return (v.distanceM / 1852.0, v.azimuth1Deg)
    }

    var body: some View {
        List {
            switch location.state {
            case .located(let here):
                Section {
                    let ranked = StationCatalog.tideStations
                        .compactMap { r -> (TideStationRecord, Double, Double)? in
                            guard let f = fix(here, r) else { return nil }
                            return (r, f.nm, f.bearing)
                        }
                        .sorted { $0.1 < $1.1 }
                        .prefix(5)
                    ForEach(Array(ranked), id: \.0.id) { r, nm, brg in
                        row(r, trailing: String(format: "%.0f nm %03.0f°", nm, brg),
                            spoken: "\(Int(nm.rounded())) nautical miles, "
                                  + "bearing \(Int(brg.rounded())) degrees true")
                    }
                } header: { header("NEAREST") }

            case .notDetermined:
                Section {
                    Button {
                        location.request()
                    } label: {
                        Label("Find nearest", systemImage: "location")
                            .font(WatchType.label)
                    }
                    .frame(minHeight: WatchMetrics.target)
                    .accessibilityIdentifier("input.requestLocation")
                    Text("Optional. Marine Nav works fully without it and makes no network "
                         + "requests either way.")
                        .font(WatchType.caption)
                        .foregroundStyle(theme.palette.inkDim)
                } header: { header("LOCATION") }

            case .denied, .restricted, .unavailable:
                // First-class state. No red banner, no "error" — a statement and
                // then the list you actually need.
                Section {
                    Text("Location is off. Pick a station below — everything else is "
                         + "unchanged.")
                        .font(WatchType.caption)
                        .foregroundStyle(theme.palette.inkDim)
                        .accessibilityIdentifier("result.locationOff")
                } header: { header("LOCATION OFF") }
            }

            if !store.recents.isEmpty {
                Section {
                    ForEach(store.recents, id: \.self) { id in
                        if let r = StationCatalog.tideStations.first(where: { $0.id == id }) {
                            row(r, trailing: nil, spoken: nil)
                        }
                    }
                } header: { header("RECENT") }
            }

            Section {
                ForEach(StationCatalog.tideStations) { r in
                    row(r, trailing: nil, spoken: nil)
                }
            } header: { header("ALL STATIONS") }
        }
        .listStyle(.carousel)
        .background(theme.palette.canvas)
        .accessibilityIdentifier("tool.stationPicker")
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(WatchType.section)
            .tracking(0.7)
            .foregroundStyle(theme.palette.inkDim)
    }

    private func row(_ r: TideStationRecord, trailing: String?, spoken: String?) -> some View {
        Button {
            selection = r.id
            store.selectedTideStationID = r.id
            store.remember(r.id)
            dismiss()
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.name)
                        .font(WatchType.label)
                        .foregroundStyle(theme.ambientInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text([r.region, r.timeZone.abbreviation(for: Date()) ?? ""]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · "))
                        .font(WatchType.caption)
                        .foregroundStyle(theme.palette.inkDim)
                }
                Spacer(minLength: 4)
                if r.id == selection {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.palette.water)
                }
                if let trailing {
                    Text(trailing)
                        .font(WatchType.mono11)
                        .monospacedDigit()
                        .foregroundStyle(theme.palette.inkDim)
                }
            }
            .frame(minHeight: WatchMetrics.target)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("input.station.\(r.id)")
        .accessibilityLabel("\(r.name), times in "
                            + "\(r.timeZone.abbreviation(for: Date()) ?? r.timeZoneIdentifier)"
                            + (spoken.map { ", \($0)" } ?? ""))
    }
}

#Preview("Station picker — location off") {
    WatchStationPickerView(selection: .constant(StationCatalog.tideStations.first!.id))
        .environment(\.watchTheme, WatchTheme(mode: .dark))
}
