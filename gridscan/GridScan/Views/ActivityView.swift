import SwiftUI

// Activity — the user-facing audit trail. What happened, when, what left.
struct ActivityView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var events: [AuditEvent] = []

    var body: some View {
        Group {
            if events.isEmpty {
                ContentUnavailableView {
                    Label("No activity yet", systemImage: "clock")
                } description: {
                    Text("Imports, corrections, and exports are recorded here.")
                }
            } else {
                List(events) { event in
                    DisclosureGroup {
                        ForEach(event.detailLines, id: \.self) { line in
                            Text(line).font(.footnote).foregroundStyle(.secondary)
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title).font(.subheadline.weight(.semibold))
                                Text(event.timestamp, style: .relative)
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: symbol(for: event.kind))
                                .foregroundStyle(tint(for: event.kind))
                        }
                    }
                    .accessibilityIdentifier("activity.row.\(event.id.uuidString)")
                }
            }
        }
        .navigationTitle("Activity")
        .task { await refresh(); await observe() }
    }

    private func refresh() async {
        events = (try? await env.store.allEvents()) ?? []
    }

    private func observe() async {
        for await _ in await env.store.changes() { await refresh() }
    }

    private func symbol(for kind: AuditEventKind) -> String {
        switch kind {
        case .imported: return "plus"
        case .importFailed: return "exclamationmark.circle.fill"
        case .corrected: return "pencil"
        case .structureChanged: return "square.split.1x2"
        case .exportedFile: return "arrow.up.right"
        case .deleted: return "trash"
        }
    }

    private func tint(for kind: AuditEventKind) -> Color {
        switch kind {
        case .importFailed: return GS.flagText
        case .corrected: return GS.corrected
        default: return .secondary
        }
    }
}
