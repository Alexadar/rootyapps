import SwiftUI
import ProducerKit

struct WorldTab: View {
    @EnvironmentObject var game: GameViewModel

    static let topicNames: [String: String] = [
        "protest": "Протест", "absurd_humor": "Абсурдний гумор", "nostalgia": "Ностальгія",
        "pathos": "Пафос", "romance": "Романтика", "politics": "Політика",
        "party": "Вечірки", "depression": "Депресія", "nature": "Природа", "space": "Космос",
    ]

    var body: some View {
        let e = game.engine
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Жанри").font(.headline)
                ForEach(Array(e.constants.genres.enumerated()), id: \.offset) { gi, _ in
                    let g = L.genres[gi]
                    HStack {
                        Text(g.emoji)
                        Text(g.name).frame(width: 110, alignment: .leading)
                        TrendGauge(value: e.genrePop[gi], max: 100)
                        Text(modText(e.genreMod[gi]))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(e.genreMod[gi] > 0 ? .green : e.genreMod[gi] < 0 ? .red : .secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .font(.callout)
                }
                Text("Теми").font(.headline)
                ForEach(Array(e.constants.trends.topics.enumerated()), id: \.offset) { ti, topic in
                    HStack {
                        Text(Self.topicNames[topic] ?? topic).frame(width: 150, alignment: .leading)
                        TrendGauge(value: e.topicPop[ti], max: 95)
                        Text(dirText(e.topicDir[ti])).font(.caption)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .font(.callout)
                }
            }
            .padding()
        }
    }

    func modText(_ m: Double) -> String {
        m > 0 ? "+\(Int(m))" : "\(Int(m))"
    }

    func dirText(_ d: Int) -> String {
        switch d {
        case 0: return "📈 росте"
        case 2: return "📉 падає"
        default: return "⛰️ пік"
        }
    }
}

struct TrendGauge: View {
    let value: Double
    let max: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(value > 60 ? Color.green : value > 30 ? .yellow : .red)
                    .frame(width: geo.size.width * value / max)
            }
        }
        .frame(height: 8)
    }
}
