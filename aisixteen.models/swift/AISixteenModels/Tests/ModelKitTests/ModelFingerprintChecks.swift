import Testing
import Foundation
import ModelKit
@testable import ModelKit

private let when = Date(timeIntervalSince1970: 1_786_000_000)

/// ORACLES:
///  • INVARIANT — stable across process launches. Swift's `hashValue` is salted per process, so a
///    fingerprint built on it would never match on the next launch and resumption would silently
///    never fire.
///  • INVARIANT — independent of enumeration order, which a directory listing does not guarantee.
///  • BEHAVIOUR — changes when the model files change, because that is the whole purpose.
@Suite("ModelFingerprint — is this the same model?")
struct ModelFingerprintTests {

    private let entries = [
        ModelFingerprint.Entry(name: "Unet.mlmodelc", size: 618_000_000, modified: when),
        ModelFingerprint.Entry(name: "TextEncoder.mlmodelc", size: 134_000_000, modified: when),
        ModelFingerprint.Entry(name: "VAEDecoder.mlmodelc", size: 95_000_000, modified: when),
    ]

    @Test("the same model gives the same fingerprint")
    func stable() {
        #expect(ModelFingerprint.of(entries) == ModelFingerprint.of(entries))
    }

    @Test("enumeration order does not change it")
    func orderIndependent() {
        #expect(ModelFingerprint.of(entries) == ModelFingerprint.of(entries.reversed()))
        #expect(ModelFingerprint.of(entries) == ModelFingerprint.of(entries.shuffled()))
    }

    @Test("a changed model changes it")
    func detectsChange() {
        var updated = entries
        updated[0].size = 700_000_000
        #expect(ModelFingerprint.of(entries) != ModelFingerprint.of(updated))

        var touched = entries
        touched[1].modified = when.addingTimeInterval(60)
        #expect(ModelFingerprint.of(entries) != ModelFingerprint.of(touched))

        var renamed = entries
        renamed[2].name = "ControlledUnet.mlmodelc"
        #expect(ModelFingerprint.of(entries) != ModelFingerprint.of(renamed))
    }

    @Test("an added or removed model changes it")
    func detectsMembership() {
        let withControlNet = entries + [
            ModelFingerprint.Entry(name: "ControlNet.mlmodelc", size: 260_000_000, modified: when)
        ]
        #expect(ModelFingerprint.of(entries) != ModelFingerprint.of(withControlNet))
    }

    @Test("it is a short, printable, file-safe string")
    func shape() {
        let value = ModelFingerprint.of(entries)
        #expect(value.count == 16)
        #expect(value.allSatisfy { $0.isHexDigit })
    }
}
