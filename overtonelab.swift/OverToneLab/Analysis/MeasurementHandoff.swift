import SwiftUI
import MeasureKit
import PitchKit

/// Carries measured values from Analysis into the tool that consumes them.
///
/// ## Why a courier and not a direct write
///
/// A tool's ViewModel is created by its detail view, which does not exist yet when the user taps
/// *Send to tempo*. So the value is parked here and applied by the receiving screen on appear. It
/// also keeps `DESIGN_GUIDELINES` §11 true — no ViewModel gains a published property; the handoff
/// only writes properties that already existed.
///
/// ## What lands, and what deliberately does not
///
/// Fed: BPM → tempo, delay. Key → pitch and partch, as the tonic's frequency. Integrated LUFS →
/// benchmark.
///
/// **Four of §10's routes are not offered, each for a specific missing input** — the rule being that a
/// handed value must land in a field that already exists and already means that quantity:
///   • `comma` takes an EDO count, a frequency ratio and a cents value; a tonic is none of them.
///   • `levels` takes volts, two comparison levels and a bit depth — there is no dBFS field for a
///     true peak.
///   • `timecode` takes a frame count, not bars; converting needs an invented meter and frame rate.
///   • `sra` and `pan` consume instrument activity, which `Session` does not carry.
/// A Send row that put a number somewhere it did not belong would be a wrong answer wearing a
/// measured badge, which is worse than no row.
@MainActor
final class MeasurementHandoff: ObservableObject {

    /// Values waiting for their screen to appear, keyed by field.
    @Published private(set) var pending: [FieldKey: Double] = [:]
    private var source: (name: String, at: Date)?

    // MARK: - Sending

    func hand(session: MeasurementStore.Session, to tool: Tool, provenance: FieldProvenance) {
        source = (session.sourceName, session.measuredAt)
        for (key, value) in Self.values(from: session, for: tool) { pending[key] = value }
    }

    /// The routing table, as data. One place to read, and one place a test can enumerate.
    static func values(from s: MeasurementStore.Session, for tool: Tool) -> [FieldKey: Double] {
        switch tool {
        case .tempo:
            return s.bpm.map { [FieldKey(tool: "tempo", field: "bpm"): $0] } ?? [:]
        case .delay:
            return s.bpm.map { [FieldKey(tool: "delay", field: "bpm"): $0] } ?? [:]
        case .pitch:
            // The tonic as a FREQUENCY, because that is the field this screen actually edits — it
            // reports the nearest note and the cents error from it. Handing a MIDI number to the
            // stepper instead would put a measured value somewhere provenance cannot be shown.
            guard let midi = Measure.tonicMIDI(tonic: s.keyTonic) else { return [:] }
            return [FieldKey(tool: "pitch", field: "freqInput"): Pitch.noteToHz(midi: midi)]
        case .partch:
            guard let midi = Measure.tonicMIDI(tonic: s.keyTonic) else { return [:] }
            return [FieldKey(tool: "partch", field: "freqLow"): Pitch.noteToHz(midi: midi)]
        case .benchmark:
            return s.integratedLUFS.map { [FieldKey(tool: "benchmark", field: "measuredInput"): $0] } ?? [:]
        default:
            return [:]
        }
    }

    /// A one-line description of what a Send row will do, for the row's subtitle.
    func summary(for tool: Tool, session: MeasurementStore.Session) -> String {
        let values = Self.values(from: session, for: tool)
        switch tool {
        case .tempo, .delay:
            return session.bpm.map { "\(Fmt.f($0, 1)) BPM" } ?? ""
        case .pitch, .partch:
            return session.keyName ?? ""
        case .benchmark:
            return session.integratedLUFS.map { "\(Fmt.f($0, 1)) LUFS" } ?? ""
        default:
            return values.isEmpty ? "" : "\(values.count) values"
        }
    }

    // MARK: - Receiving

    /// Apply a pending value to a field, marking it measured and remembering what it displaced.
    ///
    /// Called from the receiving screen's `onAppear`. Returns true when something landed, which is
    /// what makes this testable without a view.
    @discardableResult
    func apply(_ key: FieldKey, into binding: Binding<Double>, provenance: FieldProvenance) -> Bool {
        guard let value = pending[key], let source else { return false }
        provenance.markMeasured(key, replacing: binding.wrappedValue, source: source.name, at: source.at)
        binding.wrappedValue = value
        pending[key] = nil
        return true
    }

    /// Integer fields (`pitch.midi`, `timecode` bars) take the same path through a rounded bridge.
    @discardableResult
    func apply(_ key: FieldKey, into binding: Binding<Int>, provenance: FieldProvenance) -> Bool {
        guard let value = pending[key], let source else { return false }
        provenance.markMeasured(key, replacing: Double(binding.wrappedValue),
                                source: source.name, at: source.at)
        binding.wrappedValue = Int(value.rounded())
        pending[key] = nil
        return true
    }

    func clear() { pending.removeAll(); source = nil }
}
