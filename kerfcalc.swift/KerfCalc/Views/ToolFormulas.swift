import Foundation

/// FormulaCard content — the actual formula, the cited standard, and a worked example per tool.
/// Transcribed from docs/VALIDATION.md; every line maps to an oracle-backed test (VERIFIED badge).
extension Tool {
    var formula: String { spec.0 }
    var citation: String { spec.1 }
    var example: String? { spec.2 }

    private var spec: (String, String, String?) {
        switch self {
        case .rafter:
            return ("Line = Run · √(12² + rise²) ⁄ 12",
                    "NAVEDTRA 14044 · framing-square table",
                    "6/12, 12 ft run → 13.42\"/ft × 12 = 161.00\"")
        case .stairs:
            return ("Risers = round(Rise ⁄ 7.5)   Stringer = √(Rise² + Run²)",
                    "IRC 2021 R311.7 · 7¾\" riser, 10\" tread",
                    "108\" rise → 14 risers @ 7.71\", 169.01\" stringer")
        case .pitch:
            return ("Diag = √(rise² + run²)   Angle = atan(rise ⁄ run)",
                    "right-triangle trig · roof-pitch tables",
                    "3-4-5 → 5, 36.87° · 6/12 → 26.57°")
        case .concrete:
            return ("yd³ = L · W · T ⁄ 27    Bags = ft³ ⁄ 0.60",
                    "QUIKRETE #1101 · 27 ft³ per yd³",
                    "10×10×4\" slab → 1.235 yd³ · 56 × 80-lb bags")
        case .footing:
            return ("ft³ = L · W · D    yd³ = ft³ ⁄ 27",
                    "geometry · QUIKRETE #1101 yield",
                    "100' × 16\" × 8\" → 88.9 ft³ = 3.29 yd³")
        case .rebar:
            return ("Weight = length · lb⁄ft(size)",
                    "ASTM A615 / CRSI bar table",
                    "#4 = 0.668 lb/ft · 20 ft → 13.4 lb")
        case .aggregate:
            return ("Tons = yd³ · density",
                    "cited typical densities (supplier varies)",
                    "crushed stone ≈ 1.35 t/yd³")
        case .pavers:
            return ("Count = Area · (144 ⁄ L·W) · (1 + waste)",
                    "geometry · pattern waste (editable)",
                    "4×8 paver = 4.5/ft² · 200 ft² +10% → 991")
        case .area:
            return ("□ L·W    △ ½ b·h    ○ π r²",
                    "plane geometry",
                    "r = 1 → π · Heron 3-4-5 → 6")
        case .volume:
            return ("Box L·W·H    Cyl π r² h    yd³ = ft³ ⁄ 27",
                    "solid geometry · 27 ft³ per yd³",
                    "cyl r=1 h=1 → π ft³")
        case .roofing:
            return ("Squares = Plan · √(1 + (rise ⁄ 12)²) ⁄ 100",
                    "roofing slope-factor convention",
                    "6/12 → ×1.118 · 2000 ft² → 22.36 sq")
        case .estimate:
            return ("Sheets = Area ⁄ 32 · (1 + waste)",
                    "geometry · BIA / NCMA coursing",
                    "1000 ft² → 35 sheets (+10% waste)")
        case .miter:
            return ("Miter = atan(sin(spring) · tan(180 ⁄ N))",
                    "published crown-molding tables",
                    "45° spring, 4 sides → 35.26° / 30.00°")
        case .lumber:
            return ("Board ft = T\" · W\" · L' ⁄ 12",
                    "board-foot = 144 in³",
                    "2 × 6 × 10' → 10 bf")
        case .mortar:
            return ("Bags = block ⁄ 13    (brick ⁄ 37)",
                    "QUIKRETE Mason Mix #1136",
                    "100 block → 8 × 80-lb bags")
        case .offset:
            return ("Travel = Set · csc θ    Run = Set · cot θ",
                    "fitting-multiplier tables · csc 45° = 1.41421356",
                    "10\" set at 45° → 14.14\" travel, 10\" run")
        case .rollingOffset:
            return ("True offset = √(Set² + Roll²)    Travel = √(Set² + Roll²) · csc θ",
                    "right-triangle trig · roll = atan(Roll ⁄ Set)",
                    "6\" set, 8\" roll → 10\" true offset → 14.14\" travel at 45°")
        case .cutLength:
            return ("End-to-end = C-to-C − take-out A − take-out B",
                    "definition · take-outs are yours to enter (vary by maker)",
                    "24\" C-to-C less two 1½\" take-outs → 21\" cut")
        case .grade:
            return ("Fall = Run · fall⁄ft    % = fall⁄ft ÷ 12 · 100    1:N, N = 12 ÷ fall⁄ft",
                    "IPC 704.1 / UPC 708.0 minimum slopes",
                    "¼\"/ft = 2.08 % = 1:48 · 40 ft run → 10\" fall")
        case .units:
            return ("value · (m/from) ⁄ (m/to)",
                    "NIST SP 811 · in ≡ 25.4 mm",
                    "1 ft = 0.3048 m")
        }
    }
}
