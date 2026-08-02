import Foundation
import SwiftUI
import ProducerKit

/// Ukrainian display strings for the data-driven ids (mirrors src/data of the
/// original web game).
enum L {
    static let genres: [(name: String, emoji: String)] = [
        ("Панк", "🤘"), ("Реп", "🎤"), ("Поп", "💅"),
        ("Фолк", "🌾"), ("Бард", "🎸"), ("Електроніка", "🎛️"),
    ]
    static let archetypes = ["Панк", "Трудоголік", "Алкоголік", "Романтик",
                             "Ледар", "Геній", "Діва", "Вуличний"]
    static let needs: [String: (title: String, emoji: String)] = [
        "vacation": ("Відпустка", "🏖️"), "raise": ("Підвищення", "💰"),
        "costume": ("Новий костюм", "👗"), "date": ("Побачення", "💞"),
        "psychologist": ("Психолог", "🧠"), "new_instrument": ("Новий інструмент", "🎸"),
        "pet": ("Улюбленець", "🐕"), "tattoo": ("Татуювання", "💉"),
    ]
    static let staff: [String: (name: String, emoji: String)] = [
        "manager": ("Менеджер", "🧑‍💼"), "soundEngineer": ("Звукорежисер", "🎚️"),
        "pr": ("PR-агент", "📣"), "lawyer": ("Юрист", "⚖️"),
        "accountant": ("Бухгалтер", "🧾"), "security": ("Охорона", "🦺"),
    ]
    static let equipment: [String: String] = [
        "mic-1": "Шурячий мікрофон", "mic-2": "Shure SM7B", "mic-3": "Neumann U87",
        "mon-1": "Колонки з ринку", "mon-2": "Yamaha HS8", "mon-3": "Genelec 8351B",
        "comp-1": "Компресор RNC", "comp-2": "SSL G-Bus",
        "synth-1": "Монофонічний писк", "synth-2": "Moog Subsequent 37",
        "synth-3": "Access Virus TI2", "acou-1": "Матраци на стінах",
        "acou-2": "Акустичні панелі", "acou-3": "Професійна акустика",
        "light-1": "Лампочка Ілліча", "light-2": "Світлодіодний сет",
        "light-3": "Професійне світло",
    ]
    static let studios = ["Гараж", "Підвал", "Домашня студія",
                          "Комерційна студія", "Преміум студія", "Abbey Road"]
    static let labels = ["Стартовий лейбл", "Малий лейбл", "Середній лейбл",
                         "Великий лейбл", "Лейбл-гігант", "Імперія звуку"]
    static let statNames: [String: String] = [
        "talent": "Талант", "discipline": "Дисципліна", "charisma": "Харизма",
        "health": "Здоров'я", "happiness": "Настрій", "popularity": "Популярність",
        "addiction": "Залежність", "reputation": "Репутація", "selfConfidence": "Впевненість",
    ]

    static func money(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = " "
        return "₴" + (f.string(from: NSNumber(value: v)) ?? "0")
    }

    static func compact(_ v: Double) -> String {
        switch abs(v) {
        case 1_000_000...: return String(format: "%.1fM", v / 1_000_000)
        case 10_000...: return String(format: "%.0fK", v / 1_000)
        default: return String(format: "%.0f", v)
        }
    }
}

struct GameEvent: Identifiable {
    let id = UUID()
    let week: Int
    let emoji: String
    let text: String
}

@MainActor
final class GameViewModel: ObservableObject {
    @Published private(set) var engine: ProducerEngine
    @Published var events: [GameEvent] = []
    @Published var lastRelease: ReleaseReport?

    init() {
        engine = try! ProducerEngine.coevolved(seed: UInt64.random(in: 0..<UInt64.max))
    }

    func newGame() {
        engine = try! ProducerEngine.coevolved(seed: UInt64.random(in: 0..<UInt64.max))
        events = []
        lastRelease = nil
    }

    private func log(_ emoji: String, _ text: String) {
        events.insert(GameEvent(week: engine.week, emoji: emoji, text: text), at: 0)
        if events.count > 60 { events.removeLast() }
    }

