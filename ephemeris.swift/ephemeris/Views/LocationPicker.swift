import SwiftUI
import EphemerisKit

/// The Moment-card place row: shows the observer's location and opens a picker.
/// Houses and the angles need a place; everything else in the app works without one.
struct LocationRow: View {
    @Binding var location: GeoLocation?
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            HStack {
                Text("Place").foregroundStyle(.secondary)
                Spacer()
                if let location {
                    Text(location.name ?? location.coordinateString)
                        .foregroundStyle(.primary).lineLimit(1)
                } else {
                    Text("Set for houses").foregroundStyle(NebulaPalette.accent)
                }
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $picking) { LocationPicker(selected: $location) }
    }
}

/// Pick a place from a small built-in list, or type coordinates directly.
///
/// Deliberately offline: no CoreLocation, no permission prompt, no geocoding request. The
/// coordinates never leave the device — they're only saved to `UserDefaults`.
struct LocationPicker: View {
    @Binding var selected: GeoLocation?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var latText = ""
    @State private var lonText = ""

    private var filtered: [City] {
        query.isEmpty ? City.all : City.all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// Parsed coordinates, if both fields hold something sane.
    private var typed: GeoLocation? {
        guard let lat = Double(latText.replacingOccurrences(of: ",", with: ".")),
              let lon = Double(lonText.replacingOccurrences(of: ",", with: ".")),
              abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return GeoLocation(latitude: lat, longitude: lon)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Coordinates") {
                    HStack {
                        LabeledField(label: "Lat", text: $latText, placeholder: "50.45")
                        LabeledField(label: "Lon", text: $lonText, placeholder: "30.52")
                    }
                    Button("Use these coordinates") {
                        if let typed { selected = typed; dismiss() }
                    }
                    .disabled(typed == nil)
                    Text("North and east are positive. Nothing is looked up online.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Cities") {
                    ForEach(filtered) { city in
                        Button {
                            selected = city.location
                            dismiss()
                        } label: {
                            HStack {
                                Text(city.name)
                                Spacer()
                                Text(city.location.coordinateString)
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                if selected?.name == city.name {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if selected != nil {
                    Section {
                        Button("Clear place", role: .destructive) { selected = nil; dismiss() }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search cities")
            .navigationTitle("Place")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 360, minHeight: 460)
        .onAppear {
            if let s = selected {
                latText = String(format: "%.4f", s.latitude)
                lonText = String(format: "%.4f", s.longitude)
            }
        }
    }

    private struct LabeledField: View {
        // LocalizedStringKey, not String: "Lat"/"Lon" are in the catalog, but a String property
        // routes Text/TextField to their verbatim overloads and never looks them up.
        let label: LocalizedStringKey
        @Binding var text: String
        /// Stays a String: the placeholders are sample coordinates ("50.45"), and typing them as a
        /// key would put two numbers in the catalog for translators to "translate".
        let placeholder: String
        var body: some View {
            HStack(spacing: 6) {
                Text(label).foregroundStyle(.secondary)
                TextField(placeholder, text: $text)
                    .monospacedDigit()
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    #endif
            }
        }
    }
}

/// A tiny built-in gazetteer — enough to be useful offline without shipping a database.
/// Coordinates are city-centre values rounded to two decimals (~1 km), which is far finer
/// than house cusps need.
struct City: Identifiable, Hashable {
    let name: String
    let latitude: Double
    let longitude: Double

    var id: String { name }
    var location: GeoLocation { GeoLocation(latitude: latitude, longitude: longitude, name: name) }

    static let all: [City] = [
        City(name: "Amsterdam",      latitude:  52.37, longitude:    4.90),
        City(name: "Athens",         latitude:  37.98, longitude:   23.73),
        City(name: "Auckland",       latitude: -36.85, longitude:  174.76),
        City(name: "Bangkok",        latitude:  13.76, longitude:  100.50),
        City(name: "Beijing",        latitude:  39.90, longitude:  116.41),
        City(name: "Berlin",         latitude:  52.52, longitude:   13.40),
        City(name: "Buenos Aires",   latitude: -34.60, longitude:  -58.38),
        City(name: "Cairo",          latitude:  30.04, longitude:   31.24),
        City(name: "Cape Town",      latitude: -33.92, longitude:   18.42),
        City(name: "Chicago",        latitude:  41.88, longitude:  -87.63),
        City(name: "Delhi",          latitude:  28.61, longitude:   77.21),
        City(name: "Dubai",          latitude:  25.20, longitude:   55.27),
        City(name: "Dublin",         latitude:  53.35, longitude:   -6.26),
        City(name: "Istanbul",       latitude:  41.01, longitude:   28.98),
        City(name: "Johannesburg",   latitude: -26.20, longitude:   28.05),
        City(name: "Kyiv",           latitude:  50.45, longitude:   30.52),
        City(name: "Lagos",          latitude:   6.52, longitude:    3.38),
        City(name: "Lisbon",         latitude:  38.72, longitude:   -9.14),
        City(name: "London",         latitude:  51.51, longitude:   -0.13),
        City(name: "Los Angeles",    latitude:  34.05, longitude: -118.24),
        City(name: "Madrid",         latitude:  40.42, longitude:   -3.70),
        City(name: "Mexico City",    latitude:  19.43, longitude:  -99.13),
        City(name: "Miami",          latitude:  25.76, longitude:  -80.19),
        City(name: "Moscow",         latitude:  55.76, longitude:   37.62),
        City(name: "Mumbai",         latitude:  19.08, longitude:   72.88),
        City(name: "Nairobi",        latitude:  -1.29, longitude:   36.82),
        City(name: "New York",       latitude:  40.71, longitude:  -74.01),
        City(name: "Oslo",           latitude:  59.91, longitude:   10.75),
        City(name: "Paris",          latitude:  48.86, longitude:    2.35),
        City(name: "Reykjavík",      latitude:  64.15, longitude:  -21.94),
        City(name: "Rio de Janeiro", latitude: -22.91, longitude:  -43.17),
        City(name: "Rome",           latitude:  41.90, longitude:   12.50),
        City(name: "San Francisco",  latitude:  37.77, longitude: -122.42),
        City(name: "São Paulo",      latitude: -23.55, longitude:  -46.63),
        City(name: "Seattle",        latitude:  47.61, longitude: -122.33),
        City(name: "Seoul",          latitude:  37.57, longitude:  126.98),
        City(name: "Singapore",      latitude:   1.35, longitude:  103.82),
        City(name: "Stockholm",      latitude:  59.33, longitude:   18.07),
        City(name: "Sydney",         latitude: -33.87, longitude:  151.21),
        City(name: "Tokyo",          latitude:  35.68, longitude:  139.69),
        City(name: "Toronto",        latitude:  43.65, longitude:  -79.38),
        City(name: "Vancouver",      latitude:  49.28, longitude: -123.12),
        City(name: "Vienna",         latitude:  48.21, longitude:   16.37),
        City(name: "Warsaw",         latitude:  52.23, longitude:   21.01),
        City(name: "Zürich",         latitude:  47.38, longitude:    8.54),
    ]
}
