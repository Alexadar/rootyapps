import Foundation
import Combine
import FormantKit

@MainActor
final class FormantViewModel: ObservableObject {
    @Published var tractCm = 17.5
    var formants: [(n: Int, hz: Double)] {
        (1...4).map { ($0, Formants.formantHz(tractLengthM: tractCm / 100, n: $0)) }
    }

    @Published var selectedVowel = "ɑ"
    var vowels: [Vowel] { Formants.vowels }
    var vowel: Vowel { Formants.vowels.first { $0.ipa == selectedVowel } ?? Formants.vowels[0] }
}
