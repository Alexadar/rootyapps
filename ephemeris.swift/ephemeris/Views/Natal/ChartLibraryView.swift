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
    /// For the navigation title, which cannot rely on the environment reaching it — see below.
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let error = vm.loadError {
                // Never render an empty list for a failed load — that reads as "you have no charts"
                // and is how a user concludes their library was lost.
                ContentUnavailableView(
                    "Natal charts", systemImage: "exclamationmark.triangle",
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
        // The PAGE says the long form; the tab stays the short "Charts".
        //
        // Resolved through `L.string` rather than passed as a LocalizedStringKey, for the same
        // reason `NebulaCardHeader` does it: a navigation title is hoisted out of the view into the
        // window/toolbar chrome, and on macOS it is rendered outside this view's `\.locale`
        // override — so the key was looked up in the system language and the French Mac screenshot
        // showed "Natal charts" in English above a fully French sidebar and list. Same failure the
        // watch app had before it resolved its locale explicitly.
        .navigationTitle(Text(verbatim: L.string("Natal charts", locale: locale)))
        // Also refreshes after another device wrote a chart while this one was backgrounded.
        .task {
            vm.reload()
            await openLaunchChart()
        }
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
        .confirmationDialog("Natal charts", isPresented: .constant(pendingDelete != nil)) {
            Button("Delete", role: .destructive) {
                if let c = pendingDelete { vm.delete(c) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Natal charts", systemImage: "person.crop.circle.badge.plus")
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
        // Same shape for the same reason: icon + text would otherwise publish two elements sharing
        // one identifier.
        .accessibilityElement(children: .combine)
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
        // `.combine` FIRST, then name the result. Without the combine, macOS fuses the row's
        // children itself and synthesises a joined identifier —
        // "chart.<uuid>-chart.<uuid>-chart.<uuid>" — so the plain id matches nothing and every
        // natal UI test failed on macOS while passing on iOS. Trap 4.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chart.\(chart.id.uuidString)")
    }

    /// Opens a seeded chart straight from the launch environment, for store captures.
    ///
    /// The screenshot pipeline takes one shot per fresh launch — the screen is chosen by environment
    /// rather than by tapping, so a capture can never race an in-flight animation or a list that has
    /// not finished loading. Every other screen was already reachable that way via `EPHEMERIS_TAB`;
    /// the natal screens were not, because they live one level down behind a row tap.
    ///
    /// **Addressed by UUID prefix, never by row index.** `all()` sorts by `modifiedAt` descending,
    /// and the seeded fixtures are all stamped in the same instant — so "row 0" is whichever chart
    /// the sort happened to put first, and a capture keyed on it would silently shoot a different
    /// person's chart on a different run. A prefix of the fixture's fixed UUID is unambiguous, and it
    /// is the same identifier scheme the natal UI tests already address rows by.
    ///
    /// `LaunchOverride` is `#if DEBUG`, so this is inert in a shipping build.
    ///
    /// **Yields before assigning.** Setting `openChart` in the same update in which the
    /// `NavigationStack` first appears is swallowed on macOS: the value lands on the view model and
    /// no push ever happens. It is not a race that a longer settle fixes — a nine-second wait still
    /// captured the library. Tapping a row works, which is exactly why the natal UI tests (which
    /// tap) pass on macOS while the launch deep link silently did nothing, and why the first mac
    /// screenshot run produced three shots of the library under captions promising a birth chart.
    /// One turn of the run loop is enough for the stack to finish appearing.
    private func openLaunchChart() async {
        await Task.yield()
        guard vm.openChart == nil,
              let wanted = LaunchOverride.value("EPHEMERIS_CHART")?.lowercased(),
              let match = vm.charts.first(where: {
                  $0.id.uuidString.lowercased().hasPrefix(wanted)
              })
        else { return }
        vm.openChart = match
    }

    private func blankChart() -> SavedChart {
        SavedChart(name: "",
                   birthInstant: Date(),
                   timeZoneID: TimeZone.current.identifier,
                   latitude: 0, longitude: 0)
    }
}
