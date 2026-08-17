import SwiftUI

// Destinations — a pluggable first-class object, not hardcoded buttons. Tier one ships
// the two FILE kinds; .webhook is LATER (blocked on a deferred payload contract) and
// has no entry here. Nothing leaves the device except a user-tapped export, and every
// export lands in Activity.
struct DestinationsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var selected: ExportKind? = .csvFile

    var body: some View {
        List(ExportKind.allCases, selection: $selected) { kind in
            NavigationLink(value: kind) {
                Label(kind.displayName,
                      systemImage: kind == .csvFile ? "tablecells" : "doc.badge.arrow.up")
            }
            .accessibilityIdentifier("dest.kind.\(kind.rawValue)")
        }
        .navigationTitle("Destinations")
        .navigationDestination(for: ExportKind.self) { kind in
            DestinationDetailView(kind: kind)
        }
    }
}

struct DestinationDetailView: View {
    let kind: ExportKind

    var body: some View {
        Form {
            Section {
                LabeledContent("Writes to", value: "A file you choose")
                LabeledContent("Format", value: kind.formatDescription)
            } footer: {
                Text("Nothing leaves this device until you tap Export inside a document. "
                     + "Every export is recorded in Activity: what happened, when, and "
                     + "what left.")
            }
            Section("Columns") {
                // The generic mapper's tier-one form: file exports carry the document's
                // own columns, exactly as read — the product defines none of its own.
                Text("Every export carries the document\u{2019}s own columns, exactly "
                     + "as read.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(kind.displayName)
    }
}
