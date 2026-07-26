import SwiftUI

struct ToolDetailView: View {
    let tool: Tool
    var body: some View {
        ScrollView {
            VStack(spacing: 16) { content }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .background(AppBackground(accent: tool.accent))
        .tint(tool.accent)                       // flows to hero ResultRow + pill segmented control
        .navigationTitle(tool.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder private var content: some View {
        switch tool {
        case .tempo: TempoToolView()
        case .delay: DelayToolView()
        case .timecode: TimecodeToolView()
        case .pitch: PitchToolView()
        case .partch: PartchToolView()
        case .comma: CommaToolView()
        case .mersenne: MersenneToolView()
        case .sabine: SabineToolView()
        case .webster: WebsterToolView()
        case .bernoulli: BernoulliToolView()
        case .formant: FormantToolView()
        case .spl: SPLToolView()
        case .roommodes: RoomModesToolView()
        case .air: AirToolView()
        case .sbir: InterferenceToolView()
        case .butterworth: ButterworthToolView()
        case .fletcher: FletcherToolView()
        case .benchmark: BenchmarkToolView()
        case .passive: PassiveToolView()
        case .biquad: BiquadToolView()
        case .compressor: CompressorToolView()
        case .sra: SRAToolView()
        case .levels: LevelsToolView()
        case .file: FileToolView()
        case .pan: PanToolView()
        case .thiele: ThieleToolView()
        }
    }
}

// `SubScreenPicker` now lives in OTLSegmented.swift (pill style).

/// Initial sub-screen from the screenshot env hook (shared across tools; one launch at a time).
func initialScreen() -> Int { Int(ProcessInfo.processInfo.environment["OVERTONELAB_SCREEN"] ?? "0") ?? 0 }
