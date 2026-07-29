import Foundation

enum UserSmartModSetStoreError: Error, Equatable, LocalizedError, Sendable {
    case emptyID
    case emptyName
    case emptySearchText
    case duplicateName(String)
    case duplicateID(String)
    case unsupportedSchemaVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion:
            return CocoaError(.fileReadUnknown).localizedDescription
        case .emptyID, .emptyName, .emptySearchText, .duplicateName, .duplicateID:
            return CocoaError(.fileReadCorruptFile).localizedDescription
        }
    }
}

enum UserSmartModSetStore {
    static let currentSchemaVersion = 1

    static func createSmartModSet(
        named name: String,
        searchText: String,
        existingSmartModSets: [UserSmartModSet],
        reservedNames: [String] = [],
        id: String = UUID().uuidString
    ) throws -> UserSmartModSet {
        guard let trimmedID = id.trimmedNonEmpty else {
            throw UserSmartModSetStoreError.emptyID
        }
        guard let trimmedName = name.trimmedNonEmpty else {
            throw UserSmartModSetStoreError.emptyName
        }
        guard let trimmedSearchText = searchText.trimmedNonEmpty else {
            throw UserSmartModSetStoreError.emptySearchText
        }

        let existingNames = existingSmartModSets.map(\.name) + reservedNames
        if existingNames.contains(where: { namesMatch($0, trimmedName) }) {
            throw UserSmartModSetStoreError.duplicateName(trimmedName)
        }

        return UserSmartModSet(
            id: trimmedID,
            name: trimmedName,
            searchText: trimmedSearchText
        )
    }

    static func loadSmartModSets(
        from storeURL: URL,
        fileManager: FileManager = .default
    ) throws -> [UserSmartModSet] {
        try createStoreDirectoryIfNeeded(for: storeURL, fileManager: fileManager)

        guard fileManager.fileExists(atPath: storeURL.path) else {
            return []
        }

        let data = try Data(contentsOf: storeURL)
        let decoder = PropertyListDecoder()

        do {
            let storedSmartModSets = try decoder.decode(StoredUserSmartModSets.self, from: data)
            guard storedSmartModSets.schemaVersion == currentSchemaVersion else {
                throw UserSmartModSetStoreError.unsupportedSchemaVersion(
                    storedSmartModSets.schemaVersion
                )
            }
            return try normalizeSmartModSetsForSaving(storedSmartModSets.smartModSets)
        } catch let error as UserSmartModSetStoreError {
            throw error
        } catch let versionedFormatError {
            do {
                let smartModSets = try decoder.decode([UserSmartModSet].self, from: data)
                return try normalizeSmartModSetsForSaving(smartModSets)
            } catch {
                throw versionedFormatError
            }
        }
    }

    static func saveSmartModSets(
        _ smartModSets: [UserSmartModSet],
        to storeURL: URL,
        fileManager: FileManager = .default
    ) throws {
        try createStoreDirectoryIfNeeded(for: storeURL, fileManager: fileManager)
        let normalizedSmartModSets = try normalizeSmartModSetsForSaving(smartModSets)
        let storedSmartModSets = StoredUserSmartModSets(
            schemaVersion: currentSchemaVersion,
            smartModSets: normalizedSmartModSets
        )

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(storedSmartModSets)
        try data.write(to: storeURL, options: .atomic)
    }

    static func preserveUnreadableStore(
        at storeURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let recoveryDirectory = storeURL
            .deletingLastPathComponent()
            .appendingPathComponent("Recovered Data", isDirectory: true)
        try fileManager.createDirectory(
            at: recoveryDirectory,
            withIntermediateDirectories: true
        )

        let recoveryURL = recoveryDirectory
            .appendingPathComponent("Smart Mod Sets \(UUID().uuidString)")
            .appendingPathExtension("plist")
        try fileManager.moveItem(at: storeURL, to: recoveryURL)
        return recoveryURL
    }

    private struct StoredUserSmartModSets: Codable {
        var schemaVersion: Int
        var smartModSets: [UserSmartModSet]
    }

    private static func createStoreDirectoryIfNeeded(
        for storeURL: URL,
        fileManager: FileManager
    ) throws {
        let directoryURL = storeURL.deletingLastPathComponent()
        guard !fileManager.directoryExists(at: directoryURL) else {
            return
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private static func normalizeSmartModSetsForSaving(
        _ smartModSets: [UserSmartModSet]
    ) throws -> [UserSmartModSet] {
        var seenIDs: Set<String> = []
        var seenNames: Set<String> = []
        var normalizedSmartModSets: [UserSmartModSet] = []

        for smartModSet in smartModSets {
            guard let normalizedSmartModSet = normalized(smartModSet) else {
                throw validationError(for: smartModSet)
            }

            guard !seenIDs.contains(normalizedSmartModSet.id) else {
                throw UserSmartModSetStoreError.duplicateID(normalizedSmartModSet.id)
            }

            let normalizedName = normalizedSmartModSet.name.normalizedSearchText
            guard !seenNames.contains(normalizedName) else {
                throw UserSmartModSetStoreError.duplicateName(normalizedSmartModSet.name)
            }

            seenIDs.insert(normalizedSmartModSet.id)
            seenNames.insert(normalizedName)
            normalizedSmartModSets.append(normalizedSmartModSet)
        }

        return sortSmartModSets(normalizedSmartModSets)
    }

    private static func normalized(_ smartModSet: UserSmartModSet) -> UserSmartModSet? {
        guard let id = smartModSet.id.trimmedNonEmpty,
              let name = smartModSet.name.trimmedNonEmpty,
              let searchText = smartModSet.searchText.trimmedNonEmpty
        else {
            return nil
        }

        return UserSmartModSet(
            id: id,
            name: name,
            searchText: searchText,
            systemImageName: smartModSet.systemImageName.trimmedNonEmpty
                ?? UserSmartModSet.defaultSystemImageName
        )
    }

    private static func validationError(for smartModSet: UserSmartModSet) -> UserSmartModSetStoreError {
        if smartModSet.id.trimmedNonEmpty == nil {
            return .emptyID
        }
        if smartModSet.name.trimmedNonEmpty == nil {
            return .emptyName
        }
        return .emptySearchText
    }

    private static func sortSmartModSets(_ smartModSets: [UserSmartModSet]) -> [UserSmartModSet] {
        smartModSets.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}
