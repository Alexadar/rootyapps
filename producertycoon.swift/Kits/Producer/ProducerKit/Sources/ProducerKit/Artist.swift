import Foundation

/// One artist: the 6 content fields the engine needs (matching the torchsim
/// artist parameterization) plus per-roster runtime state.
public struct Artist: Identifiable {
    public let id: UUID
    public var name: String
    public var stats: [Double]        // 9, GameConstants.stats order
    public var genre: Int             // index into constants.genres
    public var archetype: Int         // index into GameConstants.archetypeIDs
    public var traitScore: Double
    public var traitChaos: Double
    public var textFit: Double
    public var lyric: String

    // runtime state
    public var inRehab = false
    public var rehabWeeks = 0
    public var tourCooldown = 0
    public var trashPop: Double = 0
    public var needActive = false
    public var needID = 0
    public var needWeeks = 0

    public init(name: String, stats: [Double], genre: Int, archetype: Int,
                traitScore: Double, traitChaos: Double, textFit: Double,
                lyric: String = "") {
        self.id = UUID()
        self.name = name
        self.stats = stats
        self.genre = genre
        self.archetype = archetype
        self.traitScore = traitScore
        self.traitChaos = traitChaos
        self.textFit = textFit
        self.lyric = lyric
    }

    public subscript(stat name: String) -> Double {
        get { stats[GameConstants.statIndex(name)] }
        set { stats[GameConstants.statIndex(name)] = newValue }
    }
}

/// Absurd stage-name pools from src/data/names.ts (satire; all fictional).
public enum ArtistNames {
    public static let ready = [
        "Кишка", "DJ Бульбулятор", "Ляля", "Гнилий Борщ", "MC Карась", "Бардачок",
        "Сметанний Вихор", "DJ Пательня", "Тьотя Валя і Бас", "Квашена Капуста",
        "MC Тромбон", "Льоня Холодець", "Поліетиленова Зоя", "Дід Перфоратор",
        "Котлета Делюкс", "Зомбі-Бабай", "Слизький Геннадій", "Панна Каналізація",
        "DJ Кефір", "Маринований Артем", "Бубон Іванович", "Свинопас 2000",
        "Електровіник", "Мадам Шкварка", "Грибний Дощ", "MC Сосиска",
        "Бетонна Оксана", "Дятел Прогресу", "Туалетна Фея", "Лютий Вареник",
        "DJ Самогон", "Хом’як Апокаліпсису", "Пан Холодильник", "Сало Вейв", "Тапок Долі",
    ]
    public static let prefixes = ["DJ", "MC", "Lil", "Старий", "Святий", "Юна",
                                  "Товстий", "Сер", "Мадам", "Пан", "Капітан", "Доктор"]
    public static let roots = ["Карась", "Бубон", "Сало", "Вареник", "Тромбон", "Холодець",
                               "Кабачок", "Бетон", "Селедка", "Огірок", "Цемент", "Борщ",
                               "Кефір", "Самогон", "Шкварка", "Гарбуз", "Драник", "Компот"]
    public static let suffixes = ["", "", " 3000", " Молодший", " з Троєщини", " Великий",
                                  " Безжальний", " Делюкс", " XL", " Прайм", " із села", " Турбо"]

    public static func generate(_ rng: inout GameRandom) -> String {
        if rng.chance(0.5) {
            return ready[rng.randInt(0, ready.count - 1)]
        }
        let p = prefixes[rng.randInt(0, prefixes.count - 1)]
        let r = roots[rng.randInt(0, roots.count - 1)]
        let s = suffixes[rng.randInt(0, suffixes.count - 1)]
        return "\(p) \(r)\(s)"
    }
}
