import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A Mod Set packaged as a shareable `.seedboxset` item for the macOS share
/// sheet (AirDrop, Messages, Mail, Notes, …) and drag-out.
///
/// It carries only the validated export bytes from the same exporter used for
/// file export, so shared files are reproducible and contain no private data.
/// The system writes the bytes to a temporary file it manages and cleans up.
struct ExportableModSet: Transferable, Equatable, Sendable {
    var name: String
    var data: Data

    /// Builds a shareable item for a set, or nil if the export cannot be
    /// produced. Inheritance is resolved so the shared set is self-contained.
    static func make(
        for set: ModSet,
        mods: [ModInfo],
        in allSets: [ModSet]
    ) -> ExportableModSet? {
        guard let data = try? ModSetTransfer.exportData(for: set, mods: mods, in: allSets) else {
            return nil
        }
        return ExportableModSet(name: set.name, data: data)
    }

    /// A filesystem-safe base name for the shared file.
    var suggestedFileBaseName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let illegal = CharacterSet(charactersIn: "/\\:")
        let sanitized = trimmed
            .components(separatedBy: illegal)
            .joined(separator: "-")
        return sanitized.isEmpty ? "Mod Set" : sanitized
    }

    var suggestedFileName: String {
        "\(suggestedFileBaseName).\(SeedBoxSetDocument.fileExtension)"
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: SeedBoxSetDocument.contentType) { exportable in
            exportable.data
        }
        .suggestedFileName { $0.suggestedFileName }
    }
}
