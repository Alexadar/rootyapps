import SwiftUI
#if canImport(MusicUnderstanding)
import MusicUnderstanding
#endif

// Audio Analysis — a SOURCE, not tool #27. See DESIGN_GUIDELINES.md §10.
// Absent-safe: on the released SDK the Measure entry is never inserted and
// nothing else in this file does anything.

// MARK: - Catalog model

/// `Tool` is a closed enum where every case implies a Kit and a detail view, so
/// Measure cannot be a case of it. The catalog becomes a sibling enum instead.
/// This is the one structural change the feature requires — it touches
/// CatalogGrid and the RootView sidebar only.
enum CatalogEntry: Hashable, Identifiable {
    case source(Source)
    case tool(Tool)

    enum Source: String, Hashable { case measure }

    var id: String {
        switch self {
        case .source(let s): return "source." + s.rawValue
        case .tool(let t):   return t.rawValue
        }
    }

    /// The absent case is a missing array element, never a disabled row.
    static var sources: [CatalogEntry] {
        guard AnalysisAvailability.isAvailable else { return [] }
        return [.source(.measure)]
    }
}

enum AnalysisAvailability {
    static var isAvailable: Bool {
        #if canImport(MusicUnderstanding)
        if #available(iOS 27, macOS 27, *) { return true }
        #endif
        return false
    }
}

// MARK: - Session store  (framework-independent — compiles on every OS)

/// Held by `RootView` as a `@StateObject`, a sibling of `FavoritesStore`.
/// Results therefore live OUTSIDE the navigation stack: popping Measure
/// discards a view, not a session, so Analysis → tool → back is free.
@MainActor
final class MeasurementStore: ObservableObject {
    struct Session: Codable, Equatable {
        var id: UUID = UUID()
        var sourceName: String          // "Take 3.wav" or "Live input"
        var measuredAt: Date
        var bpm: Double?                // nil until 2 beats — never 0
        var keyTonic: String?
        var keyIsMinor: Bool?
        var integratedLUFS: Double?
        var peakDB: Double?
        var barCount: Int?
    }

    @Published private(set) var session: Session?

    private var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "otl.session.json")
    }

    func store(_ s: Session) { session = s; persist() }
    func clear() { session = nil; try? FileManager.default.removeItem(at: fileURL) }

    /// Codable end to end, so backgrounding and cold start both survive.
    func persist() {
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func restore() {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(Session.self, from: data) else { return }
        session = s
    }

    /// Does this tool consume anything in the current session?
    func canFeed(_ tool: Tool) -> Bool {
        guard let s = session else { return false }
        switch tool {
        case .tempo, .delay:      return s.bpm != nil
        case .pitch, .partch, .comma: return s.keyTonic != nil
        case .benchmark:          return s.integratedLUFS != nil || s.peakDB != nil
        case .levels:             return s.peakDB != nil
        case .timecode:           return s.barCount != nil
        default:                  return false
        }
    }
}

// MARK: - Provenance

/// Where a field's value came from. A NEW AXIS across every receiving tool —
/// StateSpaceChecks must exercise it in both directions (see guidelines §10).
enum Provenance: Equatable {
    case typed
    case measured(source: String, at: Date)

    var isMeasured: Bool { if case .measured = self { return true }; return false }
}

/// Marks a value as measured with THREE redundant signals, none of them colour:
/// a waveform glyph, a dotted underline, and the word "Measured" in the caption.
/// Editing the value clears provenance — there is no "measured but modified".
struct MeasuredValue<Content: View>: View {
    let provenance: Provenance
    let label: LocalizedStringKey
    let spokenValue: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if provenance.isMeasured {
                    Image(systemName: "waveform")            // 1 — shape
                        .font(.system(size: 9))
                        .foregroundStyle(OTL.textSecondary)
                        .accessibilityHidden(true)           // spoken via value, not image
                }
                Text(provenance.isMeasured
                     ? "\(Text(label)) · \(Text("Measured"))" // 2 — words, localised
                     : Text(label))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(OTL.textSecondary)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
                .overlay(alignment: .bottom) {
                    if provenance.isMeasured {               // 3 — texture
                        Line().stroke(style: .init(lineWidth: 2, dash: [2, 3]))
                            .foregroundStyle(Color.white.opacity(0.45))
                            .frame(height: 2).offset(y: 3)
                    }
                }
            if case .measured(let source, let at) = provenance {
                Text("\(source) · \(at.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(OTL.textTertiary)
            }
        }
        // Provenance rides in the accessibility VALUE so it survives images off.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(provenance.isMeasured
                                 ? "\(spokenValue), measured" : spokenValue))
    }
}

private struct Line: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: .init(x: 0, y: r.midY)); p.addLine(to: .init(x: r.maxX, y: r.midY)); return p
    }
}

// MARK: - Time-series

/// Bands, never curves: every value Apple returns is already a CMTimeRange, so a
/// smooth line would imply interpolation nobody measured. A band is also a hit
/// target and an accessibility element for free.
struct BandTrack: View {
    struct Band: Identifiable {
        let id = UUID()
        let label: String
        let start: Double        // 0…1 of duration
        let width: Double        // 0…1
        let strength: Double?    // 0…1, drawn as HEIGHT + NUMBER, never alpha alone
    }
    let title: LocalizedStringKey
    let bands: [Band]
    let duration: Double
    var height: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 10, design: .monospaced)).tracking(1.2)
                .foregroundStyle(OTL.textSecondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10).fill(Color(rgbHex: 0x0C0C10))
                    ForEach(bands) { b in
                        let w = geo.size.width * b.width
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.10 + (b.strength ?? 0.5) * 0.22))
                            .frame(width: w, height: height * (b.strength ?? 1))
                            .overlay(alignment: .leading) {
                                Text(b.label).font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(OTL.textPrimary)
                                    .padding(.leading, 7)
                            }
                            .offset(x: geo.size.width * b.start,
                                    y: (height - height * (b.strength ?? 1)) / 2)
                            .accessibilityElement()
                            .accessibilityLabel(Text(b.label))
                            .accessibilityValue(Text(spoken(b)))
                    }
                }
            }
            .frame(height: height)
        }
    }

    private func spoken(_ b: Band) -> String {
        let s = Duration.seconds(b.start * duration).formatted(.time(pattern: .minuteSecond))
        let e = Duration.seconds((b.start + b.width) * duration).formatted(.time(pattern: .minuteSecond))
        if let st = b.strength { return "\(s) to \(e), strength \(st.formatted(.number.precision(.fractionLength(1))))" }
        return "\(s) to \(e)"
    }
}

// MARK: - watchOS

// Deliberately empty. The watch RECEIVES measured values (rendered with the same
// MeasuredValue marking) and never captures — a wrist mic at hip height is not a
// measurement this app can stand behind, and tap tempo already gets BPM better.
// See DESIGN_GUIDELINES.md §10, "The watchOS call".
