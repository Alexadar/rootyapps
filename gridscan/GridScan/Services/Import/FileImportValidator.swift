import Foundation
import UniformTypeIdentifiers

/// Gate + copy-in for fileImporter URLs (security-scoped on both platforms).
enum FileImportValidator {

    static let acceptedTypes: [UTType] = [.pdf, .image]

    enum FileKind {
        case pdf
        case image
    }

    struct ValidatedFile {
        let localURL: URL       // our copy, inside the document's directory
        let kind: FileKind
        let originalName: String
    }

    static func copyIn(_ url: URL, documentID: UUID) throws -> ValidatedFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        let kind: FileKind
        if type?.conforms(to: .pdf) == true {
            kind = .pdf
        } else if type?.conforms(to: .image) == true {
            kind = .image
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let local = try PageImageStore.copyOriginal(from: url, documentID: documentID)
        return ValidatedFile(localURL: local, kind: kind,
                             originalName: url.deletingPathExtension().lastPathComponent)
    }
}
