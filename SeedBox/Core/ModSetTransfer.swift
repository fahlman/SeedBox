import Foundation

/// File-level export and import of Mod Sets as `.seedboxset` documents,
/// independent of any UI. The view layer supplies the destination/source URL
/// (from a save/open panel); this type owns turning a Mod Set into bytes and
/// untrusted bytes back into a Mod Set.
enum ModSetTransfer {
    /// Builds the export document for a set, resolving inheritance so an
    /// inheriting set travels as a self-contained regular set.
    static func exportDocument(
        for set: ModSet,
        mods: [ModInfo],
        in allSets: [ModSet]
    ) -> SeedBoxSetDocument {
        SeedBoxSetCodec.makeDocument(
            name: set.name,
            disabledFolderNames: ModSetResolver.resolvedDisabledFolderNames(for: set, in: allSets),
            installedMods: mods
        )
    }

    /// Encodes the export document for a set to `.seedboxset` bytes.
    static func exportData(
        for set: ModSet,
        mods: [ModInfo],
        in allSets: [ModSet]
    ) throws -> Data {
        try SeedBoxSetCodec.encode(exportDocument(for: set, mods: mods, in: allSets))
    }

    /// Writes a set to a `.seedboxset` file at `url`.
    static func write(
        _ set: ModSet,
        mods: [ModInfo],
        in allSets: [ModSet],
        to url: URL
    ) throws {
        try exportData(for: set, mods: mods, in: allSets).write(to: url, options: .atomic)
    }

    /// Reads and validates a `.seedboxset` file, returning a Mod Set ready to
    /// add alongside `existingSets` (fresh id, non-colliding name). The set is
    /// not saved or applied here.
    static func importModSet(
        fromFileAt url: URL,
        existingSets: [ModSet]
    ) throws -> ModSet {
        let data: Data
        do {
            data = try BoundedFileReader.readRegularFile(
                at: url,
                maximumByteCount: SeedBoxSetDocument.maximumDocumentByteCount
            )
        } catch BoundedFileReadError.exceedsLimit {
            throw SeedBoxSetError.tooLarge
        } catch {
            throw SeedBoxSetError.malformedData
        }

        let document = try SeedBoxSetCodec.decode(data)
        return SeedBoxSetCodec.importedModSet(from: document, existingSets: existingSets)
    }
}
