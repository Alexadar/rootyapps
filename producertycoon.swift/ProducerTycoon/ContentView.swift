import SwiftUI
import ProducerKit

struct ContentView: View {
    @EnvironmentObject var game: GameViewModel

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HeaderBar()
                TabView {
                    StudioTab()
                        .tabItem { Label("Студія", systemImage: "music.mic") }
                    LabelTab()
                        .tabItem { Label("Лейбл", systemImage: "building.2") }
                    WorldTab()
                        .tabItem { Label("Тренди", systemImage: "chart.line.uptrend.xyaxis") }
                }
            }
            if let over = game.outcomeText {
                GameOverOverlay(info: over)
            }
        }
    }
}

struct HeaderBar: View {
    @EnvironmentObject var game: GameViewModel

    var body: some View {
        let e = game.engine
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                stat("💰", "₴" + L.compact(e.money), e.money < 0 ? .red : .primary)
                stat("🧑‍🤝‍🧑", L.compact(e.fans), .primary)
                stat("🎟️", "\(Int(e.tokens))", .primary)
                stat("⭐", "\(Int(e.rep))", e.rep < 20 ? .red : .primary)
                Spacer(minLength: 0)
            }
            HStack {
                Text("Тиждень \(e.week)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    game.endWeek()
                } label: {
                    Label("Завершити тиждень", systemImage: "forward.end.fill")
                        .font(.subheadline.bold())
                        .fixedSize()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!e.canEndWeek)
                .help(e.canEndWeek ? "" : "Спершу випустіть реліз")
                .accessibilityIdentifier("endWeek")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    func stat(_ emoji: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(emoji)
            Text(value).font(.subheadline.monospacedDigit().bold()).foregroundStyle(color)
        }
    }
}

struct GameOverOverlay: View {
    @EnvironmentObject var game: GameViewModel
    let info: (emoji: String, title: String, detail: String)

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.6)).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(info.emoji).font(.system(size: 64))
                Text(info.title).font(.largeTitle.bold())
                Text(info.detail)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                HStack(spacing: 20) {
                    VStack {
                        Text(L.compact(game.engine.fans)).font(.title2.bold())
                        Text("фанів").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack {
                        Text("\(Int(game.engine.releases))").font(.title2.bold())
                        Text("релізів").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack {
                        Text("\(game.engine.week)").font(.title2.bold())
                        Text("тижнів").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Нова гра") { game.newGame() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(32)
            .background(RoundedRectangle(cornerRadius: 20).fill(.background))
            .padding(40)
        }
    }
}

#Preview {
    ContentView().environmentObject(GameViewModel())
}
