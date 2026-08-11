import SwiftUI
import AirsideKit
import AirsideUI

/// iPhone — the field tool. One hand, gloves, bright sun. Primary inputs low.
@main struct AirsideiOSApp: App {
    var body: some Scene { WindowGroup { HomeView() } }
}

struct HomeView: View {
    @State private var path = NavigationPath()
    private let tools: [(name: String, sub: String, icon: String)] = [
        ("Psychrometrics", "any two knowns → full state", "wind"),
        ("Air-side heat", "Qs · Ql · Qt, corrected", "flame"),
        ("Duct — friction", "straight duct, velocity check", "rectangle.split.3x1"),
        ("Fan laws", "affinity + density", "fanblades"),
        ("Air mixing", "two streams → mixed", "arrow.triangle.merge"),
        ("Pipe sizing", "water — velocity limits", "drop")
    ]
    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: DS.s4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Airside").font(DS.ui(28, .bold)).foregroundColor(DS.ink)
                    Spacer()
                    Text("offline · no account").font(DS.ui(11.5, .medium)).foregroundColor(DS.ink2)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(tools, id: \.name) { t in
                        NavigationLink(value: t.name) {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: t.icon).foregroundColor(DS.water).font(.system(size: 20))
                                Text(t.name).font(DS.ui(14.5, .semibold)).foregroundColor(DS.ink)
                                Text(t.sub).font(DS.ui(10.5)).foregroundColor(DS.ink2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
                            .padding(14)
                            .background(DS.card)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(DS.border, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                Text("RECENT — RESUMES MID-CALCULATION").font(DS.ui(10.5, .semibold))
                    .foregroundColor(DS.ink2).tracking(1)
                RecentRow(title: "Psychrometrics", detail: "75.0 °F · 50 % → DP 55.1°", ago: "2 min")
            }
            .padding(DS.s4)
            .background(DS.breeze.ignoresSafeArea())
            .navigationDestination(for: String.self) { name in
                if name == "Duct — friction" { DuctView() } else { PsychrometricsView() }
            }
        }
    }
}

struct RecentRow: View {
    var title: String, detail: String, ago: String
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.ui(13.5, .semibold)).foregroundColor(DS.ink)
                Text(detail).font(DS.number(11.5)).foregroundColor(DS.ink2)
            }
            Spacer()
            Text(ago).font(DS.ui(11, .medium)).foregroundColor(Color(hex: 0x8FB0C8))
        }
        .padding(14)
        .background(DS.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DS.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
