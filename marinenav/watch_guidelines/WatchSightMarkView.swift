import SwiftUI
import AppIntents
import WatchKit

// ─────────────────────────────────────────────────────────────────────────────
// F4 · SIGHT MARK — the reason this app belongs on a wrist.
//
// A celestial sight is only as good as the instant you record it: one second of
// time error is about a quarter of a mile of longitude. Traditionally you shout
// "mark!" to someone with a stopwatch. Here the wrist IS the stopwatch.
//
// Design rules this screen is built on:
//  1. EYES-FREE. The target is the whole screen below the header — you press it
//     with the heel of a gloved hand while your eye stays on the sextant. There
//     is no other tappable thing on the screen while marking.
//  2. TIMESTAMP FIRST, UI SECOND. `Date()` is read on the first line of the
//     action, before any state mutation, animation or haptic.
//  3. UTC IS THE PRIMARY FACE. Sight reduction takes UT — the almanac is
//     tabulated in it. Station-local time is shown underneath for the log.
//  4. HAPTIC IS THE CONFIRMATION, not the label change: `.success` fires so the
//     mark is confirmed without looking.
//  5. Marks are a LIST, not a form. Altitude is entered later on the phone,
//     where a sextant reading can actually be typed.
//
// ⚠ DOCUMENTED SEAM — no math, and one number we deliberately do NOT show. The
// accuracy of a mark is bounded by the watch's own clock error, which we cannot
// measure: the app makes no network requests, so there is no time source to
// compare against. We therefore state the limitation on screen and never imply
// millisecond ACCURACY — only millisecond RESOLUTION. Do not add an NTP check.
// ─────────────────────────────────────────────────────────────────────────────

struct SightMark: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    var note: String

    init(id: UUID = UUID(), date: Date, note: String = "") {
        self.id = id
        self.date = date
        self.note = note
    }
}

/// Marks live in a file in the app's own container. No app group, no phone, no
/// network — the watch app runs independently.
@MainActor
final class SightMarkStore: ObservableObject {
    static let shared = SightMarkStore()

    @Published private(set) var marks: [SightMark] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sight-marks.json")
    }()

    init() { load() }

    /// `at:` is passed in by the caller, which captured it BEFORE doing anything
    /// else. Never call `Date()` in here.
    func record(at instant: Date) {
        marks.insert(SightMark(date: instant), at: 0)
        marks = Array(marks.prefix(50))
        save()
    }

    func annotate(_ id: UUID, note: String) {
        guard let i = marks.firstIndex(where: { $0.id == id }) else { return }
        marks[i].note = note
        save()
    }

    func delete(_ id: UUID) {
        marks.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([SightMark].self, from: data) else { return }
        marks = list
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(marks) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Action Button (Ultra) — accelerant, never the primary control
//
// Third-party access to the Action button is through an App Intent that the USER
// assigns in Settings › Action Button. The app cannot seize the button, and on
// non-Ultra models it does not exist at all. So the on-screen control is the
// design; this intent is a bonus. Registering it also gets the mark into
// Shortcuts, Siri and the Smart Stack for free.

struct RecordSightMarkIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark a Sight"
    static var description = IntentDescription(
        "Timestamps the instant of a celestial observation, to the millisecond.")
    /// The point of the whole feature: no launch, no confirmation, no UI.
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let instant = Date()          // first line. always.
        SightMarkStore.shared.record(at: instant)
        WKInterfaceDevice.current().play(.success)
        return .result(dialog: IntentDialog("Marked \(WatchFormat.timeMillis(instant, zone: .gmt)) UTC"))
    }
}

struct MarineNavShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordSightMarkIntent(),
                    phrases: ["Mark a sight in \(.applicationName)",
                              "\(.applicationName) mark"],
                    shortTitle: "Mark",
                    systemImageName: "dot.circle.and.hand.point.up.left.fill")
    }
}

// MARK: - Screen

struct WatchSightMarkView: View {
    @ObservedObject private var store = SightMarkStore.shared
    @Environment(\.watchTheme) private var theme
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    /// The just-taken mark, held for a few seconds so a glance confirms it.
    @State private var lastMark: SightMark?
    @State private var showLog = false

