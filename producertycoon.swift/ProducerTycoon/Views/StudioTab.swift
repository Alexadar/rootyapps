import SwiftUI
import ProducerKit

struct StudioTab: View {
    @EnvironmentObject var game: GameViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Кандидати")
                    .font(.headline)
                candidateRow
                HStack {
                    Text("Ростер \(game.engine.rosterCount)/\(game.engine.labelSlots)")
                        .font(.headline)
                    Spacer()
                }
                rosterList
                if !game.events.isEmpty {
                    Text("Хроніка").font(.headline)
                    ForEach(game.events.prefix(12)) { ev in
                        HStack(alignment: .top, spacing: 6) {
                            Text(ev.emoji)
                            Text(ev.text).font(.callout)
                            Spacer()
                            Text("тиж. \(ev.week)")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding()
        }
    }

    var candidateRow: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(game.engine.candidates.enumerated()), id: \.element.id) { i, artist in
                    CandidateCard(artist: artist, index: i)
                }
            }
            Button("🚪 Відмовити обом") { game.reject() }
                .buttonStyle(.bordered)
                .disabled(!game.engine.canReject)
                .frame(maxWidth: .infinity)
        }
    }

    var rosterList: some View {
        VStack(spacing: 8) {
            ForEach(0..<ProducerEngine.rosterSlots, id: \.self) { slot in
                if let artist = game.engine.roster[slot] {
                    RosterRow(artist: artist, slot: slot)
                }
            }
            if game.engine.rosterCount == 0 {
                Text("Порожньо. Підпишіть когось — без релізів тиждень не завершити.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }
}

struct CandidateCard: View {
    @EnvironmentObject var game: GameViewModel
    let artist: Artist
    let index: Int

    var body: some View {
        let g = L.genres[artist.genre]
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(g.emoji).font(.title2)
                VStack(alignment: .leading) {
                    Text(artist.name).font(.headline).lineLimit(1)
                    Text("\(g.name) · \(L.archetypes[artist.archetype])")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(["talent", "charisma", "discipline", "addiction"], id: \.self) { stat in
                StatBar(name: L.statNames[stat]!, value: artist[stat: stat],
                        inverted: stat == "addiction")
            }
            Button {
                game.sign(index)
            } label: {
                Text("Підписати")
                    .font(.callout.bold())
                    .fixedSize()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!game.engine.canSign)
            .accessibilityIdentifier("sign\(index)")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5)))
    }
}

struct RosterRow: View {
    @EnvironmentObject var game: GameViewModel
    let artist: Artist
    let slot: Int

    var body: some View {
        let e = game.engine
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L.genres[artist.genre].emoji)
                Text(artist.name).font(.subheadline.bold())
                if artist.inRehab {
                    Text("🏥 реабілітація (\(artist.rehabWeeks))")
                        .font(.caption).foregroundStyle(.orange)
                }
                if artist.needActive,
                   let need = L.needs[e.constants.needs[artist.needID].id] {
                    Text("\(need.emoji) \(need.title)")
                        .font(.caption).foregroundStyle(.purple)
                }
                Spacer()
                Text("поп. \(Int(artist[stat: "popularity"])) · зал. \(Int(artist[stat: "addiction"]))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("💿 Реліз") { game.release(slot: slot) }
                    .disabled(!e.canRelease(slot: slot))
                    .accessibilityIdentifier("release\(slot)")
                Button("🎪 Тур\(e.tourCost(slot: slot).map { " " + L.compact($0) } ?? "")") {
                    game.tour(slot: slot)
                }
                .disabled(!e.canTour(slot: slot))
                .accessibilityIdentifier("tour\(slot)")
                Button("🏥 Рехаб") { game.rehab(slot: slot) }
                    .disabled(!e.canRehab(slot: slot))
                if artist.needActive {
                    Button("🎁 \(L.compact(e.needCost(slot: slot) ?? 0))") {
                        game.fulfillNeed(slot: slot)
                    }
                    .disabled(!e.canFulfillNeed(slot: slot))
                }
                Spacer()
                Button(role: .destructive) { game.fire(slot: slot) } label: { Text("Звільнити") }
                    .disabled(!e.canFire(slot: slot))
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.35)))
    }
}

struct StatBar: View {
    let name: String
    let value: Double
    var inverted = false

    var body: some View {
        HStack(spacing: 6) {
            Text(name).font(.caption2).frame(width: 82, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * value / 100)
                }
            }
            .frame(height: 6)
            Text("\(Int(value))").font(.caption2.monospacedDigit())
                .frame(width: 22, alignment: .trailing)
        }
    }

    var color: Color {
        let good = inverted ? 100 - value : value
        return good > 60 ? .green : good > 35 ? .yellow : .red
    }
}
