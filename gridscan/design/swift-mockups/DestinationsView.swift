import SwiftUI

// Destinations — a pluggable first-class object, not hardcoded buttons.
// Accounting/CRM targets arrive later and slot in without redesigning this.
struct Destination: Identifiable {
    let id: UUID
    var name: String
    var kind: DestinationKind    // TIER ONE: .csvFile, .xlsxFile.
                                 // LATER: .webhook (blocked on a deferred payload
                                 // contract) — slots in with zero redesign here.
    var isEnabled: Bool
    var lastSent: Date?
    var fieldMapping: [FieldMapEntry]
    // Credentials live in the Keychain. The UI says so plainly, once.
}

struct DestinationsView: View {
    @State private var destinations: [Destination]
    @State private var selected: Destination.ID?

    init(destinations: [Destination]) { _destinations = State(initialValue: destinations) }

    var body: some View {
        NavigationSplitView {
            List(destinations, selection: $selected) { dest in
                DestinationRow(destination: dest)
            }
            .navigationTitle("Destinations")
            .toolbar { Button { /* add: pick kind, name, configure, test */ } label: { Image(systemName: "plus") } }
        } detail: {
            if let dest = destinations.first(where: { $0.id == selected }) {
                DestinationDetailView(destination: dest)
            }
        }
    }
}

struct DestinationDetailView: View {
    let destination: Destination
    @State private var testResult: TestResult?

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: destination.name)
                LabeledContent("Writes to", value: destination.kind.targetDescription)
                LabeledContent("Format", value: destination.kind.formatDescription)
                HStack {
                    Button("Test") { Task { testResult = await destination.kind.test() } }
                    if let testResult { TestResultLabel(result: testResult) } // "✓ Test succeeded · 200 OK"
                }
            } footer: {
                Text("Credentials are stored in your Keychain.") // plainly, no marketing tone
            }
            Section("Field mapping") {
                // ONE generic mapper for every destination kind, present and future.
                // Left side = whatever fields the document's table has (never predefined).
                ForEach(destination.fieldMapping) { entry in
                    FieldMapRow(entry: entry) // source field → destination field; auto/manual marked
                }
            }
            Section {
                // Nothing leaves until the user taps — per destination.
                Button("Send \(pendingRowCount) rows") { /* confirm, then audit */ }
                    .buttonStyle(.glassProminent)
            } footer: {
                Text("Every send is recorded in Activity: what happened, when, and what left.")
            }
        }
        .navigationTitle(destination.name)
        .toolbar { Button(destination.isEnabled ? "Disable" : "Enable") {}.buttonStyle(.glass) }
    }
}
