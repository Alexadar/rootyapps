import XCTest
@testable import ModelKit

/// What a model *is*, independent of whether one is installed.
///
/// The catalogue that finds a pack on disk lives in the app; this is the vocabulary it finds packs
/// *as*. Two properties matter and both are about not guessing: an id is compared against one
/// written by the converter in this same repository, and the memory floor is a measured number
/// rather than a device allow-list that goes stale every September.
final class ModelIdentityChecks: XCTestCase {

    // MARK: The identity itself

    func testTheShippingModelDescribesWhatIsActuallyConverted() {
        let model = ModelIdentity.sd15cn
        XCTAssertEqual(model.id, "sd15cn")
        XCTAssertEqual(model.family, .stableDiffusion15)
        // Fixed-shape Core ML graphs: 512 is a property of the files, not a preference.
        XCTAssertEqual(model.nativeSide, 512)
        XCTAssertTrue(model.hasControlNet)
        XCTAssertEqual(ModelIdentity.known(id: "sd15cn"), model)
        XCTAssertNil(ModelIdentity.known(id: "sdxl"), "an unmeasured model must not be listed")
    }

    func testEveryKnownModelHasADistinctID() {
        // Two entries sharing an id is silent: `known(id:)` returns the first, and half-finished
        // work from one model gets handed to the other.
        // One entry today. The check is here because the failure is silent when there are two:
        // `known(id:)` returns the first, and half-finished work from one model is handed to the
        // other.
        let ids = ModelIdentity.known.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate model id in the catalogue")
        for model in ModelIdentity.known {
            XCTAssertEqual(ModelIdentity.known(id: model.id), model)
            XCTAssertFalse(model.displayName.isEmpty)
            XCTAssertGreaterThan(model.nativeSide, 0)
        }
    }

    func testTheHardwareCheckIsAgainstAMeasuredNumber() {
        // The reason identity exists separately from installation: when there is a choice of packs,
        // it has to be filtered by what the device can hold. A 4 GB device does not fail politely
        // under this load — it reboots, which this project has done.
        XCTAssertGreaterThan(ModelIdentity.sd15cn.minimumDeviceMemoryBytes, 4 * 1_073_741_824)
        XCTAssertGreaterThan(ModelIdentity.sd15cn.approximateResidentBytes, 1_000_000_000)
        // This machine runs it, which is the only claim that can be checked here.
        XCTAssertTrue(ModelIdentity.sd15cn.fitsThisDevice)
    }

}
