import Foundation
import Combine
import AudioUtilKit

@MainActor
final class FileViewModel: ObservableObject {
    @Published var sampleRate = 44100.0
    @Published var bitDepth = 16.0
    @Published var channels = 2.0
    @Published var minutes = 3.0

    var bytes: Double { FileInfo.sizeBytes(sampleRate: sampleRate, bitDepth: bitDepth, channels: channels, seconds: minutes * 60) }
    var megabytes: Double { bytes / 1_000_000 }
    var nyquist: Double { FileInfo.nyquistHz(sampleRate: sampleRate) }
}
