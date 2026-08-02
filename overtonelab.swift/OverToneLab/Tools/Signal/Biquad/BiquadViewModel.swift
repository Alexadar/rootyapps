import Foundation
import Combine
import BiquadKit

@MainActor
final class BiquadViewModel: ObservableObject {
    @Published var kind: Biquad.Kind = .lowpass
    @Published var fs = 48000.0
    @Published var f0 = 1000.0
    @Published var q = 0.7071
    @Published var gainDB = 6.0
    @Published var probe = 1000.0

    var coeffs: Biquad.Coeffs { Biquad.design(kind, fs: fs, f0: f0, q: q, gainDB: gainDB) }
    var magAtF0: Double { Biquad.magnitudeDB(coeffs, hz: f0, fs: fs) }
    var magAtProbe: Double { Biquad.magnitudeDB(coeffs, hz: probe, fs: fs) }
}
