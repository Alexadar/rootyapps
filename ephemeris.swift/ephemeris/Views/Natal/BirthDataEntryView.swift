import SwiftUI
import EphemerisKit



/// Enter birth data, and see the chart resolve while typing.
///
/// The live readout is the point of the screen, not decoration. Everything downstream depends on
/// four fields the app cannot validate, and a silent thirty-minute error produces a chart that is
/// plausible and wrong. Showing the resolved UTC instant, the zone in force, and the Ascendant it
/// produces lets the user catch that themselves — which is the same argument as publishing the
/// JPL accuracy numbers instead of asking to be trusted.
///
/// **The timezone is never inferred.** Historical DST and local mean time make place→zone
/// resolution unsafe for older births, so it is picked and shown, never guessed.
struct BirthDataEntryView: View {
    @State var chart: SavedChart
    let onSave: (SavedChart) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    /// Bridges the record's flat lat/lon/name to the shared picker's `GeoLocation?`.
    ///
    /// Nil specifically when nothing has been chosen — 0,0 is the Atlantic off Africa, and treating
    /// it as a real place would silently produce houses for a chart that has no location.
    private var birthPlace: Binding<GeoLocation?> {
        Binding(
            get: {
                (chart.latitude == 0 && chart.longitude == 0 && chart.placeName == nil)
                    ? nil : chart.location
            },
            set: { new in
                chart.latitude = new?.latitude ?? 0
                chart.longitude = new?.longitude ?? 0
                chart.placeName = new?.name
            })
    }

    /// The record stores the identifier, not a `TimeZone`, so the chart can be audited later — see
    /// `SavedChart.timeZoneID`.
    private var birthTimeZone: Binding<TimeZone> {
        Binding(get: { chart.timeZone }, set: { chart.timeZoneID = $0.identifier })
    }

    /// Ascendant moves roughly 1° every 4 minutes, so a 10-minute error can change the rising sign.
    /// Showing it live is what makes that visible while the user still has the birth certificate open.
    private var preview: (ascendant: String, sun: String)? {
        let positions = chart.positions
        guard let sun = positions.first(where: { $0.body == .sun }) else { return nil }
        let asc = chart.houses(system: .placidus).map { HousesCard.degMin($0.angles.ascendant) }
        return (asc ?? "—", sun.degMinString)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $chart.name)
                        .accessibilityIdentifier("input.chartName")
                }

                Section {
                    DatePicker("Birth date", selection: $chart.birthInstant,
                               displayedComponents: [.date])
                        .accessibilityIdentifier("input.birthDate")

                    Toggle("Birth time unknown", isOn: Binding(
                        get: { !chart.isTimeKnown },
                        set: { chart.isTimeKnown = !$0 }))
                        .accessibilityIdentifier("input.timeUnknown")

                    if chart.isTimeKnown {
                        DatePicker("Birth time", selection: $chart.birthInstant,
                                   displayedComponents: [.hourAndMinute])
                            .accessibilityIdentifier("input.birthTime")
                    } else {
                        Text("Houses and angles need a birth time.")
                            .font(.caption)
                            .foregroundStyle(NebulaPalette.textSecondary)
                    }
                }

                Section {
                    // The app's own pickers, not copies. Both already handle offline lookup and
                    // search; a second implementation here would drift the moment either is fixed.
                    LocationRow(location: birthPlace)
                        .accessibilityIdentifier("input.birthPlace")

                    TimeZoneRow(timeZone: birthTimeZone)
                        .accessibilityIdentifier("input.birthTimeZone")
                }

                verification
            }
            .navigationTitle("Natal chart")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(chart) }
                        .disabled(chart.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// What the app understood — shown before saving, so a wrong zone is caught here rather than
    /// discovered later in a chart that looked fine.
    private var verification: some View {
        Section {
            LabeledContent("Time zone") { Text(verbatim: chart.timeZoneID) }
            LabeledContent(String("UTC")) {
                Text(chart.birthInstant, format: .dateTime.year().month().day().hour().minute())
            }
            if let preview {
                LabeledContent("Sun") { Text(verbatim: preview.sun).monospacedDigit() }
                LabeledContent("Ascendant") {
                    Text(verbatim: preview.ascendant).monospacedDigit()
                }
                .accessibilityIdentifier("result.previewAscendant")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.birthVerification")
    }
}