    var body: some View {
        GeometryReader { geo in
            let size = WatchSize.measuring(geo.size.width)
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text("SIGHT MARK")
                        .font(WatchType.section).tracking(0.8)
                        .foregroundStyle(theme.palette.inkDim)
                    Spacer(minLength: 2)
                    Button {
                        showLog = true
                    } label: {
                        HStack(spacing: 3) {
                            Text("\(store.marks.count)")
                                .font(WatchType.mono11).monospacedDigit()
                            Image(systemName: "list.bullet")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .frame(minWidth: 44, minHeight: 26, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.palette.water)
                    .accessibilityIdentifier("input.showMarkLog")
                    .accessibilityLabel("Recent marks, \(store.marks.count) recorded")
                }

                // THE control. Everything else on this screen is smaller than it.
                Button {
                    let instant = Date()               // first line. always.
                    store.record(at: instant)
                    WKInterfaceDevice.current().play(.success)
                    lastMark = store.marks.first
                } label: {
                    VStack(spacing: 2) {
                        Text("MARK")
                            .font(.system(size: size == .compact ? 30 : 36,
                                          weight: .heavy, design: .rounded))
                            .tracking(2)
                        Text("tap anywhere")
                            .font(WatchType.caption)
                            .foregroundStyle(theme.palette.inkDim)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: max(geo.size.height * 0.34, 68))
                    .foregroundStyle(theme.palette.caution)
                    .background(theme.palette.caution.opacity(luminanceReduced ? 0.06 : 0.14),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(theme.palette.caution.opacity(0.55), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("input.mark")
                .accessibilityLabel("Mark a sight. Records the current instant to the millisecond.")

                if let m = lastMark {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(WatchFormat.timeMillis(m.date, zone: .gmt))
                                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(theme.ambientHero)
                            Text("UTC")
                                .font(WatchType.mono11)
                                .foregroundStyle(theme.palette.inkDim)
                        }
                        Text("\(WatchFormat.timeMillis(m.date, zone: .current)) local")
                            .font(WatchType.caption)
                            .foregroundStyle(theme.palette.inkDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("result.lastMark")
                    .accessibilityLabel("Last mark "
                                        + "\(WatchFormat.timeMillis(m.date, zone: .gmt)) "
                                        + "coordinated universal time")
                } else {
                    Text("No marks yet. Press MARK at the instant of the sight.")
                        .font(WatchType.caption)
                        .foregroundStyle(theme.palette.inkDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !luminanceReduced {
                    Text("Millisecond RESOLUTION, not accuracy — a mark is only as good as this "
                         + "watch's clock, and Marine Nav makes no network requests to check it.")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.palette.inkDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, size.gutter)
            .padding(.vertical, 4)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(theme.palette.canvas)
        }
        .environment(\.watchTheme, luminanceReduced ? theme.dimmed : theme)
        .sheet(isPresented: $showLog) { WatchMarkLogView() }
    }
}

/// Recent marks: UTC to the millisecond, station-local underneath, plus a note
/// the user can dictate. Altitude is paired later, on the phone.
struct WatchMarkLogView: View {
    @ObservedObject private var store = SightMarkStore.shared
    @Environment(\.watchTheme) private var theme
    @State private var editing: SightMark?

    var body: some View {
        List {
            if store.marks.isEmpty {
                Text("No marks recorded.")
                    .font(WatchType.caption)
                    .foregroundStyle(theme.palette.inkDim)
            }
            ForEach(store.marks) { m in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(WatchFormat.timeMillis(m.date, zone: .gmt))
                            .font(WatchType.value)
                            .monospacedDigit()
                            .foregroundStyle(theme.ambientInk)
                        Text("UTC")
                            .font(WatchType.mono11)
                            .foregroundStyle(theme.palette.inkDim)
                    }
                    Text(m.note.isEmpty
                         ? WatchFormat.timeMillis(m.date, zone: .current) + " local"
                         : m.note)
                        .font(WatchType.caption)
                        .foregroundStyle(theme.palette.inkDim)
                        .lineLimit(2)
                }
                .frame(minHeight: WatchMetrics.target)
                .accessibilityIdentifier("result.mark.\(m.id.uuidString)")
                .accessibilityLabel("Mark \(WatchFormat.timeMillis(m.date, zone: .gmt)) "
                                    + "coordinated universal time"
                                    + (m.note.isEmpty ? "" : ", note \(m.note)"))
                .swipeActions {
                    Button(role: .destructive) { store.delete(m.id) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { editing = m } label: {
                        Label("Note", systemImage: "text.bubble")
                    }
                }
            }
        }
        .listStyle(.carousel)
        .background(theme.palette.canvas)
        .accessibilityIdentifier("tool.markLog")
        .sheet(item: $editing) { mark in
            WatchNoteEntryView(mark: mark) { store.annotate(mark.id, note: $0) }
        }
    }
}

/// Note entry. Dictation and Scribble only — a sextant altitude is NOT typed
/// here; it is paired on the phone, where a numeric field with an explicit range
/// exists.
struct WatchNoteEntryView: View {
    let mark: SightMark
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.watchTheme) private var theme
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(WatchFormat.timeMillis(mark.date, zone: .gmt) + " UTC")
                .font(WatchType.mono13)
                .foregroundStyle(theme.palette.inkDim)
            TextField("Body, e.g. Sun LL", text: $text)
                .font(WatchType.label)
                .accessibilityIdentifier("input.markNote")
            Button("Save") {
                onSave(text)
                dismiss()
            }
            .frame(minHeight: WatchMetrics.target)
        }
        .padding(8)
        .background(theme.palette.canvas)
        .onAppear { text = mark.note }
    }
}

#Preview("Sight mark — dusk") {
    WatchSightMarkView().environment(\.watchTheme, WatchTheme(mode: .dark))
}

#Preview("Sight mark — night red") {
    WatchSightMarkView().environment(\.watchTheme, WatchTheme(mode: .nightRed))
}