    // MARK: intents

    func sign(_ index: Int) {
        let name = engine.candidates[index].name
        if engine.sign(candidate: index) {
            log("✍️", "Підписано контракт: \(name)")
            objectWillChange.send()
        }
    }

    func reject() {
        if engine.rejectPair() {
            log("🚪", "Обом кандидатам відмовлено")
            objectWillChange.send()
        }
    }

    func release(slot: Int) {
        guard let r = engine.release(slot: slot) else { return }
        lastRelease = r
        log("💿", "\(r.artistName) — «\(r.tierName)»: \(L.money(r.moneyDelta)), +\(L.compact(r.fansGained)) фанів")
        objectWillChange.send()
    }

    func tour(slot: Int) {
        guard let t = engine.tour(slot: slot) else { return }
        log(t.success ? "🎪" : "🥀",
            "\(t.artistName): тур \(t.success ? "вдалий" : "провальний"), \(L.money(t.moneyDelta))")
        objectWillChange.send()
    }

    func rehab(slot: Int) {
        let name = engine.roster[slot]?.name ?? ""
        if engine.rehab(slot: slot) {
            log("🏥", "\(name) — у реабілітації")
            objectWillChange.send()
        }
    }

    func fire(slot: Int) {
        let name = engine.roster[slot]?.name ?? ""
        if engine.fire(slot: slot) {
            log("🔥", "\(name) звільнено")
            objectWillChange.send()
        }
    }

    func fulfillNeed(slot: Int) {
        let name = engine.roster[slot]?.name ?? ""
        if engine.fulfillNeed(slot: slot) {
            log("🎁", "Потребу артиста \(name) задоволено")
            objectWillChange.send()
        }
    }

    func hireStaff(_ i: Int) { if engine.hireStaff(i) { objectWillChange.send() } }
    func fireStaff(_ i: Int) { if engine.fireStaff(i) { objectWillChange.send() } }
    func buyEquip(_ i: Int) { if engine.buyEquip(i) { objectWillChange.send() } }
    func upgradeStudio() { if engine.upgradeStudio() { objectWillChange.send() } }
    func upgradeLabel() { if engine.upgradeLabel() { objectWillChange.send() } }

    func endWeek() {
        guard let report = engine.endWeek() else { return }
        if report.salaries > 0 {
            log("💸", "Зарплати персоналу: \(L.money(-report.salaries))")
        }
        if let ev = report.weekEvent {
            var parts: [String] = []
            if ev.money != 0 { parts.append(L.money(ev.money)) }
            if ev.fans != 0 { parts.append("\(L.compact(ev.fans)) фанів") }
            if ev.rep != 0 { parts.append("репутація \(ev.rep > 0 ? "+" : "")\(Int(ev.rep))") }
            if ev.tokens != 0 { parts.append("жетони \(ev.tokens > 0 ? "+" : "")\(Int(ev.tokens))") }
            if !parts.isEmpty { log("📰", "Подія тижня: " + parts.joined(separator: ", ")) }
        }
        log("🗓️", "Тиждень \(engine.week)")
        objectWillChange.send()
    }

    var outcomeText: (emoji: String, title: String, detail: String)? {
        switch engine.outcome {
        case .running: return nil
        case .winFans:
            return ("🏆", "Перемога!", "100 мільйонів фанатів. Ви — легенда шоу-бізнесу.")
        case .winYears:
            return ("🥂", "Перемога!", "10 років на плаву. Лейбл вистояв.")
        case .bankrupt:
            return ("💀", "Банкрутство", "Борги поховали лейбл. Менеджер утік на самокаті.")
        case .reputationLost:
            return ("🤡", "Репутацію знищено", "З вами більше ніхто не працює.")
        case .rejectedOut:
            return ("🚪", "Усім відмовлено", "Порожній лейбл і купа відмов. Артисти обходять вас стороною.")
        case .timeout:
            return ("⏰", "Час вийшов", "Гра завершена за часом.")
        }
    }
}
