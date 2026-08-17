import Foundation
import Testing
@testable import ProjectKit

/// A real temporary directory per test. The store's whole job is files, so testing it against a
/// fake file system would test the fake.
struct TempRoot: ~Copyable {
    let url: URL
    init() {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("projectkit-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}

enum Make {
    static let created = Date(timeIntervalSince1970: 1_786_544_520)   // 2026-08-12T14:22:00Z

    static func recipe(seed: UInt32 = 0x3F9C1A, variations: Int = 3) -> ProjectRecipe {
        ProjectRecipe(presetID: "scandi",
                      prompt: "Bright Scandinavian living room, pale oak floor",
                      isEdited: false,
                      baseSeed: seed,
                      requestedVariations: variations)
    }

    static func store(_ root: URL, access: any FileAccess = DirectFileAccess()) -> ProjectStore {
        ProjectStore(root: root, access: access, appVersion: "1.0.0")
    }

    @discardableResult
    static func project(in store: ProjectStore,
                        name: String = "Living room",
                        mode: SpaceMode = .interior,
                        depth: DepthProvenance = .lidar) throws -> SpaceProject {
        try store.createProject(displayName: name,
                                mode: mode,
                                createdAt: created,
                                recipe: recipe(),
                                depthProvenance: depth,
                                sourceData: Data("source-photo".utf8),
                                depthData: Data("depth-map".utf8),
                                sourcePixelWidth: 3024,
                                sourcePixelHeight: 4032)
    }

    static func variation(_ index: Int, seed: UInt32 = 0x3F9C1A) -> VariationSidecar {
        VariationSidecar(index: index,
                         seed: seed,
                         createdAt: created,
                         elapsedSeconds: 137,
                         stepsRun: 32,
                         resumedFromStep: nil,
                         prompt: "Bright Scandinavian living room, pale oak floor",
                         presetID: "scandi")
    }
}

@Suite("Folder names")
struct ProjectFolderNameChecks {

    @Test("A folder name is readable, sortable and unique")
    func nameShape() {
        let name = ProjectFolderName.make(displayName: "Living room",
                                          createdAt: Make.created,
                                          seed: 0x3F9C1A)
        // The user opens this in Files. It has to read as something.
        #expect(name == "Living-room-2026-08-12T14-22-00Z-3f9c1a")
    }

    @Test("Colons never reach the filesystem")
    func noColons() {
        // Legal on APFS, a disaster anywhere the folder is zipped or synced through something
        // older that still treats a colon as a path separator.
        let name = ProjectFolderName.make(displayName: "Kitchen", createdAt: Make.created, seed: 1)
        #expect(!name.contains(":"))
        #expect(!name.contains("/"))
    }

    @Test("Awkward display names become safe slugs")
    func slugsAreSafe() {
        #expect(ProjectFolderName.slug("Living room") == "Living-room")
        #expect(ProjectFolderName.slug("Mum's kitchen / back") == "Mum-s-kitchen-back")
        #expect(ProjectFolderName.slug("   ") == "Space")
        #expect(ProjectFolderName.slug("") == "Space")
        // Emoji and non-Latin scripts are stripped rather than mangled — the sidecar keeps the
        // real name, so nothing is lost.
        #expect(!ProjectFolderName.slug("Вітальня 🛋").contains("🛋"))
        #expect(ProjectFolderName.slug(String(repeating: "a", count: 200)).count <= 48)
    }

    @Test("The same space redesigned twice does not collide")
    func repeatedNamesDoNotCollide() {
        let first = ProjectFolderName.make(displayName: "Living room", createdAt: Make.created, seed: 1)
        let second = ProjectFolderName.make(displayName: "Living room",
                                            createdAt: Make.created.addingTimeInterval(60), seed: 2)
        #expect(first != second)
    }

    @Test("A ghost folder still yields a name and a date")
    func ghostFolderIsReadable() {
        // Before `project.json` syncs, the folder name is all the library has.
        let folder = "Living-room-2026-08-12T14-22-00Z-3f9c1a"
        #expect(ProjectFolderName.displayName(fromFolder: folder) == "Living room")
        #expect(ProjectFolderName.date(fromFolder: folder) == Make.created)
    }

    @Test("A folder that is not ours is left alone rather than misparsed")
    func foreignFolderNames() {
        #expect(ProjectFolderName.displayName(fromFolder: "Screenshots") == "Screenshots")
        #expect(ProjectFolderName.date(fromFolder: "Screenshots") == nil)
    }

    @Test("Variation filenames carry the index and the seed, and parse back")
    func variationFilenames() {
        #expect(ProjectFile.variationImage(index: 1, seed: 0x3F9C1A) == "01-3f9c1a.png")
        #expect(ProjectFile.variationSidecar(index: 12, seed: 0xA17B04) == "12-a17b04.json")
        #expect(ProjectFile.variationIndex(fromFilename: "01-3f9c1a.png") == 1)
        #expect(ProjectFile.variationIndex(fromFilename: "notes.txt") == nil)
    }

    @Test("Automatic names say what the space is and when")
    func automaticNaming() {
        // No screen asks for a name, and adding a naming step between the shutter and the redesign
        // would interrupt the one moment the user most wants to get on with it.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let name = ProjectFolderName.automaticDisplayName(mode: .interior,
                                                          createdAt: Make.created,
                                                          locale: Locale(identifier: "en_US"),
                                                          calendar: calendar)
        #expect(name.hasPrefix("Interior — "))
        #expect(name.contains("Aug"))

        let exterior = ProjectFolderName.automaticDisplayName(mode: .exterior,
                                                              createdAt: Make.created,
                                                              locale: Locale(identifier: "en_US"),
                                                              calendar: calendar)
        #expect(exterior.hasPrefix("Exterior — "))
    }

    @Test("Variation seeds derive from one base seed")
    func seedsAreReproducible() {
        let recipe = Make.recipe(seed: 1000)
        #expect(recipe.seed(forVariation: 1) == 1000)
        #expect(recipe.seed(forVariation: 3) == 1002)
    }
}

@Suite("Project store")
struct ProjectStoreChecks {

    @Test("An empty root lists nothing and is not an error")
    func emptyRoot() throws {
        let root = TempRoot()
        let listed = try Make.store(root.url).projects()
        #expect(listed.isEmpty)
    }

    @Test("A created project round-trips with everything it needs to regenerate")
    func createAndRead() throws {
        let root = TempRoot()
        let store = Make.store(root.url)
        let created = try Make.project(in: store)

        let listed = try store.projects()
        #expect(listed.count == 1)
        let project = try #require(listed.first)

        #expect(project.displayName == "Living room")
        #expect(project.sidecar?.mode == .interior)
        #expect(project.sidecar?.recipe.baseSeed == 0x3F9C1A)
        #expect(project.sidecar?.recipe.prompt == "Bright Scandinavian living room, pale oak floor")
        #expect(project.sidecar?.depthProvenance == .lidar)
        #expect(project.sidecar?.appVersion == "1.0.0")
        #expect(!project.isGhost)
        // lastPathComponent, not the whole URL: NSTemporaryDirectory hands back /var/… and the
        // file system resolves it to /private/var/…, so the two URLs differ by a symlink.
        #expect(project.folder.lastPathComponent == created.folder.lastPathComponent)

        #expect(FileManager.default.fileExists(atPath: project.sourceURL.path))
        #expect(FileManager.default.fileExists(atPath: project.depthURL.path))
    }

    @Test("project.json never lists the variations")
    func sidecarHasNoVariationList() throws {
        // The regression guard for the concurrency decision: if this file listed variations, two
        // devices adding one each would produce an iCloud conflict over the WHOLE project rather
        // than over one picture.
        let root = TempRoot()
        let store = Make.store(root.url)
        let project = try Make.project(in: store)
        try store.appendVariation(to: project.folder,
                                  sidecar: Make.variation(1),
                                  imageData: Data("png".utf8),
                                  thumbnailData: Data("thumb".utf8))

        // The invariant is that no VALUE in the sidecar is a list. (`requestedVariations` is a
        // count, and a count is fine — it is what the user asked for, not what exists.)
        let data = try Data(contentsOf: project.folder.appendingPathComponent(ProjectFile.sidecar))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["variations"] == nil)
        for (key, value) in object {
            #expect(!(value is [Any]), "\(key) is a list, which two devices would conflict over")
        }
        #expect(object["recipe"] is [String: Any])
    }

    @Test("Sidecars are pretty-printed, because the user can open them")
    func sidecarsAreReadable() throws {
        let root = TempRoot()
        let project = try Make.project(in: Make.store(root.url))
        let raw = try String(contentsOf: project.folder.appendingPathComponent(ProjectFile.sidecar),
                             encoding: .utf8)
        #expect(raw.contains("\n"), "a one-line sidecar says 'not for you'")
        #expect(raw.contains("2026-08-12T14:22:00Z"), "ISO 8601, not a float since 1970")
    }

    @Test("Variations are discovered from the folder, in order")
    func variationsAreDiscovered() throws {
        let root = TempRoot()
        let store = Make.store(root.url)
        let project = try Make.project(in: store)

        for index in [3, 1, 2] {
            try store.appendVariation(to: project.folder,
                                      sidecar: Make.variation(index, seed: UInt32(0x100 + index)),
                                      imageData: Data("png-\(index)".utf8),
                                      thumbnailData: nil)
        }

        let reloaded = try #require(try store.projects().first)
        #expect(reloaded.variations.map(\.index) == [1, 2, 3])
        #expect(reloaded.variations.allSatisfy { $0.imageIsPresent })
        #expect(reloaded.finishedCount == 3)
    }

    @Test("A picture with no sidecar is skipped, not shown as a broken tile")
    func orphanImageIsSkipped() throws {
        // Half a sync. There is nothing truthful to say about it — no seed, no prompt, no date.
        let root = TempRoot()
        let store = Make.store(root.url)
        let project = try Make.project(in: store)
        let directory = project.folder.appendingPathComponent(ProjectFile.variationsFolder,
                                                              isDirectory: true)
        try Data("png".utf8).write(to: directory.appendingPathComponent("01-3f9c1a.png"))

        let reloaded = try #require(try store.projects().first)
        #expect(reloaded.variations.isEmpty)
    }

    @Test("A sidecar with no picture is pending, not broken")
    func sidecarWithoutImageIsPending() throws {
        // The other half of a sync. The record arrived first, so the library knows what is coming
        // and can show a real download percentage.
        let root = TempRoot()
        let store = Make.store(root.url)
        let project = try Make.project(in: store)
        let directory = project.folder.appendingPathComponent(ProjectFile.variationsFolder,
                                                              isDirectory: true)
        try ProjectStore.encoder.encode(Make.variation(1))
            .write(to: directory.appendingPathComponent("01-3f9c1a.json"))

        let reloaded = try #require(try store.projects().first)
        #expect(reloaded.variations.count == 1)
        #expect(reloaded.variations[0].imageIsPresent == false)
        #expect(reloaded.finishedCount == 0)
        #expect(reloaded.variations[0].sidecar.seed == 0x3F9C1A)
    }

    @Test("A folder with no sidecar is a ghost, not an error and not hidden")
    func ghostProject() throws {
        // The folder synced but project.json has not. The user can see it in Files; hiding it
        // would be a worse lie than showing it as still arriving.
        let root = TempRoot()
        let folder = root.url.appendingPathComponent("Facade-2026-08-12T14-22-00Z-a17b04",
                                                      isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let projects = try Make.store(root.url).projects()
        #expect(projects.count == 1)
        #expect(projects[0].isGhost)
        #expect(projects[0].displayName == "Facade")
        #expect(projects[0].createdAt == Make.created)
    }

    @Test("Unrelated files in the library are ignored")
    func foreignFilesAreIgnored() throws {
        // It is the user's folder. They are allowed to put a PDF in it.
        let root = TempRoot()
        let store = Make.store(root.url)
        try Make.project(in: store)
        try Data("hello".utf8).write(to: root.url.appendingPathComponent("notes.pdf"))

        let listed = try store.projects()
        #expect(listed.count == 1)
    }

    @Test("Projects list newest first")
    func newestFirst() throws {
        let root = TempRoot()
        let store = Make.store(root.url)
        _ = try store.createProject(displayName: "Older", mode: .interior,
                                    createdAt: Make.created.addingTimeInterval(-86_400),
                                    recipe: Make.recipe(seed: 1), depthProvenance: .lidar,
                                    sourceData: Data(), depthData: nil,
                                    sourcePixelWidth: 100, sourcePixelHeight: 100)
        _ = try store.createProject(displayName: "Newer", mode: .exterior,
                                    createdAt: Make.created,
                                    recipe: Make.recipe(seed: 2), depthProvenance: .estimated,
                                    sourceData: Data(), depthData: nil,
                                    sourcePixelWidth: 100, sourcePixelHeight: 100)

        let names = try store.projects().map(\.displayName)
        #expect(names == ["Newer", "Older"])
    }

    @Test("Renaming writes the sidecar first, so the name survives a failed move")
    func renameKeepsTheSidecarAuthoritative() throws {
        let root = TempRoot()
        let store = Make.store(root.url)
        let project = try Make.project(in: store)

        let renamed = try store.rename(project, to: "Lounge")
        #expect(renamed.displayName == "Lounge")
        #expect(renamed.sidecar?.displayName == "Lounge")
        #expect(renamed.folder.lastPathComponent.hasPrefix("Lounge-"))
        // Renaming does not disturb what the project IS.
        #expect(renamed.sidecar?.id == project.sidecar?.id)
        #expect(renamed.sidecar?.recipe.baseSeed == project.sidecar?.recipe.baseSeed)
        let all = try store.projects()
        #expect(all.count == 1)
    }

    @Test("Renaming a ghost is refused rather than inventing a sidecar")
    func renamingAGhostFails() throws {
        let root = TempRoot()
        let folder = root.url.appendingPathComponent("Facade-2026-08-12T14-22-00Z-a17b04",
                                                      isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = Make.store(root.url)
        let ghost = try #require(try store.projects().first)

        #expect(throws: ProjectStore.StoreError.notAProject(ghost.folder)) {
            _ = try store.rename(ghost, to: "Anything")
        }
    }

    @Test("Deleting a project removes the whole tree")
    func deleteRemovesEverything() throws {
        let root = TempRoot()
        let store = Make.store(root.url)
        let project = try Make.project(in: store)
        try store.appendVariation(to: project.folder, sidecar: Make.variation(1),
                                  imageData: Data("png".utf8), thumbnailData: nil)

        try store.delete(project)
        let remaining = try store.projects()
        #expect(remaining.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: project.folder.path))
    }

    @Test("Deleting one variation leaves the project and its siblings")
    func deleteVariationIsScoped() throws {
        let root = TempRoot()
        let store = Make.store(root.url)
        let project = try Make.project(in: store)
        for index in 1...3 {
            try store.appendVariation(to: project.folder,
                                      sidecar: Make.variation(index, seed: UInt32(0x100 + index)),
                                      imageData: Data("png".utf8), thumbnailData: nil)
        }
        let loaded = try #require(try store.projects().first)
        try store.deleteVariation(loaded.variations[1], in: loaded)

        let after = try #require(try store.projects().first)
        #expect(after.variations.map(\.index) == [1, 3])
        #expect(!after.isGhost)
    }

    @Test("The store behaves identically over an iCloud root and a local root")
    func bothRootsBehaveTheSame() throws {
        // This is the whole iCloud story: the same code over two URLs, so a user with iCloud
        // switched off exercises paths that were actually tested.
        let cloudish = TempRoot()
        let local = TempRoot()

        let coordinated = Make.store(cloudish.url, access: CoordinatedFileAccess())
        let direct = Make.store(local.url, access: DirectFileAccess())

        for store in [coordinated, direct] {
            let project = try Make.project(in: store)
            try store.appendVariation(to: project.folder, sidecar: Make.variation(1),
                                      imageData: Data("png".utf8), thumbnailData: Data("t".utf8))
        }

        let left = try #require(try coordinated.projects().first)
        let right = try #require(try direct.projects().first)

        #expect(left.displayName == right.displayName)
        #expect(left.variations.count == right.variations.count)
        #expect(left.sidecar?.recipe == right.sidecar?.recipe)
        #expect(left.folder.lastPathComponent == right.folder.lastPathComponent)
    }

    @Test("A sidecar from a future version still parses what it can")
    func unknownFieldsAreTolerated() throws {
        // A project synced from a newer build must not make the library unreadable.
        let root = TempRoot()
        let folder = root.url.appendingPathComponent("Loft-2026-08-12T14-22-00Z-000001",
                                                      isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = """
        {
          "version": 9,
          "id": "abc",
          "displayName": "Loft",
          "mode": "interior",
          "createdAt": "2026-08-12T14:22:00Z",
          "appVersion": "9.9.9",
          "recipe": { "prompt": "x", "isEdited": false, "baseSeed": 7, "requestedVariations": 2 },
          "depthProvenance": "lidar",
          "sourcePixelWidth": 10,
          "sourcePixelHeight": 10,
          "somethingFromTheFuture": { "nested": true }
        }
        """
        try Data(json.utf8).write(to: folder.appendingPathComponent(ProjectFile.sidecar))

        let project = try #require(try Make.store(root.url).projects().first)
        #expect(!project.isGhost)
        #expect(project.displayName == "Loft")
        #expect(project.sidecar?.version == 9)
    }

    @Test("A corrupt sidecar degrades to a ghost rather than losing the folder")
    func corruptSidecarBecomesAGhost() throws {
        let root = TempRoot()
        let folder = root.url.appendingPathComponent("Attic-2026-08-12T14-22-00Z-000002",
                                                      isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: folder.appendingPathComponent(ProjectFile.sidecar))

        let project = try #require(try Make.store(root.url).projects().first)
        #expect(project.isGhost)
        #expect(project.displayName == "Attic")
    }
}
