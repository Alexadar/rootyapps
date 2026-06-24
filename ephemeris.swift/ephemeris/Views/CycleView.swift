import SwiftUI
import EphemerisKit

/// Synodic-cycle panel — a body's conjunctions, stations ("U-turns") and elongations
/// relative to the Sun. Defaults to Mercury's phases.
struct CycleView: View {
    @ObservedObject var vm: ChartViewModel
    @Namespace private var glassNS

    private static let bodies: [CelestialBody] = CelestialBody.allCases.filter { $0 != .sun && $0 != .moon }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            picker
            if let phase = vm.cyclePhase { phaseCard(phase) }
            eventsCard
        }
        .onChange(of: vm.cycleBody) { _, _ in vm.recompute() }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Synodic cycle")
            Picker("CelestialBody", selection: $vm.cycleBody) {
                ForEach(Self.bodies) { Text("\($0.glyph)  \($0.name)").tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .glassCard()
    }

    private func phaseCard(_ phase: SynodicPhase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: "Current phase")
            HStack(spacing: 10) {
                Text(vm.cycleBody.glyph).font(.largeTitle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(phase.title).font(.headline)
                    Text(phase.detail).font(.subheadline).foregroundStyle(.secondary)
                    if let day = phase.dayInPhase, let len = phase.phaseLengthDays {
                        Text("Day \(day) of \(len)").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if phase.retrograde {
                    Text("℞").font(.title).foregroundStyle(Color(rgbHex: 0xe67e22))
                }
            }
        }
        .glassCard()
        .glassEffectID("phase", in: glassNS)
    }

    private var eventsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Upcoming events")
            if vm.upcomingEvents.isEmpty {
                Text("No events found in range.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(vm.upcomingEvents) { e in
                    HStack(spacing: 12) {
                        Text(e.kind.glyph)
                            .font(.headline)
                            .frame(width: 30, height: 30)
                            .background(.tint.opacity(0.15), in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.kind.label).font(.callout)
                            Text(ZodiacSign.from(longitude: e.longitude).glyph
                                 + " " + String(format: "%.1f°", e.longitude))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(e.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
        .glassCard()
    }
}
