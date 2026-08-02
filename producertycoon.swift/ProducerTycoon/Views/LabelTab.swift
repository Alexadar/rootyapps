import SwiftUI
import ProducerKit

struct LabelTab: View {
    @EnvironmentObject var game: GameViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                upgrades
                staffSection
                equipmentSection
            }
            .padding()
        }
    }

    var upgrades: some View {
        let e = game.engine
        return VStack(alignment: .leading, spacing: 8) {
            Text("Розвиток").font(.headline)
            HStack(spacing: 12) {
                UpgradeCard(
                    emoji: "🎙️",
                    title: L.studios[e.studioLevel - 1],
                    subtitle: "Студія, рівень \(e.studioLevel)/6",
                    cost: e.studioUpgradeCost(),
                    enabled: e.canUpgradeStudio
                ) { game.upgradeStudio() }
                UpgradeCard(
                    emoji: "🏢",
                    title: L.labels[e.labelTier],
                    subtitle: "\(e.labelSlots) слотів для артистів",
                    cost: e.labelUpgradeCost(),
                    enabled: e.canUpgradeLabel
                ) { game.upgradeLabel() }
            }
            HStack(spacing: 16) {
                Text("Продюсер: рівень \(Int(e.prodLevel))")
                ProgressView(value: e.prodXP, total: e.prodXPNext)
                    .frame(maxWidth: 180)
                Text("\(Int(e.prodXP))/\(Int(e.prodXPNext)) XP")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    var staffSection: some View {
        let e = game.engine
        return VStack(alignment: .leading, spacing: 8) {
            Text("Персонал").font(.headline)
            ForEach(Array(e.constants.staff.roles.enumerated()), id: \.offset) { i, role in
                let info = L.staff[role] ?? (role, "🧑")
                HStack {
                    Text(info.emoji)
                    Text(info.name)
                    Text(L.money(e.constants.staff.salaries[role]! * e.theta.salary_mult) + "/тиж.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if e.staffHired[i] {
                        Button("Звільнити") { game.fireStaff(i) }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Найняти") { game.hireStaff(i) }
                            .buttonStyle(.borderedProminent)
                            .disabled(!e.canHireStaff(i))
                            .accessibilityIdentifier("hire\(i)")
                    }
                }
                .font(.callout)
            }
        }
    }

    var equipmentSection: some View {
        let e = game.engine
        return VStack(alignment: .leading, spacing: 8) {
            Text("Обладнання").font(.headline)
            ForEach(Array(e.constants.equipment.enumerated()), id: \.offset) { i, eq in
                HStack {
                    Text(L.equipment[eq.id] ?? eq.id)
                    Text("+\(Int(eq.bonus)) якості").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if e.equipOwned[i] {
                        Text("✅").font(.callout)
                    } else {
                        Button(L.money(e.equipCost(i))) { game.buyEquip(i) }
                            .buttonStyle(.bordered)
                            .disabled(!e.canBuyEquip(i))
                    }
                }
                .font(.callout)
            }
        }
    }
}

struct UpgradeCard: View {
    let emoji: String
    let title: String
    let subtitle: String
    let cost: Double?
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(emoji).font(.title2)
            Text(title).font(.subheadline.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            if let cost {
                Button("Покращити за \(L.money(cost))", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!enabled)
            } else {
                Text("Максимальний рівень").font(.caption).foregroundStyle(.green)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5)))
    }
}
