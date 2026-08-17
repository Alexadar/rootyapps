import SwiftUI
import EphemerisKit

/// Synodic-cycle panel — a body's conjunctions, stations ("U-turns") and elongations
/// relative to the Sun. Defaults to Mercury's phases.
struct CycleView: View {
    let phase: SynodicPhase?
    let upcoming: [SynodicEvent]
    /// Named `selectedBody`, not `body`: a stored property called `body` collides with the
/// View's own `var body: some View`.
    @Binding var selectedBody: CelestialBody
    @Environment(\.locale) private var locale

    private static let bodies: [CelestialBody] = CelestialBody.allCases.filter { $0 != .sun && $0 != .moon }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            picker
            if let phase { phaseCard(phase) }
            eventsCard
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Synodic cycle")
            Picker("Body", selection: $selectedBody) {
                // Glyph verbatim, name resolved through the catalog, then joined as one String.
                // `Text("\(glyph)  \(name)")` would leave the Kit's English name untranslated, and
                // `Text(...) + Text(...)` is deprecated — so resolve first, render once.
                ForEach(Self.bodies) {
                    Text(verbatim: $0.glyph + "  " + L.string($0.name, locale: locale)).tag($0)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
                .accessibilityIdentifier("input.cycleBody")
        }
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.cyclePicker")
    }

    /// The Kit composes `phase.title`/`phase.detail` in English at runtime, so neither can be a
    /// catalog key — feeding them to `L.loc` would silently return the English sentence. These
    /// rebuild the same text from the structured fields, translating each part on its own.
    private static func phaseTitle(_ phase: SynodicPhase, _ locale: Locale) -> Text {
        let motion = L.string(phase.retrograde ? "Retrograde" : "Direct", locale: locale)
        guard let visibility = phase.visibility else { return Text(verbatim: motion) }
        let star = visibility == .eveningStar
            ? "Evening star (Epimethean)" : "Morning star (Promethean)"
        return Text(verbatim: L.string(star, locale: locale) + " · " + motion)
    }

    /// "Inferior conjunction → Station direct". Uses `kind.label` rather than `kind.short`: the
    /// long forms are the ones the catalog already carries, so this needs no extra vocabulary.
    private static func phaseDetail(_ phase: SynodicPhase, _ locale: Locale) -> Text {
        func side(_ event: SynodicEvent?) -> String {
            event.map { L.string($0.kind.label, locale: locale) } ?? "—"
        }
        return Text(verbatim: side(phase.start) + " → " + side(phase.end))
    }

    private func phaseCard(_ phase: SynodicPhase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: "Current phase")
            HStack(spacing: 10) {
                Text(selectedBody.glyph + "\u{FE0E}").font(.largeTitle)
                    .foregroundStyle(NebulaPalette.glyph).nebulaGlow()
                VStack(alignment: .leading, spacing: 3) {
                    Self.phaseTitle(phase, locale).font(.headline)
                        .accessibilityIdentifier("cycle.phaseTitle")
                    Self.phaseDetail(phase, locale).font(.subheadline)
                        .foregroundStyle(NebulaPalette.textSecondary)
                        .accessibilityIdentifier("cycle.phaseDetail")
                    if let day = phase.dayInPhase, let len = phase.phaseLengthDays {
                        Text("Day \(day) of \(len)").font(.caption).foregroundStyle(NebulaPalette.textFaint)
                            .accessibilityIdentifier("cycle.dayInPhase")
                    }
                }
                Spacer()
                if phase.retrograde {
                    Text(verbatim: "℞").font(.title).foregroundStyle(NebulaPalette.retrograde)
                }
            }
        }
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.currentPhase")
    }

    private var eventsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Upcoming events")
            if upcoming.isEmpty {
                Text("No events found in range.").font(.callout).foregroundStyle(NebulaPalette.textSecondary)
            } else {
                ForEach(upcoming) { e in
                    HStack(spacing: 12) {
                        Text(e.kind.glyph + "\u{FE0E}")
                            .font(.headline)
                            .frame(width: 30, height: 30)
                            .background(NebulaPalette.accent.opacity(0.15), in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L.loc(e.kind.label)).font(.callout)
                            HStack(spacing: 6) {
                                SignChip(glyph: ZodiacSign.from(longitude: e.longitude).glyph, size: 18)
                                Text(verbatim: e.longitude.formatted(
                                    .number.precision(.fractionLength(1)).locale(locale)) + "°")
                                    .font(.caption).foregroundStyle(NebulaPalette.textSecondary)
                            }
                        }
                        Spacer()
                        Text(e.date, format: .dateTime.day().month(.abbreviated).year())
                            .font(.caption).monospacedDigit().foregroundStyle(NebulaPalette.textSecondary)
                    }
                }
            }
        }
        .glassCard()
    }
}
