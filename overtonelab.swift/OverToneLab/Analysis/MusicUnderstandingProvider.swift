//  MusicUnderstandingProvider.swift
//
//  ⚠️ UNIMPLEMENTED — DELIBERATELY. Do not treat the comments below as a specification.
//
//  MusicUnderstanding is a WWDC26 framework. It is ABSENT from the installed SDK (verified against
//  iPhoneOS 26.5), which means everything inside `#if canImport(MusicUnderstanding)` is never
//  compiled here: it cannot be type-checked, built, run or tested on this machine.
//
//  Writing a plausible-looking adapter against an API nobody here can read would produce code that
//  looks finished, compiles nowhere, and would be discovered to be wrong only on a beta toolchain —
//  after it had been reviewed as if it worked. So this file is a marked placeholder instead.
//
//  WHAT IS ALREADY REAL, and does not need this file:
//    • MeasureKit           — beats → BPM, bars, key naming, LUFS/peak, with a boundary oracle
//    • MeasurementStore     — the session, its presence states and the routing table
//    • FieldProvenance      — measured/typed marking and revert-to-pre-handoff
//    • FixtureAnalysisProvider — drives all of the above from OVERTONELAB_SESSION, no microphone
//
//  WHAT THIS FILE OWES, when a beta toolchain is available:
//    • conform to `AnalysisProvider` (start(onUpdate:) / stop / sourceName)
//    • request microphone permission FROM THE LISTEN BUTTON, never at launch, and add
//      INFOPLIST_KEY_NSMicrophoneUsageDescription to the gated build only — an unused permission
//      string in a shipping build is a review liability
//    • map the framework's output onto MeasureKit, not onto the UI: beat onsets → Measure.bpm
//      (which returns nil until two beats, never 0), loudness → Measure.integratedLUFS, peak →
//      Measure.peakDB, tonic/mode → Measure.keyName
//    • pass section labels and pace THROUGH, untested and unasserted — they have no ground truth
//      (DESIGN_GUIDELINES §10)
//    • render no target, no delta and no verdict anywhere in Analysis: that boundary is what keeps
//      LUFS from existing in two places, and `benchmark` owns the reasoning
//
//  Until then `AnalysisProviderFactory.make()` returns the fixture provider, or nil.

import Foundation

#if canImport(MusicUnderstanding)
import MusicUnderstanding

@available(iOS 27, macOS 27, *)
@MainActor
final class MusicUnderstandingProvider: AnalysisProvider {
    var sourceName: String { "Live input" }

    func start(onUpdate: @escaping (MeasurementStore.Session) -> Void) async throws {
        // Intentionally unimplemented — see the file header.
        throw AnalysisProviderError.unavailable
    }

    func stop() {}
}
#endif
