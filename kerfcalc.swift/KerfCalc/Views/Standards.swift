import SwiftUI

/// Single source of truth for the external standards kerfcalc's math is validated against — the
/// edition/date each was transcribed from, and how volatile it is. When a code cycle or a
/// manufacturer sheet updates, bump the `edition` here (and the matching oracle test) — this is the
/// one place to look. Shown to users in the Reference tab so the editions are transparent.
struct Standard: Identifiable {
    enum Tier: String { case fixed = "Fixed", code = "Code cycle", product = "Product" }
    let name: String
    let governs: String
    let edition: String
    let tier: Tier
    var id: String { name }
}

extension Standard {
    /// Colour per volatility tier (green = won't change, amber = code cycle, rose = market data).
    var tierColor: Color {
        switch tier { case .fixed: return KC.ok; case .code: return Color(rgbHex: 0x5B8DEF); case .product: return Color(rgbHex: 0xE08AA0) }
    }

    static let all: [Standard] = [
        // Fixed — math / physics / definitional. Effectively permanent.
        .init(name: "NIST SP 811", governs: "in/ft/yd ↔ metric", edition: "1959 intl agreement", tier: .fixed),
        .init(name: "ASTM A615", governs: "rebar area & weight", edition: "A615-20", tier: .fixed),
        .init(name: "Framing square / NAVEDTRA 14044", governs: "rafter lengths", edition: "public domain", tier: .fixed),
        .init(name: "Plane geometry / trig", governs: "area, volume, pitch, miter", edition: "—", tier: .fixed),
        .init(name: "Fitting multipliers (csc/cot θ)", governs: "pipe offset travel & run", edition: "trig identity", tier: .fixed),
        .init(name: "ASME B36.10M", governs: "pipe weight cross-check", edition: "Sch-40 table", tier: .fixed),

        // Code cycle — revised on a ~3-year cadence; jurisdictions adopt different editions.
        .init(name: "IRC", governs: "residential stairs (R311.7)", edition: "2021", tier: .code),
        .init(name: "IBC", governs: "commercial stairs", edition: "2021", tier: .code),
        .init(name: "IPC 704.1 / UPC 708.0", governs: "drainage slope minimums", edition: "2021", tier: .code),
        .init(name: "ACI 360R", governs: "slab control joints", edition: "360R-10", tier: .code),
        .init(name: "CRSI / ACI 318 §25.5", governs: "rebar lap (rule of thumb)", edition: "field approx.", tier: .code),
        .init(name: "NCMA TEK 3-2A", governs: "CMU grout volume", edition: "2005", tier: .code),

        // Product / market — manufacturer sheets & estimating conventions; editable in-app.
        .init(name: "QUIKRETE #1101", governs: "concrete bag yield", edition: "data sheet", tier: .product),
        .init(name: "QUIKRETE #1136", governs: "mortar coverage", edition: "data sheet", tier: .product),
        .init(name: "Aggregate densities", governs: "gravel/base tonnage", edition: "supplier typical", tier: .product),
        .init(name: "Estimating conventions", governs: "waste %, paint coverage", edition: "editable", tier: .product),
    ]
}
