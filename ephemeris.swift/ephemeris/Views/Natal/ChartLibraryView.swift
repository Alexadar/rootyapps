import SwiftUI
import EphemerisKit

/// The saved charts, and the way into one.
///
/// The empty state is the screen a new buyer sees first, so it carries the primary action rather
/// than an apology. Deletion is `.destructive` with a confirmation because the competing apps'
/// loudest complaint is charts vanishing — losing one to a mis-swipe would land in the same review.
struct ChartLibraryView: View {
    @ObservedObject var vm: NatalViewModel
    @State private var editing: SavedChart?
    @State private var pendingDelete: SavedChart?

    var body: some View {
        Group {
            if let error = vm.loadError {
                // Never render an empty list for a failed load — that reads as "you have no charts"
                // and is how a user concludes their library was lost.
                ContentUnavailableView(
                    "Charts", systemImage: "exclamationmark.triangle",
                    description: Text(verbatim: error))
            } else if vm.charts.isEmpty {
                emptyState
            } else {
                list
            }
        }
        // Identifies the section whatever it is showing. The inner states — empty, error, list —
        // each have their own identifier, but a deep-link test needs one marker that is present in
        // all three, or it passes or fails depending on whether the library happens to have charts.
        .accessibilityIdentifier("screen.natal")
        .navigationTitle("Charts")
        // Also refreshes after another device wrote a chart while this one was backgrounded.
        .task { vm.reload() }
        .toolbar {
            Button { editing = blankChart() } label: { Label("New chart", systemImage: "plus") }
                .accessibilityIdentifier("input.newChart")
        }
        .sheet(item: $editing) { chart in
            BirthDataEntryView(chart: chart) { saved in
                vm.save(saved)
                editing = nil
            }
        }
        .confirmationDialog("Charts", isPresented: .constant(pendingDelete != nil)) {
            Button("Delete", role: .destructive) {
                if let c = pendingDelete { vm.delete(c) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Charts", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("No saved charts yet.")
        } actions: {
            Button("New chart") { editing = blankChart() }
                .buttonStyle(.borderedProminent)
        }
        .accessibilityIdentifier("state.libraryEmpty")
    }

    private var list: some View {
        List {
            ForEach(vm.charts) { chart in
                Button { vm.openChart = chart } label: { row(chart) }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", role: .destructive) { pendingDelete = chart }
                    }
            }
            storageFooter
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.chartLibrary")
    }

    /// Says plainly where the charts live.
    ///
    /// Worth a row of its own for two reasons. The competing apps' loudest reviews are charts
    /// vanishing into a store the user cannot see, so "these are files in your iCloud Drive, and you
    /// can open them" is a real answer. And when iCloud is *unavailable* the user must be told the
    /// charts are on this device only — a second device showing an empty library is otherwise
    /// indistinguishable from data loss.
    @ViewBuilder
    private var storageFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: vm.storage == .iCloud ? "icloud" : "internaldrive")
            switch vm.storage {
            case .iCloud: Text("Charts are stored in your iCloud Drive.")
            case .local:  Text("Charts are stored on this device only.")
            }
        }
        .font(.caption)
        .foregroundStyle(NebulaPalette.textSecondary)
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("state.storageKind")
    }

    private func row(_ chart: SavedChart) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: chart.name).font(.headline)
            HStack(spacing: 6) {
                Text(chart.birthInstant, format: .dateTime.day().month(.abbreviated).year())
                if let place = chart.placeName { Text(verbatim: "· " + place) }
                // An untimed chart must be visibly untimed everywhere it appears, or it will
                // eventually be read as a precise one.
                if !chart.isTimeKnown {
                    Text("Birth time unknown")
                        .foregroundStyle(NebulaPalette.retrograde)
                }
            }
            .font(.caption)
            .foregroundStyle(NebulaPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityIdentifier("chart.\(chart.id.uuidString)")
    }

    private func blankChart() -> SavedChart {
        SavedChart(name: "",
                   birthInstant: Date(),
                   timeZoneID: TimeZone.current.identifier,
                   latitude: 0, longitude: 0)
    }
}
