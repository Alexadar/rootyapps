import XCTest
@testable import DiffusionRuntime

/// The real pack on disk, not a fixture.
///
/// A conversion can report success having done a third of the work — `--convert-controlnet` is
/// `nargs="*"`, so three repeated flags silently converted one net and printed a clean summary. This
/// reads the artefact the apps will actually ship.
final class PackChecks: XCTestCase {

    private let pack = URL(fileURLWithPath:
        "/Users/oleksandr/Projects/rootyapps/aisixteen.models/models/coreml/sd15cn-3nets/Resources")

    func testTheShippedPackCarriesAllThreeControlNets() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: pack.path),
                          "the converted pack is not on this machine")
        let installed = ControlNetCatalog.installed(at: pack)
        XCTAssertEqual(Set(installed.map(\.kind)), [.tile, .mlsd, .depth],
                       "found \(installed.map(\.name))")
    }

    func testEachAppCanFindTheNetItNeeds() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: pack.path))
        // Wallpapers and Studio want tile; Architecture wants lines and depth and not tile.
        XCTAssertNotNil(ControlNetCatalog.name(of: .tile, at: pack))
        XCTAssertNotNil(ControlNetCatalog.name(of: .mlsd, at: pack))
        XCTAssertNotNil(ControlNetCatalog.name(of: .depth, at: pack))
    }

    func testThePackDeclaresItselfAndCarriesItsLicence() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: pack.path))
        let declaration = try Data(contentsOf: pack.appendingPathComponent("model.json"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: declaration) as? [String: Any])
        XCTAssertEqual(json["id"] as? String, "sd15cn")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: pack.appendingPathComponent("LICENCE.txt").path),
            "the terms must travel with the weights")
    }
}
