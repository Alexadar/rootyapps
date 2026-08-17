#!/usr/bin/env python3
"""Generate Tarot/Localizable.xcstrings from strings_ui.json + the card-name tables below.

The ephemeris pattern (Localization/gen_xcstrings.py there): keys are the ENGLISH SOURCE
STRINGS, because SwiftUI's Text("literal") looks up by the literal and TarotKit deliberately
keeps returning English (its display strings double as the FM prompt vocabulary — the
guardrail label table was measured against English names — and as stable identifiers).
`L.loc()` turns Kit English into a catalog lookup at the view boundary.

Unlike ephemeris, the 56 minor-arcana names are GENERATED per language here rather than
listed in JSON: each language composes "Ace of Wands" with its own grammar (German genitive
"As der Stäbe", French elision "Dix d'Épées", Japanese suit-first "ワンドのエース", Turkish
possessive "Değnek Ası"), so the composition rule lives in code, per language, and the
output is stored as full-name keys — no runtime pattern can be grammatical everywhere.

    python3 Localization/gen_xcstrings.py          # write the catalog
    python3 Localization/gen_xcstrings.py --check  # report gaps, write nothing
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Tarot" / "Localizable.xcstrings"

# Shipped locales = the intersection with Apple Intelligence's supported languages
# (owner, 2026-08-17: locales the on-device model can't write in are DISSECTED from the
# ship — a localized app whose readings come back in English is a broken promise).
LOCALES = ["de", "fr", "es", "it", "tr", "nl", "sv", "ja", "ko", "pt-BR"]

# PARKED, not deleted: full translations for these live on in every table below, excluded
# only from LOCALES. When Apple Intelligence adds one of them, shipping it is a one-line
# move from this list. (State as of iOS 26: pl uk cs hu ro el are not FM languages.)
PARKED_LOCALES = ["pl", "uk", "cs", "hu", "ro", "el"]

# ── Major arcana, 0–21, per locale ──────────────────────────────────────────────────────
MAJORS_EN = ["The Fool", "The Magician", "The High Priestess", "The Empress", "The Emperor",
             "The Hierophant", "The Lovers", "The Chariot", "Strength", "The Hermit",
             "Wheel of Fortune", "Justice", "The Hanged Man", "Death", "Temperance",
             "The Devil", "The Tower", "The Star", "The Moon", "The Sun", "Judgement",
             "The World"]

MAJORS = {
 "de": ["Der Narr","Der Magier","Die Hohepriesterin","Die Herrscherin","Der Herrscher","Der Hierophant","Die Liebenden","Der Wagen","Die Kraft","Der Eremit","Rad des Schicksals","Die Gerechtigkeit","Der Gehängte","Der Tod","Die Mäßigkeit","Der Teufel","Der Turm","Der Stern","Der Mond","Die Sonne","Das Gericht","Die Welt"],
 "fr": ["Le Mat","Le Magicien","La Grande Prêtresse","L'Impératrice","L'Empereur","Le Hiérophante","Les Amoureux","Le Chariot","La Force","L'Ermite","La Roue de la Fortune","La Justice","Le Pendu","La Mort","La Tempérance","Le Diable","La Tour","L'Étoile","La Lune","Le Soleil","Le Jugement","Le Monde"],
 "es": ["El Loco","El Mago","La Sacerdotisa","La Emperatriz","El Emperador","El Hierofante","Los Enamorados","El Carro","La Fuerza","El Ermitaño","La Rueda de la Fortuna","La Justicia","El Colgado","La Muerte","La Templanza","El Diablo","La Torre","La Estrella","La Luna","El Sol","El Juicio","El Mundo"],
 "it": ["Il Matto","Il Mago","La Papessa","L'Imperatrice","L'Imperatore","Il Papa","Gli Amanti","Il Carro","La Forza","L'Eremita","La Ruota della Fortuna","La Giustizia","L'Appeso","La Morte","La Temperanza","Il Diavolo","La Torre","La Stella","La Luna","Il Sole","Il Giudizio","Il Mondo"],
 "pl": ["Głupiec","Mag","Najwyższa Kapłanka","Cesarzowa","Cesarz","Hierofant","Kochankowie","Rydwan","Siła","Pustelnik","Koło Fortuny","Sprawiedliwość","Wisielec","Śmierć","Umiarkowanie","Diabeł","Wieża","Gwiazda","Księżyc","Słońce","Sąd Ostateczny","Świat"],
 "uk": ["Дурень","Маг","Верховна Жриця","Імператриця","Імператор","Ієрофант","Закохані","Колісниця","Сила","Відлюдник","Колесо Фортуни","Справедливість","Повішений","Смерть","Помірність","Диявол","Вежа","Зірка","Місяць","Сонце","Суд","Світ"],
 "cs": ["Blázen","Mág","Velekněžka","Císařovna","Císař","Velekněz","Milenci","Vůz","Síla","Poustevník","Kolo štěstí","Spravedlnost","Viselec","Smrt","Mírnost","Ďábel","Věž","Hvězda","Měsíc","Slunce","Soud","Svět"],
 "hu": ["A Bolond","A Mágus","A Főpapnő","A Császárnő","A Császár","A Főpap","A Szerelmesek","A Diadalszekér","Az Erő","A Remete","A Szerencsekerék","Az Igazságosság","Az Akasztott","A Halál","A Mértékletesség","Az Ördög","A Torony","A Csillag","A Hold","A Nap","Az Ítélet","A Világ"],
 "ro": ["Nebunul","Magicianul","Marea Preoteasă","Împărăteasa","Împăratul","Hierofantul","Îndrăgostiții","Carul","Forța","Eremitul","Roata Norocului","Dreptatea","Spânzuratul","Moartea","Cumpătarea","Diavolul","Turnul","Steaua","Luna","Soarele","Judecata","Lumea"],
 "el": ["Ο Τρελός","Ο Μάγος","Η Αρχιέρεια","Η Αυτοκράτειρα","Ο Αυτοκράτορας","Ο Ιεροφάντης","Οι Εραστές","Το Άρμα","Η Δύναμη","Ο Ερημίτης","Ο Τροχός της Τύχης","Η Δικαιοσύνη","Ο Κρεμασμένος","Ο Θάνατος","Η Εγκράτεια","Ο Διάβολος","Ο Πύργος","Το Αστέρι","Η Σελήνη","Ο Ήλιος","Η Κρίση","Ο Κόσμος"],
 "tr": ["Deli","Büyücü","Başrahibe","İmparatoriçe","İmparator","Başrahip","Aşıklar","Savaş Arabası","Güç","Ermiş","Kader Çarkı","Adalet","Asılan Adam","Ölüm","Ölçülülük","Şeytan","Kule","Yıldız","Ay","Güneş","Yargı","Dünya"],
 "nl": ["De Dwaas","De Magiër","De Hogepriesteres","De Keizerin","De Keizer","De Hiërofant","De Geliefden","De Zegewagen","Kracht","De Kluizenaar","Het Rad van Fortuin","Gerechtigheid","De Gehangene","De Dood","Matigheid","De Duivel","De Toren","De Ster","De Maan","De Zon","Het Oordeel","De Wereld"],
 "sv": ["Narren","Magikern","Översteprästinnan","Kejsarinnan","Kejsaren","Hierofanten","De Älskande","Vagnen","Styrkan","Eremiten","Lyckohjulet","Rättvisan","Den Hängde","Döden","Måttfullheten","Djävulen","Tornet","Stjärnan","Månen","Solen","Domen","Världen"],
 "ja": ["愚者","魔術師","女教皇","女帝","皇帝","教皇","恋人","戦車","力","隠者","運命の輪","正義","吊られた男","死神","節制","悪魔","塔","星","月","太陽","審判","世界"],
 "ko": ["바보","마법사","여사제","여황제","황제","교황","연인","전차","힘","은둔자","운명의 수레바퀴","정의","매달린 남자","죽음","절제","악마","탑","별","달","태양","심판","세계"],
 "pt-BR": ["O Louco","O Mago","A Sacerdotisa","A Imperatriz","O Imperador","O Hierofante","Os Enamorados","O Carro","A Força","O Eremita","A Roda da Fortuna","A Justiça","O Enforcado","A Morte","A Temperança","O Diabo","A Torre","A Estrela","A Lua","O Sol","O Julgamento","O Mundo"],
}

# ── Minor arcana: per-language ranks, suits, and a composition rule ─────────────────────
RANKS_EN = ["Ace","Two","Three","Four","Five","Six","Seven","Eight","Nine","Ten",
            "Page","Knight","Queen","King"]
SUITS_EN = ["Wands","Cups","Swords","Pentacles"]

RANKS = {
 "de": ["Ass","Zwei","Drei","Vier","Fünf","Sechs","Sieben","Acht","Neun","Zehn","Bube","Ritter","Königin","König"],
 "fr": ["As","Deux","Trois","Quatre","Cinq","Six","Sept","Huit","Neuf","Dix","Valet","Cavalier","Reine","Roi"],
 "es": ["As","Dos","Tres","Cuatro","Cinco","Seis","Siete","Ocho","Nueve","Diez","Sota","Caballero","Reina","Rey"],
 "it": ["Asso","Due","Tre","Quattro","Cinque","Sei","Sette","Otto","Nove","Dieci","Fante","Cavaliere","Regina","Re"],
 "pl": ["As","Dwójka","Trójka","Czwórka","Piątka","Szóstka","Siódemka","Ósemka","Dziewiątka","Dziesiątka","Paź","Rycerz","Królowa","Król"],
 "uk": ["Туз","Двійка","Трійка","Четвірка","П'ятірка","Шістка","Сімка","Вісімка","Дев'ятка","Десятка","Паж","Лицар","Королева","Король"],
 "cs": ["Eso","Dvojka","Trojka","Čtyřka","Pětka","Šestka","Sedmička","Osmička","Devítka","Desítka","Páže","Rytíř","Královna","Král"],
 "hu": ["Ász","Kettes","Hármas","Négyes","Ötös","Hatos","Hetes","Nyolcas","Kilences","Tízes","Apród","Lovag","Királynő","Király"],
 "ro": ["As","Doi","Trei","Patru","Cinci","Șase","Șapte","Opt","Nouă","Zece","Paj","Cavaler","Regină","Rege"],
 "el": ["Άσσος","Δύο","Τρία","Τέσσερα","Πέντε","Έξι","Επτά","Οκτώ","Εννέα","Δέκα","Βαλές","Ιππότης","Βασίλισσα","Βασιλιάς"],
 "tr": ["Ası","İkilisi","Üçlüsü","Dörtlüsü","Beşlisi","Altılısı","Yedilisi","Sekizlisi","Dokuzlusu","Onlusu","Prensi","Şövalyesi","Kraliçesi","Kralı"],
 "nl": ["Aas","Twee","Drie","Vier","Vijf","Zes","Zeven","Acht","Negen","Tien","Page","Ridder","Koningin","Koning"],
 "sv": ["Ess","Två","Tre","Fyra","Fem","Sex","Sju","Åtta","Nio","Tio","Page","Riddare","Drottning","Kung"],
 "ja": ["エース","2","3","4","5","6","7","8","9","10","ペイジ","ナイト","クイーン","キング"],
 "ko": ["에이스","2","3","4","5","6","7","8","9","10","페이지","나이트","퀸","킹"],
 "pt-BR": ["Ás","Dois","Três","Quatro","Cinco","Seis","Sete","Oito","Nove","Dez","Valete","Cavaleiro","Rainha","Rei"],
}

SUITS = {
 # value: the form used inside the composed name (already carrying case/preposition where
 # the rule below expects it)
 "de": ["der Stäbe","der Kelche","der Schwerter","der Münzen"],
 "fr": ["de Bâtons","de Coupes","d'Épées","de Deniers"],
 "es": ["de Bastos","de Copas","de Espadas","de Oros"],
 "it": ["di Bastoni","di Coppe","di Spade","di Denari"],
 "pl": ["Buław","Kielichów","Mieczy","Pentakli"],
 "uk": ["Жезлів","Кубків","Мечів","Пентаклів"],
 "cs": ["Holí","Pohárů","Mečů","Pentaklů"],
 "hu": ["Botok","Kelyhek","Kardok","Érmék"],
 "ro": ["de Bâte","de Cupe","de Spade","de Pentacle"],
 "el": ["Μπαστουνιών","Κυπέλλων","Σπαθιών","Πενταλφών"],
 "tr": ["Değnek","Kupa","Kılıç","Tılsım"],
 "nl": ["van Staven","van Bekers","van Zwaarden","van Pentakels"],
 "sv": ["i Stavar","i Bägare","i Svärd","i Mynt"],
 "ja": ["ワンド","カップ","ソード","ペンタクル"],
 "ko": ["완드","컵","소드","펜타클"],
 "pt-BR": ["de Paus","de Copas","de Espadas","de Ouros"],
}

def compose_minor(locale, rank_i, suit_i):
    r, s = RANKS[locale][rank_i], SUITS[locale][suit_i]
    if locale in ("de", "fr", "es", "it", "ro", "nl", "sv", "pt-BR", "pl", "uk", "cs", "el"):
        return f"{r} {s}"                      # rank first + case/preposition in the suit
    if locale == "hu":
        return f"{s} – {r}"                    # neutral apposition (possessive is irregular)
    if locale == "tr":
        return f"{s} {r}"                      # suit + possessive rank ("Değnek Ası")
    if locale == "ja":
        return f"{s}の{r}"                     # suit-first with の
    if locale == "ko":
        return f"{s} {r}"                      # suit-first apposition
    raise SystemExit(f"no minor rule for {locale}")

# ── Deck-specific majors (Marseille 1760 + the original Astral deck) ───────────────────
# Only names that are NEW English keys appear here — shared names ("The Empress",
# "Justice"…) reuse the 1909 tables above. Order: key → per-locale value.
MARSEILLE_NEW = {
 "The Juggler": {"de":"Der Gaukler","fr":"Le Bateleur","es":"El Malabarista","it":"Il Bagatto","pl":"Kuglarz","uk":"Жонглер","cs":"Kejklíř","hu":"A Mutatványos","ro":"Jonglerul","el":"Ο Ταχυδακτυλουργός","tr":"Hokkabaz","nl":"De Goochelaar","sv":"Gycklaren","ja":"奇術師","ko":"요술사","pt-BR":"O Saltimbanco"},
 "The Papess": {"de":"Die Päpstin","fr":"La Papesse","es":"La Papisa","it":"La Papessa","pl":"Papieżyca","uk":"Папеса","cs":"Papežka","hu":"A Papnő","ro":"Papesa","el":"Η Πάπισσα","tr":"Kadın Papa","nl":"De Pausin","sv":"Påvinnan","ja":"女教皇","ko":"여교황","pt-BR":"A Papisa"},
 "The Pope": {"de":"Der Papst","fr":"Le Pape","es":"El Papa","it":"Il Papa","pl":"Papież","uk":"Папа","cs":"Papež","hu":"A Pápa","ro":"Papa","el":"Ο Πάπας","tr":"Papa","nl":"De Paus","sv":"Påven","ja":"教皇","ko":"교황","pt-BR":"O Papa"},
 "The Lover": {"de":"Der Liebende","fr":"L'Amoureux","es":"El Enamorado","it":"L'Innamorato","pl":"Zakochany","uk":"Закоханий","cs":"Zamilovaný","hu":"A Szerelmes","ro":"Îndrăgostitul","el":"Ο Ερωτευμένος","tr":"Aşık","nl":"De Verliefde","sv":"Den Förälskade","ja":"恋人","ko":"연인","pt-BR":"O Enamorado"},
 "The Wheel of Fortune": {"de":"Das Rad des Schicksals","fr":"La Roue de Fortune","es":"La Rueda de la Fortuna","it":"La Ruota della Fortuna","pl":"Koło Fortuny","uk":"Колесо Фортуни","cs":"Kolo štěstí","hu":"A Szerencsekerék","ro":"Roata Norocului","el":"Ο Τροχός της Τύχης","tr":"Kader Çarkı","nl":"Het Rad van Fortuin","sv":"Lyckohjulet","ja":"運命の輪","ko":"운명의 수레바퀴","pt-BR":"A Roda da Fortuna"},
 "The Nameless Arcanum": {"de":"Das namenlose Arkanum","fr":"L'Arcane sans nom","es":"El Arcano sin nombre","it":"L'Arcano senza nome","pl":"Arkanum bez imienia","uk":"Аркан без імені","cs":"Arkánum beze jména","hu":"A névtelen arkánum","ro":"Arcana fără nume","el":"Η ανώνυμη Αρκάνα","tr":"İsimsiz Arkana","nl":"Het naamloze arcanum","sv":"Det namnlösa arkanet","ja":"名前のないアルカナ","ko":"이름 없는 아르카나","pt-BR":"O Arcano sem nome"},
 "The House of God": {"de":"Das Gotteshaus","fr":"La Maison Dieu","es":"La Casa de Dios","it":"La Casa di Dio","pl":"Dom Boży","uk":"Дім Божий","cs":"Dům Boží","hu":"Az Isten háza","ro":"Casa Domnului","el":"Ο Οίκος του Θεού","tr":"Tanrı'nın Evi","nl":"Het Godshuis","sv":"Guds hus","ja":"神の家","ko":"신의 집","pt-BR":"A Casa de Deus"},
}

ASTRAL_EN = ["The Comet","The Spark","The Veil","The Aurora","The Polestar","The Keeper",
             "The Twin Stars","The Meteor","The Ember","The Lantern","The Orbit",
             "The Balance","The Eclipse","The Falling Star","The Confluence","The Shadow",
             "The Lightning","The Beacon","The Tide","The Dawn","The Awakening","The Cosmos"]

ASTRAL = {
 "de": ["Der Komet","Der Funke","Der Schleier","Die Aurora","Der Polarstern","Der Hüter","Die Zwillingssterne","Der Meteor","Die Glut","Die Laterne","Die Umlaufbahn","Das Gleichgewicht","Die Finsternis","Die Sternschnuppe","Der Zusammenfluss","Der Schatten","Der Blitz","Das Leuchtfeuer","Die Gezeiten","Die Morgendämmerung","Das Erwachen","Der Kosmos"],
 "fr": ["La Comète","L'Étincelle","Le Voile","L'Aurore","L'Étoile Polaire","Le Gardien","Les Étoiles Jumelles","Le Météore","La Braise","La Lanterne","L'Orbite","L'Équilibre","L'Éclipse","L'Étoile Filante","La Confluence","L'Ombre","L'Éclair","Le Phare","La Marée","L'Aube","L'Éveil","Le Cosmos"],
 "es": ["El Cometa","La Chispa","El Velo","La Aurora","La Estrella Polar","El Guardián","Las Estrellas Gemelas","El Meteoro","La Brasa","La Linterna","La Órbita","El Equilibrio","El Eclipse","La Estrella Fugaz","La Confluencia","La Sombra","El Relámpago","El Faro","La Marea","El Alba","El Despertar","El Cosmos"],
 "it": ["La Cometa","La Scintilla","Il Velo","L'Aurora","La Stella Polare","Il Custode","Le Stelle Gemelle","La Meteora","La Brace","La Lanterna","L'Orbita","L'Equilibrio","L'Eclissi","La Stella Cadente","La Confluenza","L'Ombra","Il Fulmine","Il Faro","La Marea","L'Alba","Il Risveglio","Il Cosmo"],
 "pl": ["Kometa","Iskra","Zasłona","Zorza","Gwiazda Polarna","Strażnik","Gwiazdy Bliźniacze","Meteor","Żar","Latarnia","Orbita","Równowaga","Zaćmienie","Spadająca Gwiazda","Połączenie","Cień","Błyskawica","Latarnia Morska","Przypływ","Świt","Przebudzenie","Kosmos"],
 "uk": ["Комета","Іскра","Завіса","Сяйво","Полярна Зоря","Хранитель","Зорі-Близнюки","Метеор","Жарина","Ліхтар","Орбіта","Рівновага","Затемнення","Падаюча Зоря","Злиття","Тінь","Блискавка","Маяк","Приплив","Світанок","Пробудження","Космос"],
 "cs": ["Kometa","Jiskra","Závoj","Polární záře","Polárka","Strážce","Hvězdná dvojčata","Meteor","Žár","Lucerna","Orbita","Rovnováha","Zatmění","Padající hvězda","Soutok","Stín","Blesk","Maják","Příliv","Úsvit","Probuzení","Kosmos"],
 "hu": ["Az Üstökös","A Szikra","A Fátyol","A Sarki Fény","A Sarkcsillag","Az Őrző","Az Ikercsillagok","A Meteor","A Parázs","A Lámpás","A Keringés","Az Egyensúly","A Fogyatkozás","A Hullócsillag","Az Összefolyás","Az Árnyék","A Villám","A Jelzőfény","Az Árapály","A Hajnal","Az Ébredés","A Kozmosz"],
 "ro": ["Cometa","Scânteia","Vălul","Aurora","Steaua Polară","Păzitorul","Stelele Gemene","Meteorul","Jarul","Felinarul","Orbita","Echilibrul","Eclipsa","Steaua Căzătoare","Confluența","Umbra","Fulgerul","Farul","Mareea","Zorii","Trezirea","Cosmosul"],
 "el": ["Ο Κομήτης","Η Σπίθα","Το Πέπλο","Το Σέλας","Ο Πολικός Αστέρας","Ο Φύλακας","Τα Δίδυμα Αστέρια","Ο Μετεωρίτης","Η Θράκα","Το Φανάρι","Η Τροχιά","Η Ισορροπία","Η Έκλειψη","Το Πεφταστέρι","Η Συμβολή","Η Σκιά","Η Αστραπή","Ο Φάρος","Η Παλίρροια","Η Αυγή","Η Αφύπνιση","Ο Κόσμος"],
 "tr": ["Kuyruklu Yıldız","Kıvılcım","Peçe","Kutup Işığı","Kutup Yıldızı","Bekçi","İkiz Yıldızlar","Göktaşı","Kor","Fener","Yörünge","Denge","Tutulma","Kayan Yıldız","Kavuşum","Gölge","Şimşek","Deniz Feneri","Gelgit","Şafak","Uyanış","Evren"],
 "nl": ["De Komeet","De Vonk","De Sluier","Het Noorderlicht","De Poolster","De Hoeder","De Tweelingsterren","De Meteoor","De Gloed","De Lantaarn","De Omloopbaan","Het Evenwicht","De Eclips","De Vallende Ster","De Samenvloeiing","De Schaduw","De Bliksem","Het Baken","Het Getij","De Dageraad","Het Ontwaken","De Kosmos"],
 "sv": ["Kometen","Gnistan","Slöjan","Norrskenet","Polstjärnan","Väktaren","Tvillingstjärnorna","Meteoren","Glöden","Lyktan","Omloppsbanan","Jämvikten","Förmörkelsen","Stjärnfallet","Sammanflödet","Skuggan","Blixten","Fyren","Tidvattnet","Gryningen","Uppvaknandet","Kosmos"],
 "ja": ["彗星","火花","ヴェール","オーロラ","北極星","番人","双子星","流星","残り火","ランタン","軌道","均衡","蝕","流れ星","合流","影","稲妻","灯台","潮","夜明け","目覚め","宇宙"],
 "ko": ["혜성","불꽃","베일","오로라","북극성","수호자","쌍둥이 별","유성","잉걸불","등불","궤도","균형","일식","별똥별","합류","그림자","번개","등대","조수","새벽","각성","우주"],
 "pt-BR": ["O Cometa","A Faísca","O Véu","A Aurora","A Estrela Polar","O Guardião","As Estrelas Gêmeas","O Meteoro","A Brasa","A Lanterna","A Órbita","O Equilíbrio","O Eclipse","A Estrela Cadente","A Confluência","A Sombra","O Relâmpago","O Farol","A Maré","O Alvorecer","O Despertar","O Cosmos"],
}

# ── Methods: display names + taglines ───────────────────────────────────────────────────
METHODS = {
 "Daily Card": {"de":"Tageskarte","fr":"Carte du jour","es":"Carta del día","it":"Carta del giorno","pl":"Karta dnia","uk":"Карта дня","cs":"Karta dne","hu":"Napi lap","ro":"Cartea zilei","el":"Κάρτα της ημέρας","tr":"Günün kartı","nl":"Dagkaart","sv":"Dagens kort","ja":"今日の一枚","ko":"오늘의 카드","pt-BR":"Carta do dia"},
 "Three Cards": {"de":"Drei Karten","fr":"Trois cartes","es":"Tres cartas","it":"Tre carte","pl":"Trzy karty","uk":"Три карти","cs":"Tři karty","hu":"Három lap","ro":"Trei cărți","el":"Τρεις κάρτες","tr":"Üç kart","nl":"Drie kaarten","sv":"Tre kort","ja":"3枚引き","ko":"세 장의 카드","pt-BR":"Três cartas"},
 "Crossroads": {"de":"Scheideweg","fr":"Croisée des chemins","es":"Encrucijada","it":"Crocevia","pl":"Rozdroże","uk":"Роздоріжжя","cs":"Rozcestí","hu":"Válaszút","ro":"Răscruce","el":"Σταυροδρόμι","tr":"Yol ayrımı","nl":"Tweesprong","sv":"Vägskäl","ja":"岐路","ko":"갈림길","pt-BR":"Encruzilhada"},
 "Celtic Cross": {"de":"Keltisches Kreuz","fr":"Croix celtique","es":"Cruz celta","it":"Croce celtica","pl":"Krzyż celtycki","uk":"Кельтський хрест","cs":"Keltský kříž","hu":"Kelta kereszt","ro":"Crucea celtică","el":"Κελτικός σταυρός","tr":"Kelt haçı","nl":"Keltisch kruis","sv":"Keltiskt kors","ja":"ケルト十字","ko":"켈틱 크로스","pt-BR":"Cruz celta"},
 "One card. A daily pulse.": {"de":"Eine Karte. Ein täglicher Impuls.","fr":"Une carte. Un pouls quotidien.","es":"Una carta. Un pulso diario.","it":"Una carta. Un battito quotidiano.","pl":"Jedna karta. Codzienny impuls.","uk":"Одна карта. Щоденний імпульс.","cs":"Jedna karta. Denní impuls.","hu":"Egy lap. Napi lüktetés.","ro":"O carte. Un puls zilnic.","el":"Μία κάρτα. Ένας καθημερινός παλμός.","tr":"Tek kart. Günlük bir nabız.","nl":"Eén kaart. Een dagelijkse polsslag.","sv":"Ett kort. En daglig puls.","ja":"一枚のカード。毎日の鼓動。","ko":"카드 한 장. 하루의 맥박.","pt-BR":"Uma carta. Um pulso diário."},
 "Three cards. A question, read plainly.": {"de":"Drei Karten. Eine Frage, klar gelesen.","fr":"Trois cartes. Une question, lue simplement.","es":"Tres cartas. Una pregunta, leída con claridad.","it":"Tre carte. Una domanda, letta con chiarezza.","pl":"Trzy karty. Pytanie odczytane wprost.","uk":"Три карти. Питання, прочитане просто.","cs":"Tři karty. Otázka, čtená prostě.","hu":"Három lap. Egy kérdés, tisztán olvasva.","ro":"Trei cărți. O întrebare, citită limpede.","el":"Τρεις κάρτες. Μια ερώτηση, διαβασμένη απλά.","tr":"Üç kart. Sade okunan bir soru.","nl":"Drie kaarten. Een vraag, helder gelezen.","sv":"Tre kort. En fråga, läst rakt på sak.","ja":"3枚のカード。問いを、素直に読む。","ko":"세 장의 카드. 질문을 담백하게 읽다.","pt-BR":"Três cartas. Uma pergunta, lida com clareza."},
 "Five cards. A decision, walked around.": {"de":"Fünf Karten. Eine Entscheidung, umrundet.","fr":"Cinq cartes. Une décision, examinée sous tous les angles.","es":"Cinco cartas. Una decisión, vista desde todos los lados.","it":"Cinque carte. Una decisione, girata da ogni lato.","pl":"Pięć kart. Decyzja obejrzana ze wszystkich stron.","uk":"П'ять карт. Рішення, оглянуте з усіх боків.","cs":"Pět karet. Rozhodnutí obhlédnuté ze všech stran.","hu":"Öt lap. Egy döntés, körüljárva.","ro":"Cinci cărți. O decizie, privită din toate părțile.","el":"Πέντε κάρτες. Μια απόφαση, ιδωμένη από παντού.","tr":"Beş kart. Her yönüyle ele alınan bir karar.","nl":"Vijf kaarten. Een beslissing, van alle kanten bekeken.","sv":"Fem kort. Ett beslut, betraktat från alla håll.","ja":"5枚のカード。決断を、あらゆる角度から。","ko":"다섯 장의 카드. 결정을 두루 살피다.","pt-BR":"Cinco cartas. Uma decisão, vista de todos os lados."},
 "Ten cards. The whole terrain.": {"de":"Zehn Karten. Das ganze Gelände.","fr":"Dix cartes. Tout le terrain.","es":"Diez cartas. Todo el terreno.","it":"Dieci carte. L'intero terreno.","pl":"Dziesięć kart. Cały teren.","uk":"Десять карт. Уся картина.","cs":"Deset karet. Celý terén.","hu":"Tíz lap. A teljes terep.","ro":"Zece cărți. Întregul teren.","el":"Δέκα κάρτες. Όλο το τοπίο.","tr":"On kart. Tüm arazi.","nl":"Tien kaarten. Het hele terrein.","sv":"Tio kort. Hela terrängen.","ja":"10枚のカード。全体像を。","ko":"열 장의 카드. 전체 지형.","pt-BR":"Dez cartas. O terreno inteiro."},
}

# ── Positions / orientation (the Kit's other display strings) ───────────────────────────
EXTRAS = {
 "Situation":  {"de":"Situation","fr":"Situation","es":"Situación","it":"Situazione","pl":"Sytuacja","uk":"Ситуація","cs":"Situace","hu":"Helyzet","ro":"Situație","el":"Κατάσταση","tr":"Durum","nl":"Situatie","sv":"Situation","ja":"状況","ko":"상황","pt-BR":"Situação"},
 "Action":     {"de":"Handlung","fr":"Action","es":"Acción","it":"Azione","pl":"Działanie","uk":"Дія","cs":"Akce","hu":"Cselekvés","ro":"Acțiune","el":"Δράση","tr":"Eylem","nl":"Actie","sv":"Handling","ja":"行動","ko":"행동","pt-BR":"Ação"},
 "Outcome":    {"de":"Ausgang","fr":"Résultat","es":"Resultado","it":"Esito","pl":"Rezultat","uk":"Результат","cs":"Výsledek","hu":"Kimenetel","ro":"Rezultat","el":"Έκβαση","tr":"Sonuç","nl":"Uitkomst","sv":"Utfall","ja":"結果","ko":"결과","pt-BR":"Resultado"},
 "Focus":      {"de":"Fokus","fr":"Focus","es":"Enfoque","it":"Focus","pl":"Skupienie","uk":"Фокус","cs":"Zaměření","hu":"Fókusz","ro":"Focalizare","el":"Εστίαση","tr":"Odak","nl":"Focus","sv":"Fokus","ja":"焦点","ko":"초점","pt-BR":"Foco"},
 "Obstacle":   {"de":"Hindernis","fr":"Obstacle","es":"Obstáculo","it":"Ostacolo","pl":"Przeszkoda","uk":"Перешкода","cs":"Překážka","hu":"Akadály","ro":"Obstacol","el":"Εμπόδιο","tr":"Engel","nl":"Obstakel","sv":"Hinder","ja":"障害","ko":"장애물","pt-BR":"Obstáculo"},
 "Foundation": {"de":"Fundament","fr":"Fondation","es":"Fundamento","it":"Fondamento","pl":"Fundament","uk":"Основа","cs":"Základ","hu":"Alap","ro":"Temelie","el":"Θεμέλιο","tr":"Temel","nl":"Fundament","sv":"Grund","ja":"基盤","ko":"기반","pt-BR":"Fundamento"},
 "Advice":     {"de":"Rat","fr":"Conseil","es":"Consejo","it":"Consiglio","pl":"Rada","uk":"Порада","cs":"Rada","hu":"Tanács","ro":"Sfat","el":"Συμβουλή","tr":"Öğüt","nl":"Advies","sv":"Råd","ja":"助言","ko":"조언","pt-BR":"Conselho"},
 "Direction":  {"de":"Richtung","fr":"Direction","es":"Dirección","it":"Direzione","pl":"Kierunek","uk":"Напрям","cs":"Směr","hu":"Irány","ro":"Direcție","el":"Κατεύθυνση","tr":"Yön","nl":"Richting","sv":"Riktning","ja":"方向","ko":"방향","pt-BR":"Direção"},
 "Heart of the Matter": {"de":"Kern der Sache","fr":"Le cœur du sujet","es":"El corazón del asunto","it":"Il cuore della questione","pl":"Sedno sprawy","uk":"Суть справи","cs":"Jádro věci","hu":"A dolog lényege","ro":"Miezul problemei","el":"Η καρδιά του ζητήματος","tr":"Meselenin özü","nl":"De kern van de zaak","sv":"Sakens kärna","ja":"問題の核心","ko":"문제의 핵심","pt-BR":"O cerne da questão"},
 "What Crosses It": {"de":"Was es kreuzt","fr":"Ce qui le croise","es":"Lo que lo cruza","it":"Ciò che lo attraversa","pl":"Co je krzyżuje","uk":"Що перетинає","cs":"Co to kříží","hu":"Ami keresztezi","ro":"Ce îl traversează","el":"Ό,τι το διασταυρώνει","tr":"Onu kesen","nl":"Wat het kruist","sv":"Det som korsar","ja":"横切るもの","ko":"가로지르는 것","pt-BR":"O que o cruza"},
 "What Passes": {"de":"Was vergeht","fr":"Ce qui passe","es":"Lo que pasa","it":"Ciò che passa","pl":"Co przemija","uk":"Що минає","cs":"Co odchází","hu":"Ami elmúlik","ro":"Ce trece","el":"Ό,τι περνά","tr":"Geçip giden","nl":"Wat voorbijgaat","sv":"Det som går förbi","ja":"過ぎゆくもの","ko":"지나가는 것","pt-BR":"O que passa"},
 "The Crown":  {"de":"Die Krone","fr":"La Couronne","es":"La Corona","it":"La Corona","pl":"Korona","uk":"Корона","cs":"Koruna","hu":"A Korona","ro":"Coroana","el":"Το Στέμμα","tr":"Taç","nl":"De Kroon","sv":"Kronan","ja":"王冠","ko":"왕관","pt-BR":"A Coroa"},
 "What Approaches": {"de":"Was naht","fr":"Ce qui approche","es":"Lo que se acerca","it":"Ciò che si avvicina","pl":"Co nadchodzi","uk":"Що наближається","cs":"Co přichází","hu":"Ami közeledik","ro":"Ce se apropie","el":"Ό,τι πλησιάζει","tr":"Yaklaşan","nl":"Wat nadert","sv":"Det som närmar sig","ja":"近づくもの","ko":"다가오는 것","pt-BR":"O que se aproxima"},
 "The Self":   {"de":"Das Selbst","fr":"Le Soi","es":"El Yo","it":"Il Sé","pl":"Ja","uk":"Я","cs":"Já","hu":"Az Én","ro":"Sinele","el":"Ο Εαυτός","tr":"Benlik","nl":"Het Zelf","sv":"Jaget","ja":"自己","ko":"자아","pt-BR":"O Eu"},
 "The House":  {"de":"Das Haus","fr":"La Maison","es":"La Casa","it":"La Casa","pl":"Dom","uk":"Дім","cs":"Dům","hu":"A Ház","ro":"Casa","el":"Το Σπίτι","tr":"Ev","nl":"Het Huis","sv":"Huset","ja":"家","ko":"집","pt-BR":"A Casa"},
 "Hopes and Fears": {"de":"Hoffnungen und Ängste","fr":"Espoirs et craintes","es":"Esperanzas y temores","it":"Speranze e timori","pl":"Nadzieje i obawy","uk":"Надії та страхи","cs":"Naděje a obavy","hu":"Remények és félelmek","ro":"Speranțe și temeri","el":"Ελπίδες και φόβοι","tr":"Umutlar ve korkular","nl":"Hoop en vrees","sv":"Hopp och farhågor","ja":"希望と恐れ","ko":"희망과 두려움","pt-BR":"Esperanças e medos"},
 "Where It Tends": {"de":"Wohin es sich neigt","fr":"Où cela tend","es":"Hacia dónde tiende","it":"Dove tende","pl":"Dokąd zmierza","uk":"Куди йде","cs":"Kam směřuje","hu":"Merre tart","ro":"Încotro tinde","el":"Πού τείνει","tr":"Nereye gidiyor","nl":"Waar het heen neigt","sv":"Vart det lutar","ja":"向かう先","ko":"향하는 곳","pt-BR":"Para onde tende"},
 "Upright":    {"de":"Aufrecht","fr":"À l'endroit","es":"Al derecho","it":"Dritta","pl":"Prosta","uk":"Пряма","cs":"Vzpřímená","hu":"Egyenes","ro":"Dreaptă","el":"Ορθή","tr":"Düz","nl":"Rechtop","sv":"Upprätt","ja":"正位置","ko":"정방향","pt-BR":"Normal"},
 "Reversed":   {"de":"Umgekehrt","fr":"Inversée","es":"Invertida","it":"Rovesciata","pl":"Odwrócona","uk":"Перевернута","cs":"Obrácená","hu":"Fordított","ro":"Inversată","el":"Αντεστραμμένη","tr":"Ters","nl":"Omgekeerd","sv":"Omvänd","ja":"逆位置","ko":"역방향","pt-BR":"Invertida"},
}

# Verbatim everywhere: brand-ish names and OS paths the system localizes itself.
# Deck names are product identities, like the app's own name.
DO_NOT_TRANSLATE = {"Tarot", "Classic 1909", "Marseille 1760", "Astral",
                    "Settings → Apple Intelligence & Siri"}


def build():
    ui = json.loads((ROOT / "Localization" / "strings_ui.json").read_text())
    strings = dict(ui["strings"])

    for i, en in enumerate(MAJORS_EN):
        strings[en] = {loc: MAJORS[loc][i] for loc in LOCALES}
    for si, s_en in enumerate(SUITS_EN):
        for ri, r_en in enumerate(RANKS_EN):
            en = f"{r_en} of {s_en}"
            strings[en] = {loc: compose_minor(loc, ri, si) for loc in LOCALES}
    # Bare rank names surface on the placeholder card faces.
    for ri, r_en in enumerate(RANKS_EN):
        strings.setdefault(r_en, {loc: RANKS[loc][ri] for loc in LOCALES})
    # Marseille's Valet: the Page/Valet split is an English–French distinction most
    # languages don't make — the Valet keys reuse each locale's page-court word.
    page_i = RANKS_EN.index("Page")
    strings["Valet"] = {loc: RANKS[loc][page_i] for loc in LOCALES}
    for si, s_en in enumerate(SUITS_EN):
        strings[f"Valet of {s_en}"] = {loc: compose_minor(loc, page_i, si) for loc in LOCALES}
    for en, table in MARSEILLE_NEW.items():
        strings[en] = table
    for i, en in enumerate(ASTRAL_EN):
        strings[en] = {loc: ASTRAL[loc][i] for loc in LOCALES}
    for en, table in METHODS.items():
        strings[en] = table
    for en, table in EXTRAS.items():
        strings[en] = table
    for en in DO_NOT_TRANSLATE:
        strings[en] = {"_verbatim": True}

    gaps = []
    for key, row in strings.items():
        if row.get("_verbatim"):
            continue
        missing = [l for l in LOCALES if l not in row or not row[l]]
        if missing:
            gaps.append((key, missing))
    return strings, gaps


def to_xcstrings(strings):
    out = {"sourceLanguage": "en", "version": "1.0", "strings": {}}
    for key in sorted(strings):
        row = strings[key]
        entry = {"extractionState": "manual"}
        if row.get("_verbatim"):
            entry["shouldTranslate"] = False
        else:
            entry["localizations"] = {
                loc: {"stringUnit": {"state": "translated", "value": row[loc]}}
                for loc in LOCALES if loc in row and not loc.startswith("_")
            }
        out["strings"][key] = entry
    return out


if __name__ == "__main__":
    strings, gaps = build()
    if gaps:
        for key, missing in gaps:
            print(f"GAP {key!r}: missing {missing}")
        sys.exit(f"{len(gaps)} keys with gaps")
    if "--check" in sys.argv:
        print(f"{len(strings)} keys, zero gaps")
        sys.exit(0)
    CATALOG.write_text(json.dumps(to_xcstrings(strings), ensure_ascii=False, indent=2,
                                  sort_keys=True) + "\n")
    print(f"wrote {CATALOG.name}: {len(strings)} keys × {len(LOCALES)} locales")
