import SwiftUI

enum ToolSection: String, CaseIterable, Identifiable {
    case timing = "Timing", tuning = "Tuning", acoustics = "Acoustics",
         signal = "Signal", stereo = "Stereo", utility = "Utility", design = "Design"
    var id: String { rawValue }
}

enum Tool: String, CaseIterable, Identifiable, Hashable {
    case tempo, delay, timecode, pitch            // Timing
    case partch, comma, mersenne                  // Tuning
    case sabine, webster, bernoulli, formant, spl, roommodes, air, sbir // Acoustics
    case butterworth, fletcher, benchmark, passive, biquad, compressor // Signal
    case sra                                      // Stereo
    case levels, file, pan                        // Utility
    case thiele                                   // Design

    var id: String { rawValue }

    var section: ToolSection {
        switch self {
        case .tempo, .delay, .timecode, .pitch: return .timing
        case .partch, .comma, .mersenne: return .tuning
        case .sabine, .webster, .bernoulli, .formant, .spl, .roommodes, .air, .sbir: return .acoustics
        case .butterworth, .fletcher, .benchmark, .passive, .biquad, .compressor: return .signal
        case .sra: return .stereo
        case .levels, .file, .pan: return .utility
        case .thiele: return .design
        }
    }

    var title: String {
        switch self {
        case .tempo: return "Tempo"; case .delay: return "Delay"; case .timecode: return "Timecode"; case .pitch: return "Pitch"
        case .partch: return "Partch"; case .comma: return "Comma"; case .mersenne: return "Mersenne"
        case .sabine: return "Sabine"; case .webster: return "Webster"; case .bernoulli: return "Bernoulli"
        case .formant: return "Formant"; case .spl: return "SPL"
        case .roommodes: return "Room Modes"; case .air: return "Air"; case .sbir: return "SBIR"
        case .butterworth: return "Butterworth"; case .fletcher: return "Fletcher"; case .benchmark: return "Benchmark"; case .passive: return "Passive"
        case .biquad: return "Biquad"; case .compressor: return "Compressor"
        case .sra: return "SRA"
        case .levels: return "Levels"; case .file: return "File"; case .pan: return "Pan"
        case .thiele: return "Thiele"
        }
    }

    var subtitle: String {
        switch self {
        case .tempo: return "Note length & tempo"
        case .delay: return "Delay & distance"
        case .timecode: return "SMPTE timecode"
        case .pitch: return "Note · frequency · wavelength"
        case .partch: return "Just intonation & cents"
        case .comma: return "EDO & temperament"
        case .mersenne: return "String tension & frets"
        case .sabine: return "Room reverberation"
        case .webster: return "Horns & Helmholtz"
        case .bernoulli: return "Pipe resonance"
        case .formant: return "Vocal-tract formants"
        case .spl: return "Sound pressure level"
        case .roommodes: return "Modes, ratios & Bonello"
        case .air: return "Air absorption (ISO 9613)"
        case .sbir: return "Boundary & comb filtering"
        case .butterworth: return "Filters & crossovers"
        case .fletcher: return "A / C / Z weighting"
        case .benchmark: return "LUFS loudness"
        case .passive: return "RC / RL / LC filters"
        case .biquad: return "IIR filter coefficients"
        case .compressor: return "Compressor & knee"
        case .sra: return "Stereo recording angle"
        case .levels: return "Decibels & reference levels"
        case .file: return "File size & sample rate"
        case .pan: return "Pan law"
        case .thiele: return "Loudspeaker boxes"
        }
    }

    var symbol: String {
        switch self {
        case .tempo: return "metronome"; case .delay: return "timer"; case .timecode: return "film"; case .pitch: return "pianokeys.inverse"
        case .partch: return "function"; case .comma: return "circle.grid.3x3"; case .mersenne: return "tuningfork"
        case .sabine: return "waveform.path"; case .webster: return "horn"; case .bernoulli: return "pianokeys"
        case .formant: return "mouth"; case .spl: return "speaker.wave.3"
        case .roommodes: return "cube"; case .air: return "wind"; case .sbir: return "alternatingcurrent"
        case .butterworth: return "waveform.path.ecg"; case .fletcher: return "waveform"; case .benchmark: return "target"; case .passive: return "capsule.portrait"
        case .biquad: return "chart.xyaxis.line"; case .compressor: return "chart.line.downtrend.xyaxis"
        case .sra: return "angle"
        case .levels: return "dial.medium"; case .file: return "doc"; case .pan: return "arrow.left.and.right"
        case .thiele: return "hifispeaker"
        }
    }

    static func tools(in section: ToolSection) -> [Tool] { allCases.filter { $0.section == section } }
}
