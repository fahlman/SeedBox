import Foundation

/// Errors raised when reading an untrusted `.seedboxset` file.
enum SeedBoxSetError: Error, Equatable, LocalizedError, Sendable {
    /// The data is not valid JSON or is missing required structure.
    case malformedData
    /// The document is not a Mod Set document.
    case unsupportedKind(String)
    /// The schema version is older than this build can read.
    case unsupportedVersion(Int)
    /// The schema version is newer than this build understands.
    case futureVersion(Int)
    /// The Mod Set has no usable name.
    case missingName

    var errorDescription: String? {
        switch self {
        case .malformedData:
            return AppStrings.SeedBoxSet.malformedData
        case .unsupportedKind:
            return AppStrings.SeedBoxSet.unsupportedKind
        case .unsupportedVersion:
            return AppStrings.SeedBoxSet.unsupportedVersion
        case .futureVersion:
            return AppStrings.SeedBoxSet.futureVersion
        case .missingName:
            return AppStrings.SeedBoxSet.missingName
        }
    }
}

/// A portable, versioned representation of a Mod Set for backup, sharing, and
/// transfer between Macs.
///
/// The format deliberately carries only what a receiving Mac needs to recreate
/// a Mod Set and explain missing mods: a name and, for each mod the set
/// disables, its folder name plus identifying manifest metadata. It never
/// includes mod contents, archived mods, configs, logs, diagnostics,
/// security-scoped bookmarks, or absolute local paths.
struct SeedBoxSetDocument: Codable, Equatable, Sendable {
    /// The schema version this build writes.
    static let currentSchemaVersion = 1
    /// The oldest schema version this build can still read.
    static let minimumSupportedSchemaVersion = 1
    static let fileExtension = "seedboxset"
    /// Reverse-DNS identifier for the document type, used when the file type is
    /// registered with the system later (see #105).
    static let contentTypeIdentifier = "com.fahlsing.seedbox.modset"
    static let modSetKind = "modSet"
    static let generatorName = "Seed Box"

    var schemaVersion: Int
    var kind: String
    var generator: String
    var modSet: ExportedModSet

    struct ExportedModSet: Codable, Equatable, Sendable {
        var name: String
        var disabledMods: [ExportedMod]
    }

    /// A mod referenced by the set. Folder name identifies it for matching;
    /// the manifest fields let a receiving Mac explain a missing mod without
    /// needing the mod itself.
    struct ExportedMod: Codable, Equatable, Sendable {
        var folderName: String
        var modName: String?
        var uniqueID: String?
        var version: String?
    }
}

enum SeedBoxSetCodec {
    /// Builds an export document for a Mod Set defined by `disabledFolderNames`,
    /// enriching each entry with metadata from the installed mods where known.
    ///
    /// `disabledFolderNames` should be the set's fully resolved disabled list,
    /// so an inheriting set exports as a self-contained regular set.
    static func makeDocument(
        name: String,
        disabledFolderNames: [String],
        installedMods: [ModInfo]
    ) -> SeedBoxSetDocument {
        let modsByToken = Dictionary(
            installedMods.map { ($0.enabledFolderName.normalizedFolderToken, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )

        var seenTokens: Set<String> = []
        var disabledMods: [SeedBoxSetDocument.ExportedMod] = []
        for folderName in disabledFolderNames {
            let canonicalName = folderName.trimmingPrefix(Character("."))
            let token = canonicalName.normalizedFolderToken
            guard !token.isEmpty, !seenTokens.contains(token) else {
                continue
            }
            seenTokens.insert(token)

            let manifest = modsByToken[token]?.manifest
            disabledMods.append(
                SeedBoxSetDocument.ExportedMod(
                    folderName: canonicalName,
                    modName: manifest?.name?.trimmedNonEmpty,
                    uniqueID: manifest?.uniqueID?.trimmedNonEmpty,
                    version: manifest?.version?.trimmedNonEmpty
                )
            )
        }

        disabledMods.sort {
            $0.folderName.localizedCaseInsensitiveCompare($1.folderName) == .orderedAscending
        }

        return SeedBoxSetDocument(
            schemaVersion: SeedBoxSetDocument.currentSchemaVersion,
            kind: SeedBoxSetDocument.modSetKind,
            generator: SeedBoxSetDocument.generatorName,
            modSet: SeedBoxSetDocument.ExportedModSet(name: name, disabledMods: disabledMods)
        )
    }

    static func encode(_ document: SeedBoxSetDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    /// Decodes and validates an untrusted `.seedboxset` payload.
    ///
    /// The version and kind are checked from a minimal envelope first, so a
    /// future-version file is reported clearly even if its full structure has
    /// changed.
    static func decode(_ data: Data) throws -> SeedBoxSetDocument {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw SeedBoxSetError.malformedData
        }

        guard envelope.kind == SeedBoxSetDocument.modSetKind else {
            throw SeedBoxSetError.unsupportedKind(envelope.kind)
        }
        if envelope.schemaVersion > SeedBoxSetDocument.currentSchemaVersion {
            throw SeedBoxSetError.futureVersion(envelope.schemaVersion)
        }
        if envelope.schemaVersion < SeedBoxSetDocument.minimumSupportedSchemaVersion {
            throw SeedBoxSetError.unsupportedVersion(envelope.schemaVersion)
        }

        let document: SeedBoxSetDocument
        do {
            document = try JSONDecoder().decode(SeedBoxSetDocument.self, from: data)
        } catch {
            throw SeedBoxSetError.malformedData
        }

        guard !document.modSet.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SeedBoxSetError.missingName
        }

        return document
    }

    /// Converts a validated document into a local Mod Set definition. A fresh
    /// id is assigned so the import never collides with or overwrites an
    /// existing set by id.
    static func modSet(
        from document: SeedBoxSetDocument,
        id: String = UUID().uuidString
    ) -> ModSet {
        ModSet(
            id: id,
            name: document.modSet.name,
            disabledFolderNames: document.modSet.disabledMods.map(\.folderName)
        )
    }

    /// Minimal header used to validate version and kind before a full decode.
    private struct Envelope: Decodable {
        var schemaVersion: Int
        var kind: String
    }
}
