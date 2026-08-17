import Foundation
import SwiftData

/// Composition root: builds the store (real SwiftData container — in-memory when the
/// DEBUG launch hook asks for it), pipeline, and services, and seeds fixtures for
/// deterministic UITest runs.
@MainActor
final class AppEnvironment: ObservableObject {

    let store: any DocumentStore
    let importService: ImportService
    let exportService: ExportService
    let indexer: SpotlightIndexer
    let pipeline: ExtractionPipeline

    init() {
        let schema = Schema([DocumentRecord.self, ReviewFlagRecord.self,
                             AuditEventRecord.self])
        let inMemory = LaunchOverride.value("GRIDSCAN_STORE") == "memory"
        let configuration = ModelConfiguration(schema: schema,
                                               isStoredInMemoryOnly: inMemory)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A corrupt on-disk store must not brick the app: fall back to memory and
            // let the user re-import. The documents' originals are still on disk.
            container = try! ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
        let store = SwiftDataDocumentStore(modelContainer: container)
        let pipeline = ExtractionPipeline()
        let indexer = SpotlightIndexer()
        self.store = store
        self.pipeline = pipeline
        self.indexer = indexer
        self.importService = ImportService(store: store, pipeline: pipeline, indexer: indexer)
        self.exportService = ExportService(store: store)

        Task {
#if DEBUG
            if LaunchOverride.flag("GRIDSCAN_FIXTURES") {
                await FixtureCatalog.seed(into: store)
            }
            if let path = LaunchOverride.value("GRIDSCAN_IMPORT") {
                // End-to-end hook: run the REAL import pipeline against a fixture file.
                await importService.importFiles(urls: [URL(fileURLWithPath: path)])
            }
#endif
            if let ids = try? await store.summaries().map(\.id) {
                PageImageStore.sweepOrphans(knownIDs: Set(ids))
            }
        }
    }
}
