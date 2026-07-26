import SwiftUI

/// The Moment-card time-zone row: shows the current zone + offset and opens a searchable
/// picker over all IANA zones. The chosen zone is persisted by `ChartViewModel`.
struct TimeZoneRow: View {
    @Binding var timeZone: TimeZone
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            HStack {
                Text("Time zone").foregroundStyle(.secondary)
                Spacer()
                Text(TimeZonePicker.label(timeZone)).monospacedDigit().foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $picking) { TimeZonePicker(selected: $timeZone) }
    }
}

/// A searchable list of every IANA time zone with its current UTC offset.
struct TimeZonePicker: View {
    @Binding var selected: TimeZone
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private static let all: [String] = TimeZone.knownTimeZoneIdentifiers.sorted()
    private var filtered: [String] {
        query.isEmpty ? Self.all : Self.all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.self) { id in
                Button {
                    if let tz = TimeZone(identifier: id) { selected = tz }
                    dismiss()
                } label: {
                    HStack {
                        Text(id.replacingOccurrences(of: "_", with: " "))
                        Spacer()
                        if let tz = TimeZone(identifier: id) {
                            Text(Self.offset(tz)).foregroundStyle(.secondary).monospacedDigit()
                        }
                        if id == selected.identifier {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $query, prompt: "Search time zones")
            .navigationTitle("Time zone")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 360, minHeight: 460)
    }

    /// "City · UTC+3" for the compact row.
    static func label(_ tz: TimeZone) -> String {
        let city = tz.identifier.split(separator: "/").last
            .map { $0.replacingOccurrences(of: "_", with: " ") } ?? tz.identifier
        return "\(city) · \(offset(tz))"
    }

    /// Current UTC offset like "UTC+3" / "UTC+5:30" / "UTC−4".
    static func offset(_ tz: TimeZone) -> String {
        let secs = tz.secondsFromGMT()
        let sign = secs < 0 ? "−" : "+"
        let h = abs(secs) / 3600, m = (abs(secs) % 3600) / 60
        return m == 0 ? "UTC\(sign)\(h)" : "UTC\(sign)\(h):\(String(format: "%02d", m))"
    }
}
