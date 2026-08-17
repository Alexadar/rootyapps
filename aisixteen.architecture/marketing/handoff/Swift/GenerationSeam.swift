import SwiftUI

// The seam: everything talks to a protocol, never to a model.
// Progress is STEP-BASED — never a 0–1 float. Same contract as the wallpaper app.

enum GenerationStage: String, CaseIterable {
    case reading = "Reading the space"
    case composing = "Composing the redesign"
    case refining = "Refining details"
    case fullRes = "Full resolution"
}

enum GenerationPause {
    case phoneCall        // resumes when the call ends
    case thermal          // running slower to stay cool — still progressing
    case lowBattery       // paused at 10%; resume on charge or user override
    case backgroundSuspended // iOS set it aside; resumes on foreground
}

struct GenerationProgress {
    var stage: GenerationStage
    var step: Int
    var totalSteps: Int
    var intermediate: CGImage?   // decoded latent every 2–3 steps — the forming image
    var pause: GenerationPause?  // nil while running
    var estimatedRemaining: TimeInterval? // rolling estimate from measured step duration
}

struct RedesignRequest {
    var sourcePhoto: CGImage
    var depthMap: CGImage?       // LiDAR or monocular estimate — conditions geometry
    var mode: SpaceMode          // interior / exterior
    var prompt: String           // seeded by a preset, user-editable
    var presetID: String?
    var seed: UInt32?
}

enum SpaceMode: String { case interior, exterior }

protocol RedesignGenerator {
    func generate(_ request: RedesignRequest,
                  progress: @escaping (GenerationProgress) -> Void) async throws -> CGImage
    func cancel()   // plays the morph in reverse; never discards queued siblings
}

// Mock: realistic multi-minute pacing, staged progress, intermediate previews.
final class MockRedesignGenerator: RedesignGenerator {
    private var cancelled = false
    func generate(_ request: RedesignRequest,
                  progress: @escaping (GenerationProgress) -> Void) async throws -> CGImage {
        cancelled = false
        let total = 32
        for step in 1...total {
            try Task.checkCancellation()
            if cancelled { throw CancellationError() }
            let stage: GenerationStage = step <= 4 ? .reading : step <= 12 ? .composing : step <= 28 ? .refining : .fullRes
            // Real cadence ≈ minutes; compressed for the mock.
            try await Task.sleep(for: .seconds(0.4))
            progress(.init(stage: stage, step: step, totalSteps: total,
                           intermediate: step % 3 == 0 ? request.sourcePhoto : nil,
                           pause: nil,
                           estimatedRemaining: Double(total - step) * 0.4))
        }
        return request.sourcePhoto
    }
    func cancel() { cancelled = true }
}
