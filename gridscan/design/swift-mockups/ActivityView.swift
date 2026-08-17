import SwiftUI

// Activity — the user-facing audit trail. What happened, when, what left.
struct ActivityView: View {
    let events: [AuditEvent]

    var body: some View {
        List(events) { event in
            DisclosureGroup {
                // Expandable payload summary, e.g.:
                //   Soil sample log — Plot 7 · rows 1–41 · 3 columns
                //   Written to iCloud Drive/Exports/Plot 7.csv
                //   Included 1 row still marked for review   <- flags travel here too
                ForEach(event.detailLines, id: \.self) { line in
                    Text(line).font(.footnote).foregroundStyle(.secondary)
                }
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title).font(.subheadline.weight(.semibold))
                        Text(event.timestamp, style: .relative).font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: event.kind.symbolName) // plus / exclamationmark / pencil / arrow.up.right
                        .foregroundStyle(event.kind.tint)
                }
            }
        }
        .navigationTitle("Activity")
    }
}

enum AuditEventKind {
    case imported, importFailed, sent, learnedLayout, exportedFile

    var symbolName: String {
        switch self {
        case .imported: return "plus"
        case .importFailed: return "exclamationmark.circle.fill"
        case .sent, .exportedFile: return "arrow.up.right"
        case .learnedLayout: return "pencil"
        }
    }
}
