import Foundation

enum ModSetStoreError: Error, Equatable, LocalizedError, Sendable {
    case cannotDeleteDefaultSet
    case duplicateSetName(String)
    case missingSet(String)

    var errorDescription: String? {
        switch self {
        case .cannotDeleteDefaultSet:
            return "The default mod set cannot be deleted."
        case .duplicateSetName(let name):
            return "A mod set named \(name) already exists."
        case .missingSet(let id):
            return "Mod set \(id) was not found."
        }
    }
}

enum ModSetStore {
    static let defaultSetID = "default"
    static let defaultSetName = "Default"

    static func loadSets(
        install: StardewInstall,
        currentMods: [ModInfo],
        fileManager: FileManager = .default
    ) throws -> [ModSet] {
        try createStoreDirectoryIfNeeded(install: install, fileManager: fileManager)

        let defaultSet = try loadOrCreateDefaultSet(
            install: install,
            currentMods: currentMods,
            fileManager: fileManager
        )

        let userSetURLs = try fileManager.contentsOfDirectory(
            at: install.modSetDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "plist" }
        .filter { $0.deletingPathExtension().lastPathComponent != defaultSetID }

        let userSets: [ModSet] = userSetURLs.compactMap { url in
            guard let stored = loadStoredSet(at: url) else {
                return nil
            }

            return ModSet(
                id: stored.id,
                name: stored.name,
                disabledFolderNames: normalizeFolderNames(stored.disabledFolderNames),
                isDefault: false
            )
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return [defaultSet] + userSets
    }

    static func createSet(
        named name: String,
        from sourceSet: ModSet,
        existingSets: [ModSet]
    ) throws -> ModSet {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return ModSet(
                id: UUID().uuidString,
                name: "Untitled Set",
                disabledFolderNames: normalizeFolderNames(sourceSet.disabledFolderNames),
                isDefault: false
            )
        }

        let normalizedName = trimmedName.lowercased()
        let nameAlreadyExists = existingSets.contains { set in
            set.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedName
        }
        if nameAlreadyExists {
            throw ModSetStoreError.duplicateSetName(trimmedName)
        }

        return ModSet(
            id: UUID().uuidString,
            name: trimmedName,
            disabledFolderNames: normalizeFolderNames(sourceSet.disabledFolderNames),
            isDefault: false
        )
    }

    static func saveSet(
        _ set: ModSet,
        install: StardewInstall,
        fileManager: FileManager = .default
    ) throws {
        try createStoreDirectoryIfNeeded(install: install, fileManager: fileManager)
        let storedID = set.isDefault ? defaultSetID : set.id
        let storedSet = StoredModSet(
            id: storedID,
            name: set.isDefault ? defaultSetName : set.name,
            disabledFolderNames: normalizeFolderNames(set.disabledFolderNames)
        )
        try saveStoredSet(
            storedSet,
            to: urlForSetID(storedID, install: install),
            fileManager: fileManager
        )
    }

    static func deleteSet(
        _ set: ModSet,
        install: StardewInstall,
        fileManager: FileManager = .default
    ) throws {
        guard !set.isDefault else {
            throw ModSetStoreError.cannotDeleteDefaultSet
        }

        let url = urlForSetID(set.id, install: install)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ModSetStoreError.missingSet(set.id)
        }

        try fileManager.removeItem(at: url)
    }

    @discardableResult
    static func applySet(
        _ set: ModSet,
        install: StardewInstall,
        fileManager: FileManager = .default
    ) throws -> Int {
        let mods = try ModLibrary.scan(install: install, fileManager: fileManager)
        let disabledFolderNames = Set(
            normalizeFolderNames(set.disabledFolderNames).map(\.normalizedFolderToken)
        )

        var changedCount = 0
        for mod in mods {
            let shouldBeEnabled = !disabledFolderNames.contains(mod.enabledFolderName.normalizedFolderToken)
            guard mod.isEnabled != shouldBeEnabled else {
                continue
            }

            _ = try ModLibrary.setEnabled(mod, enabled: shouldBeEnabled, fileManager: fileManager)
            changedCount += 1
        }

        return changedCount
    }

    static func snapshotSet(
        id: String,
        name: String,
        from mods: [ModInfo],
        isDefault: Bool = false
    ) -> ModSet {
        ModSet(
            id: id,
            name: name,
            disabledFolderNames: normalizeFolderNames(
                mods.filter { !$0.isEnabled }.map(\.enabledFolderName)
            ),
            isDefault: isDefault
        )
    }

    private struct StoredModSet: Codable {
        var id: String
        var name: String
        var disabledFolderNames: [String]
    }

    private static func loadOrCreateDefaultSet(
        install: StardewInstall,
        currentMods: [ModInfo],
        fileManager: FileManager
    ) throws -> ModSet {
        let defaultURL = urlForSetID(defaultSetID, install: install)
        if let stored = loadStoredSet(at: defaultURL) {
            return ModSet(
                id: defaultSetID,
                name: defaultSetName,
                disabledFolderNames: normalizeFolderNames(stored.disabledFolderNames),
                isDefault: true
            )
        }

        let baselineSet = snapshotSet(
            id: defaultSetID,
            name: defaultSetName,
            from: currentMods,
            isDefault: true
        )

        let storedSet = StoredModSet(
            id: baselineSet.id,
            name: baselineSet.name,
            disabledFolderNames: baselineSet.disabledFolderNames
        )
        try saveStoredSet(storedSet, to: defaultURL, fileManager: fileManager)
        return baselineSet
    }

    private static func createStoreDirectoryIfNeeded(
        install: StardewInstall,
        fileManager: FileManager
    ) throws {
        guard fileManager.directoryExists(at: install.modSetDirectoryURL) else {
            try fileManager.createDirectory(
                at: install.modSetDirectoryURL,
                withIntermediateDirectories: true
            )
            return
        }
    }

    private static func loadStoredSet(at url: URL) -> StoredModSet? {
        guard
            let data = try? Data(contentsOf: url),
            let storedSet = try? PropertyListDecoder().decode(StoredModSet.self, from: data)
        else {
            return nil
        }

        return storedSet
    }

    private static func saveStoredSet(
        _ storedSet: StoredModSet,
        to url: URL,
        fileManager: FileManager
    ) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(storedSet)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try data.write(to: url, options: .atomic)
    }

    private static func urlForSetID(_ setID: String, install: StardewInstall) -> URL {
        install.modSetDirectoryURL.appendingPathComponent("\(setID).plist")
    }

    private static func normalizeFolderNames(_ folderNames: [String]) -> [String] {
        var seenTokens: Set<String> = []
        var normalizedFolderNames: [String] = []

        for folderName in folderNames {
            guard let trimmed = folderName.trimmedNonEmpty else {
                continue
            }

            let canonicalName = trimmed.trimmingPrefix(Character("."))
            let token = canonicalName.normalizedFolderToken
            guard !token.isEmpty else {
                continue
            }
            guard !seenTokens.contains(token) else {
                continue
            }

            seenTokens.insert(token)
            normalizedFolderNames.append(canonicalName)
        }

        return normalizedFolderNames.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}
